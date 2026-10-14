#pragma once
#include "Browser.h"
#include "Formatting.h"

namespace flow {
class AppController {
    bool historyReady_=false, queryPending_=false, feedPending_=false, commandPending_=false;
    bool targetPending_=false,pastePending_=false,cleanupPending_=false,inTick_=false;
    uint64_t cleanupGeneration_=0;
    double restoreAt_=0;
    int phase_=0;
    bool frozen_=false, stopSent_=false;
    bool pasteDelivered_=false;
    double startAt_=0, stopAt_=0, stableAt_=0, lastHealth_=0, pasteAt_=0, drainedAt_=0;
    std::wstring stable_;
    Recovery recovery_;
    HWND owner_{};
    void notify()noexcept{try{changed();}catch(...){lastError=E_FAIL;}}
    void command(const std::wstring& action,std::function<void(Json)> fn,const std::wstring& expected=L"") {
        commandPending_=true;auto token=session.generation;
        browser.call(action,[this,token,fn](Json j){if(!session.current(token))return;commandPending_=false;if(j.HasKey(L"error")){fail(std::wstring(j.GetNamedString(L"error")));return;}fn(j);},expected);
    }
    void feed() {
        if(feedPending_||phase_<1||phase_>3)return;auto chunk=microphone.audio.peekBatch(3200);if(chunk.samples.empty())return;
        auto token=session.generation;feedPending_=true;
        browser.call(L"feedAudio",[this,token,id=chunk.id](Json j){if(!session.current(token))return;feedPending_=false;if(j.HasKey(L"error")){fail(L"Captured audio could not reach ChatGPT. No incomplete text was pasted.");return;}if(!microphone.audio.acknowledgeThrough(id)){fail(L"Audio delivery order failed");return;}feed();},wide(base64(chunk.samples.data(),chunk.samples.size()*sizeof(float))));
    }
    void page(Json state) {
        if(state.HasKey(L"error"))return;
        browser.needsLogin=state.GetNamedBoolean(L"login",false);
        browser.hasDraft=!state.GetNamedString(L"text",L"").empty();
        bool ready=state.GetNamedBoolean(L"ready",false),temporary=state.GetNamedBoolean(L"temporary",false);
        browser.connected=ready&&temporary&&!browser.needsLogin;
        if(browser.needsLogin)browser.status=L"Sign in to ChatGPT";
        else if(browser.hasDraft && !busy(session.state))browser.status=L"A ChatGPT draft is present. Clear it before recording.";
        else if(browser.connected)browser.status=L"ChatGPT connected";
        if(!busy(session.state)) {
            if(ready&&!temporary&&!browser.hasDraft)browser.call(L"prepare",[](Json){});
            if(browser.connected)recovery_.ready();return;
        }
        if(browser.needsLogin){fail(L"Open Manage connection and sign in to ChatGPT");return;}
        if(state.GetNamedBoolean(L"audioFailed",false)){fail(L"Audio buffer filled. No incomplete text was pasted.");return;}
        if(phase_==0 && ready && !commandPending_ && !cleanupPending_) {
            if(browser.hasDraft){fail(L"ChatGPT contains a draft; it was preserved. Clear it first.");return;}
            if(!temporary){command(L"prepare",[](Json){});return;}
            command(L"captureNative",[this](Json){phase_=1;});return;
        }
        if(phase_==1&&!commandPending_){command(L"start",[this](Json){phase_=2;});return;}
        if(phase_==2 && state.GetNamedBoolean(L"recording",false) && !commandPending_) {
            if(!state.GetNamedBoolean(L"audioAttached",false)){fail(L"ChatGPT did not attach the buffered microphone");return;}
            command(L"playAudio",[this](Json){phase_=3;recorderMs=(now()-startAt_)*1000;});return;
        }
        if(phase_==3 && session.state==State::recording && (state.GetNamedBoolean(L"transcribing",false)||ready)) {
            if(microphone.audio.pending()>0){fail(L"The page stopped before all audio was delivered. Text was not pasted as complete.");return;}finish();
        }
        if(session.state!=State::transcribing||phase_!=3)return;
        if(!frozen_ && microphone.audio.pending()==0&&!feedPending_&&!commandPending_) {command(L"freezeAudio",[this](Json){frozen_=true;});return;}
        if(frozen_&&!stopSent_&&state.GetNamedNumber(L"audioQueued",1)<=0&&!commandPending_){
            drainedAt_=now();
            if(state.GetNamedBoolean(L"recording",false)){command(L"stop",[this](Json){stopSent_=true;stopAcknowledgedAt=now();});return;}
            stopSent_=true;
        }
        if(stopSent_&&ready&&!state.GetNamedBoolean(L"recording",false)&&!state.GetNamedBoolean(L"transcribing",false)) {
            auto text=std::wstring(state.GetNamedString(L"text",L""));
            if(text.empty()){fail(L"No speech returned. Nothing was saved or pasted.");return;}
            if(text!=stable_){stable_=text;stableAt_=now();return;}
            if(now()-stableAt_>=0.2&&!commandPending_&&!targetPending_)complete(text);
        }else stableAt_=0;
    }
    void complete(const std::wstring& raw) {
        phase_=4;
        textReadyAt=now();auto text=store.settings.GetNamedBoolean(L"readableFormatting",true)?readableTranscript(raw):raw;
        try{store.save(text,raw);}catch(...){fail(L"History could not be saved; the ChatGPT draft was kept.");return;}
        historySavedAt=now();result=text;microphone.stop();cleanupPending_=true;auto cleanup=++cleanupGeneration_;
        browser.call(L"endAudio",[this,raw,cleanup](Json ended){
            if(cleanup!=cleanupGeneration_)return;
            if(ended.HasKey(L"error")){cleanupPending_=false;browser.hasDraft=true;draftNotice=L" Your text is safe in History. Reconnect before recording again.";return;}
            browser.call(L"discard",[this,cleanup](Json j){
                if(cleanup!=cleanupGeneration_)return;cleanupPending_=false;browser.hasDraft=j.HasKey(L"error");
                if(!busy(session.state))browser.active=false;
                draftNotice=browser.hasDraft?L" Your ChatGPT draft was kept; clear it before recording again.":L"";
            },raw);
        });
        session.state=session.local?State::finished:State::inserting;
        message=session.local?L"Saved to History.":L"Adding your text…";pasteAt_=0;pastePending_=false;notify();
    }
public:
    Store store;
    Browser browser;
    Microphone microphone;
    Insertion insertion;
    Session session;
    std::wstring message=L"Connect ChatGPT to begin",result,draftNotice;
    double recorderMs=0,textReadyAt=0,historySavedAt=0,pasteDeliveredAt=0,stopAcknowledgedAt=0;
    long lastError=S_OK;
    bool hotkeyReady=false;
    std::function<void()> changed=[]{};
    explicit AppController(HWND owner,bool fixture=false):owner_(owner),store(fixture?std::filesystem::temp_directory_path()/(L"FlowGPT-UI-"+guid()):dataPath()),browser(store.root()/L"WebView2",fixture) {
        try{store.load();historyReady_=true;}catch(...){message=L"Local history/settings could not be read. Existing data was preserved; recording is disabled.";}
        if(fixture&&historyReady_)store.save(L"आज के लिए तीन काम हैं:\n1. Send the project proposal.\n2. Grocery shopping कर लेना.\n3. Review meeting notes.");
        browser.interrupted=[this]{if(busy(session.state))fail(L"Browser interrupted during recording; no incomplete result was pasted.");};
        browser.failed=[this](long code){lastError=code;if(busy(session.state))fail(L"A connection operation failed. Any saved text remains in History.");};browser.init();
    }
    ~AppController(){session.cancel();++cleanupGeneration_;changed=[]{};microphone.stop();insertion.cancel(owner_);browser.close();}
    void begin(bool preview=false) {
        if(session.state==State::starting||session.state==State::recording){finish();return;}
        if(!historyReady_){message=L"Resolve local history storage before recording";changed();return;}
        if(busy(session.state))return;
        DWORD pid{};GetWindowThreadProcessId(GetForegroundWindow(),&pid);preview=preview||pid==GetCurrentProcessId();
        session.begin(preview);result.clear();draftNotice.clear();stable_.clear();phase_=0;frozen_=stopSent_=false;queryPending_=feedPending_=commandPending_=false;pasteAt_=0;drainedAt_=0;startAt_=now();recorderMs=0;
        message=L"Starting microphone…";
        // Capture must not wait for cross-process UI Automation providers.
        textReadyAt=historySavedAt=pasteDeliveredAt=stopAcknowledgedAt=0;
        microphone.start(std::wstring(store.settings.GetNamedString(L"microphone",L"")));
        targetPending_=!preview;if(targetPending_)insertion.beginCapture();
        browser.active=true;browser.hide();notify();
    }
    void finish() {
        if(session.state==State::starting){session.stopRequested=true;microphone.stop();session.state=State::transcribing;stopAt_=now();message=L"Finishing captured speech…";changed();return;}
        if(!session.stop())return;microphone.stop();stopAt_=now();message=L"Waiting for ChatGPT transcription…";changed();
    }
    void fail(const std::wstring& error) {
        bool owned=browser.active;session.cancel();++cleanupGeneration_;cleanupPending_=false;targetPending_=pastePending_=false;microphone.stop();insertion.cancel(owner_);browser.active=false;session.state=State::error;message=error;phase_=4;queryPending_=feedPending_=commandPending_=false;
        if(owned&&browser.ready()){browser.call(L"cancel",[](Json){});browser.call(L"endAudio",[](Json){});}notify();
    }
    void cancel() { fail(L"Dictation cancelled");session.state=State::cancelled;changed(); }
    void tickImpl() {
        if(restoreAt_&&now()>=restoreAt_){restoreAt_=0;insertion.restoreLater(owner_);}
        browser.tick();
        if(targetPending_){auto captured=insertion.captured();if(captured.has_value()){targetPending_=false;if(!*captured){fail(L"Click an editable text area, then use your shortcut. This field may not support automatic insertion.");return;}}}
        if(busy(session.state)&&session.state!=State::inserting) {
            if(FAILED(microphone.error())){fail(L"Microphone access failed or device disconnected. Check Windows microphone privacy and selected device.");return;}
            if(session.state==State::starting&&microphone.firstMs()>0){session.state=State::recording;message=L"Recording your voice";changed();}
            if(session.state==State::starting&&now()-startAt_>3){fail(L"No microphone frames arrived. Check Windows microphone privacy and device.");return;}
            if(phase_<3&&now()-startAt_>20){fail(L"ChatGPT recorder did not initialize within 20 seconds. Reconnect and retry.");return;}
            if(session.state==State::transcribing&&now()-stopAt_>150){fail(L"Transcription timed out. Check the saved browser draft.");return;}
            feed();
        }
        if(session.state==State::inserting) {
            if(!pastePending_){if(GetAsyncKeyState(VK_CONTROL)&0x8000||GetAsyncKeyState(VK_MENU)&0x8000||GetAsyncKeyState(VK_SHIFT)&0x8000)return;
                pastePending_=true;insertion.beginPaste(owner_,result);return;}
            auto pasted=insertion.pasted();if(!pasted.has_value())return;
            pasteDelivered_=*pasted;pasteDeliveredAt=now();restoreAt_=now()+0.7;
            session.state=pasteDelivered_?State::attempted:State::finished;
            message=(pasteDelivered_?L"Saved to History and sent to your text area.":L"Saved to History. This text area could not accept automatic paste.")+draftNotice;notify();
            return;
        }
        if(!queryPending_&&browser.ready()){queryPending_=true;auto token=session.generation;browser.call(L"state",[this,token](Json j){queryPending_=false;if(token!=session.generation)return;page(j);});}
        if(!busy(session.state)&&!cleanupPending_&&now()-lastHealth_>=3){lastHealth_=now();if(!browser.connected&&now()-browser.loadedAt>20&&recovery_.request(now(),false,browser.needsLogin,browser.hasDraft))browser.reload();}
    }
    void tick()noexcept{
        if(inTick_)return;inTick_=true;struct Reset{bool& flag;~Reset(){flag=false;}}reset{inTick_};
        try{tickImpl();}catch(const winrt::hresult_error& e){lastError=e.code().value;try{fail(L"A recording operation failed. Any saved text remains in History.");}catch(...){session.cancel();session.state=State::error;}}catch(...){lastError=E_FAIL;try{fail(L"A recording operation failed. Any saved text remains in History.");}catch(...){session.cancel();session.state=State::error;}}
    }
    std::wstring diagnostics() const {Json o;o.Insert(L"version",JValue::CreateStringValue(L"1.0.0-windows-preview"));o.Insert(L"architecture",JValue::CreateStringValue(L"x64"));o.Insert(L"state",JValue::CreateNumberValue(int(session.state)));o.Insert(L"hotkeyRegistered",JValue::CreateBooleanValue(hotkeyReady));o.Insert(L"connected",JValue::CreateBooleanValue(browser.connected));o.Insert(L"firstAudioMs",JValue::CreateNumberValue(microphone.firstMs()));o.Insert(L"recorderStartMs",JValue::CreateNumberValue(recorderMs));o.Insert(L"historyEntries",JValue::CreateNumberValue(double(store.entries.size())));o.Insert(L"captureError",JValue::CreateNumberValue(microphone.error()));return std::wstring(o.Stringify());}
};
}
