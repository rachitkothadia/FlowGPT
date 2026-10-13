#pragma once
#include "Browser.h"

namespace flow {
class AppController {
    bool historyReady_=false, queryPending_=false, feedPending_=false, commandPending_=false;
    int phase_=0;
    bool frozen_=false, stopSent_=false;
    double startAt_=0, stopAt_=0, stableAt_=0, lastHealth_=0, pasteAt_=0;
    std::wstring stable_;
    Recovery recovery_;
    HWND owner_{};
    void command(const std::wstring& action,std::function<void(Json)> fn,const std::wstring& expected=L"") {
        commandPending_=true;auto token=session.generation;
        browser.call(action,[this,token,fn](Json j){if(!session.current(token))return;commandPending_=false;if(j.HasKey(L"error")){fail(std::wstring(j.GetNamedString(L"error")));return;}fn(j);},expected);
    }
    void feed() {
        if(feedPending_||phase_<1||phase_>3)return;auto chunk=microphone.audio.peek();if(chunk.samples.empty())return;
        auto token=session.generation;feedPending_=true;
        browser.call(L"feedAudio",[this,token,id=chunk.id](Json j){if(!session.current(token))return;feedPending_=false;if(j.HasKey(L"error")){fail(L"Captured audio could not reach ChatGPT. No incomplete text was pasted.");return;}if(!microphone.audio.acknowledge(id))fail(L"Audio delivery order failed");},wide(base64(chunk.samples.data(),chunk.samples.size()*sizeof(float))));
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
        if(phase_==0 && ready && !commandPending_) {
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
            if(state.GetNamedBoolean(L"recording",false)){command(L"stop",[this](Json){stopSent_=true;});return;}
            stopSent_=true;
        }
        if(stopSent_&&ready) {
            auto text=std::wstring(state.GetNamedString(L"text",L""));
            if(text.empty()){fail(L"No speech returned. Nothing was saved or pasted.");return;}
            if(text!=stable_){stable_=text;stableAt_=now();return;}
            if(now()-stableAt_>=0.6&&!commandPending_)complete(text);
        }
    }
    void complete(const std::wstring& text) {
        phase_=4;
        try{store.save(text);}catch(...){fail(L"History could not be saved; the ChatGPT draft was kept.");return;}
        result=text;auto token=session.generation;
        command(L"endAudio",[this,text,token](Json){
            browser.call(L"discard",[this,token](Json j){
                if(!session.current(token))return;browser.active=false;microphone.stop();phase_=4;
                draftNotice=j.HasKey(L"error")?L" ChatGPT draft was kept; clear it before the next recording.":L"";
                if(session.local){session.state=State::finished;message=L"Saved to History."+draftNotice;changed();return;}
                session.state=State::inserting;message=L"Inserting into your original field…";pasteAt_=0;changed();
            },text);
        });
    }
public:
    Store store;
    Browser browser;
    Microphone microphone;
    Insertion insertion;
    Session session;
    std::wstring message=L"Connect ChatGPT to begin",result,draftNotice;
    double recorderMs=0;
    bool hotkeyReady=false;
    std::function<void()> changed=[]{};
    explicit AppController(HWND owner,bool fixture=false):owner_(owner),store(fixture?std::filesystem::temp_directory_path()/(L"FlowGPT-UI-"+guid()):dataPath()),browser(store.root()/L"WebView2",fixture) {
        try{store.load();historyReady_=true;}catch(...){message=L"Local history/settings could not be read. Existing data was preserved; recording is disabled.";}
        if(fixture&&historyReady_)store.save(L"आज के लिए तीन काम हैं:\n1. Send the project proposal.\n2. Grocery shopping कर लेना.\n3. Review meeting notes.");
        browser.interrupted=[this]{if(busy(session.state))fail(L"Browser interrupted during recording; no incomplete result was pasted.");};browser.init();
    }
    ~AppController(){microphone.stop();insertion.restore(owner_);browser.close();}
    void begin(bool preview=false) {
        if(session.state==State::starting||session.state==State::recording){finish();return;}
        if(!historyReady_){message=L"Resolve local history storage before recording";changed();return;}
        if(busy(session.state))return;
        DWORD pid{};GetWindowThreadProcessId(GetForegroundWindow(),&pid);preview=preview||pid==GetCurrentProcessId();
        session.begin(preview);result.clear();draftNotice.clear();stable_.clear();phase_=0;frozen_=stopSent_=false;queryPending_=feedPending_=commandPending_=false;pasteAt_=0;startAt_=now();recorderMs=0;
        message=L"Starting microphone…";
        // Capture must not wait for cross-process UI Automation providers.
        microphone.start(std::wstring(store.settings.GetNamedString(L"microphone",L"")));
        if(!preview&&!insertion.capture()){fail(L"Focus an editable non-password field, then use your shortcut");return;}
        browser.active=true;browser.hide();changed();
    }
    void finish() {
        if(session.state==State::starting){session.stopRequested=true;microphone.stop();session.state=State::transcribing;stopAt_=now();message=L"Finishing captured speech…";changed();return;}
        if(!session.stop())return;microphone.stop();stopAt_=now();message=L"Waiting for ChatGPT transcription…";changed();
    }
    void fail(const std::wstring& error) {
        bool owned=browser.active;session.cancel();microphone.stop();insertion.restore(owner_);browser.active=false;session.state=State::error;message=error;phase_=4;queryPending_=feedPending_=commandPending_=false;
        if(owned&&browser.ready()){browser.call(L"cancel",[](Json){});browser.call(L"endAudio",[](Json){});}changed();
    }
    void cancel() { fail(L"Dictation cancelled");session.state=State::cancelled;changed(); }
    void tick() {
        browser.tick();
        if(busy(session.state)&&session.state!=State::inserting) {
            if(FAILED(microphone.error())){fail(L"Microphone access failed or device disconnected. Check Windows microphone privacy and selected device.");return;}
            if(session.state==State::starting&&microphone.firstMs()>0){session.state=State::recording;message=L"Recording your voice";changed();}
            if(session.state==State::starting&&now()-startAt_>3){fail(L"No microphone frames arrived. Check Windows microphone privacy and device.");return;}
            if(phase_<3&&now()-startAt_>20){fail(L"ChatGPT recorder did not initialize within 20 seconds. Reconnect and retry.");return;}
            if(session.state==State::transcribing&&now()-stopAt_>150){fail(L"Transcription timed out. Check the saved browser draft.");return;}
            feed();
        }
        if(session.state==State::inserting) {
            if(pasteAt_==0){if(GetAsyncKeyState(VK_CONTROL)&0x8000||GetAsyncKeyState(VK_MENU)&0x8000||GetAsyncKeyState(VK_SHIFT)&0x8000)return;
                bool sent=insertion.paste(owner_,result);pasteAt_=now();message=sent?L"Paste delivered; checking destination…":L"Saved in History; destination could not accept paste.";}
            if(now()-pasteAt_>=0.7){insertion.restore(owner_);session.state=State::attempted;message=L"Saved in History. Paste was attempted; confirm it in your destination."+draftNotice;changed();}
            return;
        }
        if(!queryPending_&&browser.ready()){queryPending_=true;auto token=session.generation;browser.call(L"state",[this,token](Json j){queryPending_=false;if(token!=session.generation)return;page(j);});}
        if(!busy(session.state)&&now()-lastHealth_>=3){lastHealth_=now();if(!browser.connected&&now()-browser.loadedAt>20&&recovery_.request(now(),false,browser.needsLogin,browser.hasDraft))browser.reload();}
    }
    std::wstring diagnostics() const {Json o;o.Insert(L"version",JValue::CreateStringValue(L"1.0.0-windows-preview"));o.Insert(L"architecture",JValue::CreateStringValue(L"x64"));o.Insert(L"state",JValue::CreateNumberValue(int(session.state)));o.Insert(L"hotkeyRegistered",JValue::CreateBooleanValue(hotkeyReady));o.Insert(L"connected",JValue::CreateBooleanValue(browser.connected));o.Insert(L"firstAudioMs",JValue::CreateNumberValue(microphone.firstMs()));o.Insert(L"recorderStartMs",JValue::CreateNumberValue(recorderMs));o.Insert(L"historyEntries",JValue::CreateNumberValue(double(store.entries.size())));o.Insert(L"captureError",JValue::CreateNumberValue(microphone.error()));return std::wstring(o.Stringify());}
};
}
