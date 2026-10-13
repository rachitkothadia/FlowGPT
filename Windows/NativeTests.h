#pragma once
#include "Browser.h"
#include "Hud.h"

namespace flow {
inline LRESULT CALLBACK probeProc(HWND hwnd,UINT message,WPARAM w,LPARAM l){
    if(message==WM_CREATE){HWND edit=CreateWindowExW(0,L"EDIT",L"",WS_CHILD|WS_VISIBLE|ES_MULTILINE|WS_BORDER,20,20,450,140,hwnd,reinterpret_cast<HMENU>(42),GetModuleHandleW(nullptr),nullptr);SetFocus(edit);return 0;}
    if(message==WM_ACTIVATE&&LOWORD(w)!=WA_INACTIVE){SetFocus(GetDlgItem(hwnd,42));return 0;}
    if(message==WM_DESTROY){PostQuitMessage(0);return 0;}
    return DefWindowProcW(hwnd,message,w,l);
}
inline int insertionProbe(){WNDCLASSW c{};c.lpfnWndProc=probeProc;c.hInstance=GetModuleHandleW(nullptr);c.lpszClassName=L"FlowGPTInsertionProbe";RegisterClassW(&c);HWND w=CreateWindowExW(0,c.lpszClassName,L"FlowGPT insertion test fixture",WS_OVERLAPPEDWINDOW|WS_VISIBLE,100,100,520,240,nullptr,nullptr,c.hInstance,nullptr);ShowWindow(w,SW_SHOW);SetForegroundWindow(w);SetFocus(GetDlgItem(w,42));MSG m{};while(GetMessageW(&m,nullptr,0,0)>0){TranslateMessage(&m);DispatchMessageW(&m);}return 0;}
inline void messages(){MSG m{};while(PeekMessageW(&m,nullptr,0,0,PM_REMOVE)){TranslateMessage(&m);DispatchMessageW(&m);}}
inline bool putFixtureClipboard(HWND owner,const std::wstring& text,UINT custom=0){
    if(!OpenClipboard(owner))return false;EmptyClipboard();
    auto put=[](UINT format,const void* bytes,size_t size){HGLOBAL h=GlobalAlloc(GMEM_MOVEABLE,size);if(!h)return false;void* p=GlobalLock(h);if(!p){GlobalFree(h);return false;}memcpy(p,bytes,size);GlobalUnlock(h);if(!SetClipboardData(format,h)){GlobalFree(h);return false;}return true;};
    bool good=put(CF_UNICODETEXT,text.c_str(),(text.size()+1)*sizeof(wchar_t));const char payload[]="private fixture format";if(custom)good=put(custom,payload,sizeof(payload))&&good;CloseClipboard();return good;
}
inline std::wstring fixtureClipboard(HWND owner){if(!OpenClipboard(owner))return L"";HANDLE h=GetClipboardData(CF_UNICODETEXT);const auto* text=static_cast<const wchar_t*>(GlobalLock(h));std::wstring value=text?text:L"";if(text)GlobalUnlock(h);CloseClipboard();return value;}
inline int nativeTests(){
    auto root=std::filesystem::temp_directory_path()/(L"FlowGPT-NativeTests-"+guid());std::filesystem::create_directories(root);
    Json checks, details;
    auto check=[&](const wchar_t* name,bool value){checks.Insert(name,JValue::CreateBooleanValue(value));};
    try{
        Store a(root/L"store");a.load();a.save(L"हिन्दी English मराठी 🎤\nC++ Rust");a.setting(L"appearance",JValue::CreateStringValue(L"Dark"));
        Store b(root/L"store");b.load();check(L"historySurvivesReopen",b.entries.size()==1&&b.entries[0].text==a.entries[0].text);check(L"settingsSurviveReopen",b.settings.GetNamedString(L"appearance")==L"Dark");
        for(int i=0;i<105;++i)a.save(L"Fixture "+std::to_wstring(i));check(L"historyBounded",a.entries.size()==100);a.erase(a.entries[0].id);Store c(root/L"store");c.load();check(L"deletePersists",c.entries.size()==99);
        atomicWrite(root/L"store"/L"history.json",L"broken");bool corrupt=false;try{Store d(root/L"store");d.load();}catch(...){corrupt=true;}check(L"corruptionReportedWithoutOverwrite",corrupt&&read(root/L"store"/L"history.json")==L"broken");
        check(L"hotkeyRegistration",RegisterHotKey(nullptr,89,MOD_CONTROL|MOD_ALT|MOD_NOREPEAT,VK_F11)!=FALSE);UnregisterHotKey(nullptr,89);
        STARTUPINFOW startupInfo{sizeof(startupInfo)};PROCESS_INFORMATION process{};std::wstring command=L"\""+exePath()+L"\" --insertion-probe";
        bool launched=CreateProcessW(nullptr,command.data(),nullptr,nullptr,FALSE,0,nullptr,nullptr,&startupInfo,&process)!=FALSE;check(L"nativeEditorProbeLaunched",launched);
        if(launched){
            double until=now()+8;HWND target{};while(now()<until&&!target){messages();target=FindWindowW(L"FlowGPTInsertionProbe",nullptr);Sleep(30);}check(L"nativeEditorProbeWindow",target!=nullptr);
            if(target){HWND field=GetDlgItem(target,42);SetForegroundWindow(target);Sleep(250);messages();Insertion insertion;bool captured=insertion.capture();check(L"nativeFocusedFieldCaptured",captured);
                std::wstring speech=L"हिन्दी English मराठी 🎤\nC++ keyword";bool pasted=captured&&insertion.paste(target,speech);check(L"nativePasteEventsDelivered",pasted);Sleep(750);messages();wchar_t text[512]{};SendMessageW(field,WM_GETTEXT,512,reinterpret_cast<LPARAM>(text));check(L"nativeMixedScriptPasteExact",std::wstring(text)==speech);insertion.restore(target);
                UINT custom=RegisterClipboardFormatW(L"FlowGPT disposable fixture format");check(L"clipboardFixturePrepared",putFixtureClipboard(target,L"Original clipboard",custom));ClipboardLease lease;
                check(L"clipboardTranscriptPublished",lease.write(target,speech)&&fixtureClipboard(target)==speech);lease.restore(target);
                check(L"clipboardTextRestored",fixtureClipboard(target)==L"Original clipboard");bool customExact=false;if(OpenClipboard(target)){HANDLE h=GetClipboardData(custom);auto bytes=static_cast<const char*>(GlobalLock(h));customExact=bytes&&GlobalSize(h)>=23&&std::string(bytes)=="private fixture format";if(bytes)GlobalUnlock(h);CloseClipboard();}check(L"clipboardCustomFormatRestored",customExact);
                ClipboardLease newer;newer.write(target,speech);putFixtureClipboard(target,L"User copied newer text");newer.restore(target);check(L"newUserCopyPreserved",fixtureClipboard(target)==L"User copied newer text");
                insertion.capture();SendMessageW(field,EM_SETREADONLY,TRUE,0);check(L"readOnlyTargetRefused",!insertion.valid());SendMessageW(field,EM_SETREADONLY,FALSE,0);
                insertion.capture();SetForegroundWindow(GetShellWindow());check(L"changedForegroundRefused",!insertion.valid());PostMessageW(target,WM_CLOSE,0,0);
            }
            WaitForSingleObject(process.hProcess,3000);CloseHandle(process.hThread);CloseHandle(process.hProcess);
        }
        Hud hud;hud.update(State::recording,0.7);messages();check(L"popupVisible",IsWindowVisible(hud.handle())!=FALSE);check(L"popupNonactivating",(GetWindowLongPtrW(hud.handle(),GWL_EXSTYLE)&WS_EX_NOACTIVATE)!=0);hud.update(State::finished,0);check(L"popupHidesAfterFinish",IsWindowVisible(hud.handle())==FALSE);
        Browser browser(root/L"browser",true);browser.init();bool response=false;Json result;
        auto request=[&](const std::wstring& action,const std::wstring& expected=L""){
            response=false;browser.call(action,[&](Json j){result=j;response=true;},expected);double deadline=now()+10;
            while(!response&&now()<deadline){messages();browser.tick();Sleep(10);}if(result.HasKey(L"error"))details.Insert(action,result.GetNamedValue(L"error"));return response&&!result.HasKey(L"error");
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
        check(L"openingAudioDurationRetained",result.GetNamedNumber(L"duration",0)>=0.9);
        const double energy=result.GetNamedNumber(L"energy",0);check(L"decodedOpeningAudioEnergyRetained",energy>=0.036&&energy<=0.054);
        details.Insert(L"syntheticAudioDurationSeconds",JValue::CreateNumberValue(result.GetNamedNumber(L"duration",0)));
        details.Insert(L"syntheticAudioEnergy",JValue::CreateNumberValue(energy));
        check(L"changedDraftRefused",!request(L"discard",L"different text"));check(L"matchingDraftRemoved",request(L"discard",L"नमस्ते English मराठी 🎤"));check(L"audioCleanup",request(L"endAudio"));
        check(L"browserProfileFixtureWritten",request(L"fixtureStorage",L"Persistent own profile"));browser.reload();deadline=now()+30;while(!browser.ready()&&now()<deadline){messages();Sleep(20);}
        check(L"browserProfileSurvivesReconnect",request(L"fixtureStorage")&&result.GetNamedString(L"value",L"")==L"Persistent own profile");browser.close();
    }catch(const std::exception& e){checks.Insert(L"exception",JValue::CreateStringValue(wide(e.what())));}catch(const winrt::hresult_error& e){checks.Insert(L"exception",JValue::CreateNumberValue(e.code().value));}
    bool pass=true;for(auto pair:checks)if(pair.Value().ValueType()!=winrt::Windows::Data::Json::JsonValueType::Boolean||!pair.Value().GetBoolean())pass=false;
    Json report;report.Insert(L"passed",JValue::CreateBooleanValue(pass));report.Insert(L"checks",checks);report.Insert(L"details",details);report.Insert(L"type",JValue::CreateStringValue(L"Windows isolated native storage/window/WebView2 audio fixtures; no account or physical microphone"));atomicWrite(std::filesystem::path(exePath()).parent_path()/L"native-tests.json",std::wstring(report.Stringify()));return pass?0:1;
}
}
