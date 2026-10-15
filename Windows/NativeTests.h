#pragma once
#include "Browser.h"
#include "Hud.h"
#include "AppController.h"

namespace flow {
inline bool richProbe=false;
inline LRESULT CALLBACK probeProc(HWND hwnd,UINT message,WPARAM w,LPARAM l){
    if(message==WM_CREATE){HWND edit=CreateWindowExW(0,richProbe?L"RICHEDIT50W":L"EDIT",L"",WS_CHILD|WS_VISIBLE|ES_MULTILINE|WS_BORDER,20,20,450,90,hwnd,reinterpret_cast<HMENU>(42),GetModuleHandleW(nullptr),nullptr);CreateWindowExW(0,L"EDIT",L"",WS_CHILD|WS_VISIBLE|WS_BORDER,20,115,450,30,hwnd,reinterpret_cast<HMENU>(43),GetModuleHandleW(nullptr),nullptr);SetFocus(edit);return 0;}
    if(message==WM_APP+5){SetFocus(GetDlgItem(hwnd,int(w)));return 0;}
    if(message==WM_ACTIVATE&&LOWORD(w)!=WA_INACTIVE){SetFocus(GetDlgItem(hwnd,42));return 0;}
    if(message==WM_DESTROY){PostQuitMessage(0);return 0;}
    return DefWindowProcW(hwnd,message,w,l);
}
inline int insertionProbe(bool rich=false){richProbe=rich;HMODULE library=rich?LoadLibraryW(L"msftedit.dll"):nullptr;if(rich&&!library)return 1;WNDCLASSW c{};c.lpfnWndProc=probeProc;c.hInstance=GetModuleHandleW(nullptr);c.lpszClassName=L"FlowGPTInsertionProbe";RegisterClassW(&c);HWND w=CreateWindowExW(0,c.lpszClassName,L"FlowGPT insertion test fixture",WS_OVERLAPPEDWINDOW|WS_VISIBLE,100,100,520,240,nullptr,nullptr,c.hInstance,nullptr);ShowWindow(w,SW_SHOW);SetForegroundWindow(w);SetFocus(GetDlgItem(w,42));MSG m{};while(GetMessageW(&m,nullptr,0,0)>0){TranslateMessage(&m);DispatchMessageW(&m);}if(library)FreeLibrary(library);return 0;}
inline void messages(){MSG m{};while(PeekMessageW(&m,nullptr,0,0,PM_REMOVE)){TranslateMessage(&m);DispatchMessageW(&m);}}
inline bool putFixtureClipboard(HWND owner,const std::wstring& text,UINT custom=0){
    if(!OpenClipboard(owner))return false;EmptyClipboard();
    auto put=[](UINT format,const void* bytes,size_t size){HGLOBAL h=GlobalAlloc(GMEM_MOVEABLE,size);if(!h)return false;void* p=GlobalLock(h);if(!p){GlobalFree(h);return false;}memcpy(p,bytes,size);GlobalUnlock(h);if(!SetClipboardData(format,h)){GlobalFree(h);return false;}return true;};
    bool good=put(CF_UNICODETEXT,text.c_str(),(text.size()+1)*sizeof(wchar_t));const char payload[]="private fixture format";if(custom)good=put(custom,payload,sizeof(payload))&&good;CloseClipboard();return good;
}
inline std::wstring fixtureClipboard(HWND owner){if(!OpenClipboard(owner))return L"";HANDLE h=GetClipboardData(CF_UNICODETEXT);const auto* text=static_cast<const wchar_t*>(GlobalLock(h));std::wstring value=text?text:L"";if(text)GlobalUnlock(h);CloseClipboard();return value;}
inline bool fixtureGraphics(HWND owner){
    const DWORD pixels[]{0x00112233,0x00445566,0x00778899,0x00aabbcc};HBITMAP bitmap=CreateBitmap(2,2,1,32,pixels);
    HDC dc=CreateEnhMetaFileW(nullptr,nullptr,nullptr,L"FlowGPT\0Disposable fixture\0");if(dc){MoveToEx(dc,0,0,nullptr);LineTo(dc,24,24);}HENHMETAFILE metafile=dc?CloseEnhMetaFile(dc):nullptr;
    if(!bitmap||!metafile||!OpenClipboard(owner)){if(bitmap)DeleteObject(bitmap);if(metafile)DeleteEnhMetaFile(metafile);return false;}
    bool good=true;if(!SetClipboardData(CF_BITMAP,bitmap)){DeleteObject(bitmap);good=false;}if(!SetClipboardData(CF_ENHMETAFILE,metafile)){DeleteEnhMetaFile(metafile);good=false;}CloseClipboard();return good;
}
inline std::pair<std::vector<unsigned char>,std::vector<unsigned char>> graphicsBytes(HWND owner){
    std::pair<std::vector<unsigned char>,std::vector<unsigned char>> result;if(!OpenClipboard(owner))return result;
    HBITMAP bitmap=static_cast<HBITMAP>(GetClipboardData(CF_BITMAP));BITMAP description{};
    if(bitmap&&GetObjectW(bitmap,sizeof(description),&description)){auto size=description.bmWidthBytes*std::abs(description.bmHeight);if(size>0&&size<1024*1024){result.first.resize(size);if(GetBitmapBits(bitmap,size,result.first.data())!=size)result.first.clear();}}
    HENHMETAFILE metafile=static_cast<HENHMETAFILE>(GetClipboardData(CF_ENHMETAFILE));UINT size=metafile?GetEnhMetaFileBits(metafile,0,nullptr):0;
    if(size&&size<1024*1024){result.second.resize(size);if(GetEnhMetaFileBits(metafile,size,result.second.data())!=size)result.second.clear();}CloseClipboard();return result;
}
inline int nativeTests(){
    auto root=std::filesystem::temp_directory_path()/(L"FlowGPT-NativeTests-"+guid());std::filesystem::create_directories(root);
    Json checks, details;
    auto check=[&](const wchar_t* name,bool value){checks.Insert(name,JValue::CreateBooleanValue(value));};
    try{
        Store a(root/L"store");a.load();a.save(L"हिन्दी English मराठी 🎤\nC++ Rust");a.setting(L"appearance",JValue::CreateStringValue(L"Dark"));
        Store b(root/L"store");b.load();check(L"historySurvivesReopen",b.entries.size()==1&&b.entries[0].text==a.entries[0].text);check(L"settingsSurviveReopen",b.settings.GetNamedString(L"appearance")==L"Dark");
        auto startupRoot=L"Software\\FlowGPT\\Tests\\"+guid();StartupRegistration login(startupRoot+L"\\Run",startupRoot+L"\\Preference");
        login.synchronize();check(L"startupDefaultsToRegistered",login.enabled()&&login.preference()==true);
        login.set(false);login.synchronize();check(L"startupExplicitOptOutPersists",!login.enabled()&&login.preference()==false);
        login.set(true);StartupRegistration relocated(startupRoot+L"\\Run",startupRoot+L"\\Preference",L"C:\\FlowGPT fixture\\FlowGPT.exe");
        relocated.synchronize();check(L"startupRepairsMovedExecutable",relocated.enabled()&&!login.enabled());RegDeleteTreeW(HKEY_CURRENT_USER,startupRoot.c_str());
        for(int i=0;i<105;++i)a.save(L"Fixture "+std::to_wstring(i));check(L"historyBounded",a.entries.size()==100);a.erase(a.entries[0].id);Store c(root/L"store");c.load();check(L"deletePersists",c.entries.size()==99);
        atomicWrite(root/L"store"/L"history.json",L"broken");bool corrupt=false;try{Store d(root/L"store");d.load();}catch(...){corrupt=true;}check(L"corruptionReportedWithoutOverwrite",corrupt&&read(root/L"store"/L"history.json")==L"broken");
        check(L"hotkeyRegistration",RegisterHotKey(nullptr,89,MOD_CONTROL|MOD_ALT|MOD_NOREPEAT,VK_F11)!=FALSE);UnregisterHotKey(nullptr,89);
        STARTUPINFOW startupInfo{sizeof(startupInfo)};PROCESS_INFORMATION process{};std::wstring command=L"\""+exePath()+L"\" --insertion-probe";
        bool launched=CreateProcessW(nullptr,command.data(),nullptr,nullptr,FALSE,0,nullptr,nullptr,&startupInfo,&process)!=FALSE;check(L"nativeEditorProbeLaunched",launched);
        if(launched){
            double until=now()+8;HWND target{};while(now()<until&&!target){messages();target=FindWindowW(L"FlowGPTInsertionProbe",nullptr);Sleep(30);}check(L"nativeEditorProbeWindow",target!=nullptr);
            if(target){HWND field=GetDlgItem(target,42);SetForegroundWindow(target);Sleep(250);messages();
                Insertion nullPatterns([](IUIAutomationElement*,PATTERNID,REFIID,void** result){*result=nullptr;return S_OK;});check(L"successfulNullPatternsSafelyRefused",!nullPatterns.capture());
                Insertion insertion;bool captured=insertion.capture();check(L"nativeFocusedFieldCaptured",captured);
                std::wstring speech=L"हिन्दी English मराठी 🎤\nC++ keyword";bool pasted=captured&&insertion.paste(target,speech);check(L"nativePasteEventsDelivered",pasted);Sleep(750);messages();wchar_t text[512]{};SendMessageW(field,WM_GETTEXT,512,reinterpret_cast<LPARAM>(text));check(L"nativeMixedScriptPasteExact",std::wstring(text)==speech);insertion.restore(target);
                UINT custom=RegisterClipboardFormatW(L"FlowGPT disposable fixture format");check(L"clipboardFixturePrepared",putFixtureClipboard(target,L"Original clipboard",custom));check(L"clipboardGraphicsPrepared",fixtureGraphics(target));auto graphics=graphicsBytes(target);ClipboardLease lease;
                check(L"clipboardTranscriptPublished",lease.write(target,speech)&&fixtureClipboard(target)==speech);lease.restore(target);
                check(L"clipboardTextRestored",fixtureClipboard(target)==L"Original clipboard");bool customExact=false;if(OpenClipboard(target)){HANDLE h=GetClipboardData(custom);auto bytes=static_cast<const char*>(GlobalLock(h));customExact=bytes&&GlobalSize(h)>=23&&std::string(bytes)=="private fixture format";if(bytes)GlobalUnlock(h);CloseClipboard();}check(L"clipboardCustomFormatRestored",customExact);
                auto restoredGraphics=graphicsBytes(target);check(L"clipboardBitmapRestored",!graphics.first.empty()&&restoredGraphics.first==graphics.first);check(L"clipboardMetafileRestored",!graphics.second.empty()&&restoredGraphics.second==graphics.second);
                ClipboardLease newer;newer.write(target,speech);putFixtureClipboard(target,L"User copied newer text");newer.restore(target);check(L"newUserCopyPreserved",fixtureClipboard(target)==L"User copied newer text");
                insertion.capture();SendMessageW(field,EM_SETREADONLY,TRUE,0);check(L"readOnlyTargetRefused",!insertion.valid());SendMessageW(field,EM_SETREADONLY,FALSE,0);
                SendMessageW(field,WM_SETTEXT,0,reinterpret_cast<LPARAM>(L""));SendMessageW(target,WM_APP+5,42,0);Sleep(100);
                bool armed=false;unsigned queries=0;Insertion fieldRace([&](IUIAutomationElement* element,PATTERNID pattern,REFIID iid,void** value){
                    HRESULT result=element->GetCurrentPatternAs(pattern,iid,value);if(armed&&++queries==2)SendMessageW(target,WM_APP+5,43,0);return result;});
                bool raceCaptured=fieldRace.capture();armed=true;check(L"sameWindowFocusSwitchRefused",raceCaptured&&!fieldRace.paste(target,L"Private fixture must not appear"));
                Sleep(100);wchar_t firstText[256]{},secondText[256]{};SendMessageW(field,WM_GETTEXT,256,reinterpret_cast<LPARAM>(firstText));SendMessageW(GetDlgItem(target,43),WM_GETTEXT,256,reinterpret_cast<LPARAM>(secondText));check(L"sameWindowFocusSwitchPastesNeitherField",!firstText[0]&&!secondText[0]);fieldRace.restore(target);SendMessageW(target,WM_APP+5,42,0);Sleep(100);
                insertion.capture();SetForegroundWindow(GetShellWindow());check(L"changedForegroundRefused",!insertion.valid());PostMessageW(target,WM_CLOSE,0,0);
            }
            WaitForSingleObject(process.hProcess,3000);CloseHandle(process.hThread);CloseHandle(process.hProcess);
        }
        STARTUPINFOW richStartup{sizeof(richStartup)};PROCESS_INFORMATION richProcess{};std::wstring richCommand=L"\""+exePath()+L"\" --insertion-probe --rich";
        bool richLaunched=CreateProcessW(nullptr,richCommand.data(),nullptr,nullptr,FALSE,0,nullptr,nullptr,&richStartup,&richProcess)!=FALSE;check(L"richEditorProbeLaunched",richLaunched);
        if(richLaunched){double until=now()+8;HWND target{};while(now()<until&&!target){messages();target=FindWindowW(L"FlowGPTInsertionProbe",nullptr);Sleep(30);}
            if(target){SetForegroundWindow(target);Sleep(250);messages();Insertion insertion;bool captured=insertion.capture();check(L"richEditorCaptured",captured);auto speech=std::wstring(L"हिन्दी English मराठी C++ Rust");check(L"richEditorPasteDelivered",captured&&insertion.paste(target,speech));Sleep(750);messages();wchar_t value[256]{};SendMessageW(GetDlgItem(target,42),WM_GETTEXT,256,reinterpret_cast<LPARAM>(value));check(L"richEditorMixedScriptExact",std::wstring(value)==speech);insertion.restore(target);PostMessageW(target,WM_CLOSE,0,0);}else check(L"richEditorWindow",false);
            WaitForSingleObject(richProcess.hProcess,3000);CloseHandle(richProcess.hThread);CloseHandle(richProcess.hProcess);}
        Hud hud;hud.update(State::recording,0.7);messages();check(L"popupVisible",IsWindowVisible(hud.handle())!=FALSE);check(L"popupNonactivating",(GetWindowLongPtrW(hud.handle(),GWL_EXSTYLE)&WS_EX_NOACTIVATE)!=0);
        RECT before{},after{};GetWindowRect(hud.handle(),&before);for(int i=0;i<5;++i){hud.update(State::recording,i*0.1);messages();}GetWindowRect(hud.handle(),&after);check(L"popupPositionStableDuringRecording",EqualRect(&before,&after)!=FALSE);
        hud.update(State::finished,0);check(L"popupHidesAfterFinish",IsWindowVisible(hud.handle())==FALSE);
        hud.update(State::error,0);check(L"errorPopupDoesNotDisappearAsSuccess",IsWindowVisible(hud.handle())!=FALSE);hud.update(State::finished,0);
        Browser browser(root/L"browser",true);browser.init();bool response=false;Json result;
        auto request=[&](const std::wstring& action,const std::wstring& expected=L""){
            response=false;browser.call(action,[&](Json j){result=j;response=true;},expected);double deadline=now()+10;
            while(!response&&now()<deadline){messages();browser.tick();Sleep(10);}if(result.HasKey(L"error"))details.Insert(action,result.GetNamedValue(L"error"));return response&&!result.HasKey(L"error");
        };
        double deadline=now()+30;while(!browser.ready()&&now()<deadline){messages();Sleep(20);}Sleep(200);messages();
        check(L"webviewFixtureReady",browser.ready());check(L"oldBrowserMicrophoneDecisionRemoved",browser.microphoneDecisionReset);check(L"temporaryChatVerified",request(L"state")&&result.GetNamedBoolean(L"temporary",false));
        check(L"browserHidden",!browser.visible());check(L"nativeStreamCreated",request(L"captureNative"));
        std::vector<float> samples(16000);for(size_t i=0;i<samples.size();++i)samples[i]=float(0.3*std::sin(i*2*3.141592653589793*440/16000));
        AudioQueue opening;for(size_t i=0;i<samples.size();i+=160)opening.push(samples.data()+i,160);bool delivered=true;
        while(opening.pending()){auto batch=opening.peekBatch(3200);if(!request(L"feedAudio",wide(base64(batch.samples.data(),batch.samples.size()*4)))||!opening.acknowledgeThrough(batch.id)){delivered=false;break;}}
        check(L"openingAudioQueued",delivered&&opening.pending()==0);check(L"recorderStarted",request(L"start"));
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
        check(L"microphonePolicySurvivesReconnect",browser.microphoneDecisionReset);check(L"browserProfileSurvivesReconnect",request(L"fixtureStorage")&&result.GetNamedString(L"value",L"")==L"Persistent own profile");browser.close();
        {
            AppController controller(nullptr,true);auto wait=[&](auto predicate,double seconds){auto until=now()+seconds;while(now()<until){messages();controller.tick();if(predicate())return true;Sleep(20);}return predicate();};
            check(L"controllerConnectionReady",wait([&]{return controller.browser.connected;},30));
            controller.begin(true);check(L"controllerNativeCaptureStarts",wait([&]{return controller.session.state==State::recording&&controller.recorderMs>0;},10));
            auto keepRecordingUntil=now()+0.7;while(now()<keepRecordingUntil){messages();controller.tick();Sleep(20);}
            check(L"visibleDictateBehindRecorderDoesNotPrematurelyFinish",controller.session.state==State::recording&&controller.microphone.running());
            controller.finish();check(L"controllerFinishesThroughHistory",wait([&]{return !busy(controller.session.state);},15)&&controller.session.state==State::finished&&controller.store.entries.size()==2);
            check(L"controllerReturnedTranscriptExact",controller.result==L"नमस्ते English मराठी 🎤"&&controller.store.entries.front().raw==controller.result);
            bool signalReturned=false;Json signal;controller.browser.call(L"fixtureSignal",[&](Json j){signal=j;signalReturned=true;});
            check(L"controllerFixtureAudioHasSignal",wait([&]{return signalReturned;},8)&&signal.GetNamedBoolean(L"signal",false)&&signal.GetNamedNumber(L"duration",0)>0.3);
            check(L"controllerDraftClearedBeforeNextRecording",wait([&]{return !controller.browser.active&&!controller.browser.hasDraft;},8));
            controller.begin(true);controller.session.local=false; // Model an unavailable external insertion target, without typing into any real app.
            check(L"missingTargetDoesNotStopNativeCapture",wait([&]{return controller.session.state==State::recording&&controller.recorderMs>0;},10));
            auto secondUntil=now()+0.4;while(now()<secondUntil){messages();controller.tick();Sleep(20);}controller.finish();
            check(L"missingTargetStillSavesTranscript",wait([&]{return !busy(controller.session.state);},15)&&controller.session.state==State::finished&&controller.store.entries.size()==3&&controller.result==L"नमस्ते English मराठी 🎤");
            check(L"missingTargetShowsHistoryRecovery",controller.message.find(L"Saved to History")!=std::wstring::npos);
        }
    }catch(const std::exception& e){checks.Insert(L"exception",JValue::CreateStringValue(wide(e.what())));}catch(const winrt::hresult_error& e){checks.Insert(L"exception",JValue::CreateNumberValue(e.code().value));}
    bool pass=true;for(auto pair:checks)if(pair.Value().ValueType()!=winrt::Windows::Data::Json::JsonValueType::Boolean||!pair.Value().GetBoolean())pass=false;
    Json report;report.Insert(L"passed",JValue::CreateBooleanValue(pass));report.Insert(L"checks",checks);report.Insert(L"details",details);report.Insert(L"type",JValue::CreateStringValue(L"Windows isolated native storage/window/WebView2 audio fixtures; no account or physical microphone"));atomicWrite(std::filesystem::path(exePath()).parent_path()/L"native-tests.json",std::wstring(report.Stringify()));return pass?0:1;
}
}
