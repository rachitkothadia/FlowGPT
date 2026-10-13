#pragma once
#include "Browser.h"
#include "Hud.h"

namespace flow {
inline void messages(){MSG m{};while(PeekMessageW(&m,nullptr,0,0,PM_REMOVE)){TranslateMessage(&m);DispatchMessageW(&m);}}
inline int nativeTests(){
    auto root=std::filesystem::temp_directory_path()/(L"FlowGPT-NativeTests-"+guid());std::filesystem::create_directories(root);
    Json checks;
    auto check=[&](const wchar_t* name,bool value){checks.Insert(name,JValue::CreateBooleanValue(value));};
    try{
        Store a(root/L"store");a.load();a.save(L"हिन्दी English मराठी 🎤\nC++ Rust");a.setting(L"appearance",JValue::CreateStringValue(L"Dark"));
        Store b(root/L"store");b.load();check(L"historySurvivesReopen",b.entries.size()==1&&b.entries[0].text==a.entries[0].text);check(L"settingsSurviveReopen",b.settings.GetNamedString(L"appearance")==L"Dark");
        for(int i=0;i<105;++i)a.save(L"Fixture "+std::to_wstring(i));check(L"historyBounded",a.entries.size()==100);a.erase(a.entries[0].id);Store c(root/L"store");c.load();check(L"deletePersists",c.entries.size()==99);
        atomicWrite(root/L"store"/L"history.json",L"broken");bool corrupt=false;try{Store d(root/L"store");d.load();}catch(...){corrupt=true;}check(L"corruptionReportedWithoutOverwrite",corrupt&&read(root/L"store"/L"history.json")==L"broken");
        check(L"hotkeyRegistration",RegisterHotKey(nullptr,89,MOD_CONTROL|MOD_ALT|MOD_NOREPEAT,VK_F11)!=FALSE);UnregisterHotKey(nullptr,89);
        Hud hud;hud.update(State::recording,0.7);messages();check(L"popupVisible",IsWindowVisible(hud.handle())!=FALSE);check(L"popupNonactivating",(GetWindowLongPtrW(hud.handle(),GWL_EXSTYLE)&WS_EX_NOACTIVATE)!=0);hud.update(State::finished,0);check(L"popupHidesAfterFinish",IsWindowVisible(hud.handle())==FALSE);
        Browser browser(root/L"browser",true);browser.init();bool response=false;Json result;
        auto request=[&](const std::wstring& action,const std::wstring& expected=L""){
            response=false;browser.call(action,[&](Json j){result=j;response=true;},expected);double deadline=now()+10;
            while(!response&&now()<deadline){messages();browser.tick();Sleep(10);}return response&&!result.HasKey(L"error");
        };
        double deadline=now()+30;while(!browser.ready()&&now()<deadline){messages();Sleep(20);}Sleep(200);messages();
        check(L"webviewFixtureReady",browser.ready());check(L"temporaryChatVerified",request(L"state")&&result.GetNamedBoolean(L"temporary",false));
        check(L"browserHidden",!browser.visible());check(L"nativeStreamCreated",request(L"captureNative"));
        std::vector<float> samples(16000);for(size_t i=0;i<samples.size();++i)samples[i]=float(0.3*std::sin(i*2*3.141592653589793*440/16000));
        check(L"openingAudioQueued",request(L"feedAudio",wide(base64(samples.data(),samples.size()*4))));check(L"recorderStarted",request(L"start"));
        deadline=now()+5;bool attached=false;while(now()<deadline){if(request(L"state")&&result.GetNamedBoolean(L"audioAttached",false)){attached=true;break;}Sleep(30);messages();}check(L"nativeAudioAttached",attached);
        check(L"audioPlaybackStarted",request(L"playAudio"));check(L"audioFrozen",request(L"freezeAudio"));
        deadline=now()+6;bool drained=false;while(now()<deadline){Sleep(100);messages();if(request(L"state")&&result.GetNamedNumber(L"audioQueued",1)<=0){drained=true;break;}}check(L"openingAudioDrained",drained);
        Sleep(150);messages();check(L"stopRecorder",request(L"stop"));
        deadline=now()+8;bool transcript=false;while(now()<deadline){Sleep(100);messages();if(request(L"state")&&result.GetNamedString(L"text",L"")==L"नमस्ते English मराठी 🎤"){transcript=true;break;}}check(L"mixedScriptFixtureReturned",transcript);
        check(L"decodedRecordedSignal",request(L"fixtureSignal")&&result.GetNamedBoolean(L"signal",false));
        check(L"changedDraftRefused",!request(L"discard",L"different text"));check(L"matchingDraftRemoved",request(L"discard",L"नमस्ते English मराठी 🎤"));check(L"audioCleanup",request(L"endAudio"));browser.close();
    }catch(const std::exception& e){checks.Insert(L"exception",JValue::CreateStringValue(wide(e.what())));}catch(const winrt::hresult_error& e){checks.Insert(L"exception",JValue::CreateNumberValue(e.code().value));}
    bool pass=true;for(auto pair:checks)if(pair.Value().ValueType()!=winrt::Windows::Data::Json::JsonValueType::Boolean||!pair.Value().GetBoolean())pass=false;
    Json report;report.Insert(L"passed",JValue::CreateBooleanValue(pass));report.Insert(L"checks",checks);report.Insert(L"type",JValue::CreateStringValue(L"Windows isolated native storage/window/WebView2 audio fixtures; no account or physical microphone"));atomicWrite(std::filesystem::path(exePath()).parent_path()/L"native-tests.json",std::wstring(report.Stringify()));return pass?0:1;
}
}
