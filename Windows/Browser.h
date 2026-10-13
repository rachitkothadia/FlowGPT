#pragma once
#include "Platform.h"
#include <WebView2.h>
#include <WebView2EnvironmentOptions.h>
#include <map>

namespace flow {
class Browser {
    struct Lifetime { bool alive=true;unsigned generation=0; };
    std::shared_ptr<Lifetime> lifetime_=std::make_shared<Lifetime>();
    struct Pending { double deadline; std::function<void(Json)> callback; };
    ComPtr<ICoreWebView2Environment> environment_;
    ComPtr<ICoreWebView2Controller> controller_;
    ComPtr<ICoreWebView2> web_;
    std::map<int,Pending> pending_;
    int next_=1;
    HWND window_{};
    std::filesystem::path profile_;
    bool shown_=false,fixture_=false,initialized_=false;
    static bool trusted(const std::wstring& source) {
        try { auto uri=winrt::Windows::Foundation::Uri(source); return uri.SchemeName()==L"https" && uri.Host()==L"chatgpt.com"; } catch(...) { return false; }
    }
    static LRESULT CALLBACK procedure(HWND hwnd,UINT message,WPARAM w,LPARAM l) {
        auto self=reinterpret_cast<Browser*>(GetWindowLongPtrW(hwnd,GWLP_USERDATA));
        if(self && message==WM_CLOSE){self->hide();return 0;}
        if(self && message==WM_SIZE){self->resize();return 0;}
        return DefWindowProcW(hwnd,message,w,l);
    }
    void resize(){if(controller_){RECT r{};GetClientRect(window_,&r);controller_->put_Bounds(r);}}
public:
    bool connected=false, needsLogin=false, hasDraft=false, active=false;
    std::wstring status=L"Connecting to ChatGPT…";
    double loadedAt=now();
    std::function<void()> interrupted;
    static Json error(const std::wstring& message){Json v;v.Insert(L"error",JValue::CreateStringValue(message));return v;}
    explicit Browser(std::filesystem::path profile = dataPath()/L"WebView2", bool fixture=false): profile_(std::move(profile)),fixture_(fixture){}
    ~Browser(){lifetime_->alive=false;close();if(window_)DestroyWindow(window_);}
    bool visible() const{return shown_;}
    bool ready() const{return initialized_ && web_;}
    void show(){shown_=true;SetLayeredWindowAttributes(window_,0,255,LWA_ALPHA);ShowWindow(window_,SW_SHOW);SetForegroundWindow(window_);}
    void hide(){shown_=false;SetLayeredWindowAttributes(window_,0,1,LWA_ALPHA);ShowWindow(window_,SW_SHOWNOACTIVATE);SetWindowPos(window_,HWND_BOTTOM,0,0,0,0,SWP_NOMOVE|SWP_NOSIZE|SWP_NOACTIVATE);}
    void failPending(const std::wstring& message){auto pending=std::move(pending_);pending_.clear();for(auto& p:pending)p.second.callback(error(message));}
    void close(){++lifetime_->generation;initialized_=false;connected=false;failPending(L"Browser connection closed");if(controller_)controller_->Close();web_.Reset();controller_.Reset();environment_.Reset();}
    void reload(){if(active||hasDraft||needsLogin)return;close();init();}
    void init(){
        auto guard=lifetime_;unsigned generation=++guard->generation;
        initialized_=false;connected=false;loadedAt=now();
        if(!window_){WNDCLASSW c{};c.lpfnWndProc=procedure;c.hInstance=GetModuleHandleW(nullptr);c.lpszClassName=L"FlowGPTBrowserHost";c.hCursor=LoadCursorW(nullptr,IDC_ARROW);RegisterClassW(&c);
            window_=CreateWindowExW(WS_EX_TOOLWINDOW|WS_EX_LAYERED,c.lpszClassName,L"FlowGPT · ChatGPT connection",WS_OVERLAPPEDWINDOW,CW_USEDEFAULT,CW_USEDEFAULT,960,740,nullptr,nullptr,c.hInstance,nullptr);SetWindowLongPtrW(window_,GWLP_USERDATA,reinterpret_cast<LONG_PTR>(this));hide();}
        std::filesystem::create_directories(profile_);
        auto options=Microsoft::WRL::Make<CoreWebView2EnvironmentOptions>();
        // The explicit native shortcut starts audio in a background page. Browser
        // autoplay policy otherwise leaves AudioContext.resume() awaiting a DOM gesture.
        options->put_AdditionalBrowserArguments(L"--autoplay-policy=no-user-gesture-required");
        HRESULT hr=CreateCoreWebView2EnvironmentWithOptions(nullptr,profile_.c_str(),options.Get(),Microsoft::WRL::Callback<ICoreWebView2CreateCoreWebView2EnvironmentCompletedHandler>([this,guard,generation](HRESULT result,ICoreWebView2Environment* env)->HRESULT{
            if(!guard->alive||generation!=guard->generation)return S_OK;
            if(FAILED(result)){status=L"WebView2 runtime unavailable. Install Microsoft Edge WebView2 Runtime.";return S_OK;}environment_=env;
            env->CreateCoreWebView2Controller(window_,Microsoft::WRL::Callback<ICoreWebView2CreateCoreWebView2ControllerCompletedHandler>([this,guard,generation](HRESULT created,ICoreWebView2Controller* controller)->HRESULT{
                if(!guard->alive||generation!=guard->generation){if(controller)controller->Close();return S_OK;}
                if(FAILED(created)){status=L"ChatGPT browser could not initialize";return S_OK;}controller_=controller;controller_->get_CoreWebView2(&web_);resize();
                EventRegistrationToken token{};
                web_->add_WebMessageReceived(Microsoft::WRL::Callback<ICoreWebView2WebMessageReceivedEventHandler>([this,guard,generation](ICoreWebView2*,ICoreWebView2WebMessageReceivedEventArgs* args)->HRESULT{
                    if(!guard->alive||generation!=guard->generation)return S_OK;
                    LPWSTR source{},raw{};args->get_Source(&source);args->get_WebMessageAsJson(&raw);
                    bool valid=source&&trusted(source);std::wstring payload=raw?raw:L"";CoTaskMemFree(source);CoTaskMemFree(raw);if(!valid)return S_OK;
                    try{auto j=Json::Parse(payload);if(j.GetNamedString(L"type",L"")!=L"flow-response")return S_OK;int id=int(j.GetNamedNumber(L"id",0));auto it=pending_.find(id);if(it!=pending_.end()){auto fn=std::move(it->second.callback);pending_.erase(it);fn(j.GetNamedObject(L"result"));}}catch(...){/* Untrusted or malformed messages never cause insertion. */}return S_OK;
                }).Get(),&token);
                web_->add_NavigationStarting(Microsoft::WRL::Callback<ICoreWebView2NavigationStartingEventHandler>([this,guard,generation](ICoreWebView2*,ICoreWebView2NavigationStartingEventArgs* args)->HRESULT{if(!guard->alive||generation!=guard->generation)return S_OK;LPWSTR uri{};args->get_Uri(&uri);needsLogin=uri&&!trusted(uri);CoTaskMemFree(uri);initialized_=false;connected=false;loadedAt=now();failPending(L"Browser navigated");return S_OK;}).Get(),&token);
                web_->add_NavigationCompleted(Microsoft::WRL::Callback<ICoreWebView2NavigationCompletedEventHandler>([this,guard,generation](ICoreWebView2*,ICoreWebView2NavigationCompletedEventArgs* args)->HRESULT{if(!guard->alive||generation!=guard->generation)return S_OK;BOOL success{};args->get_IsSuccess(&success);initialized_=success;status=success?L"Checking ChatGPT connection…":L"Connection failed; retrying when idle";return S_OK;}).Get(),&token);
                web_->add_ProcessFailed(Microsoft::WRL::Callback<ICoreWebView2ProcessFailedEventHandler>([this,guard,generation](ICoreWebView2*,ICoreWebView2ProcessFailedEventArgs*)->HRESULT{if(!guard->alive||generation!=guard->generation)return S_OK;initialized_=false;connected=false;status=L"Browser interrupted; reconnect when idle";failPending(status);if(interrupted)interrupted();return S_OK;}).Get(),&token);
                web_->add_PermissionRequested(Microsoft::WRL::Callback<ICoreWebView2PermissionRequestedEventHandler>([this,guard,generation](ICoreWebView2*,ICoreWebView2PermissionRequestedEventArgs* args)->HRESULT{if(!guard->alive||generation!=guard->generation)return S_OK;COREWEBVIEW2_PERMISSION_KIND kind{};args->get_PermissionKind(&kind);LPWSTR uri{};args->get_Uri(&uri);bool origin=uri&&trusted(uri);CoTaskMemFree(uri);if(kind==COREWEBVIEW2_PERMISSION_KIND_MICROPHONE)args->put_State(active&&origin?COREWEBVIEW2_PERMISSION_STATE_ALLOW:COREWEBVIEW2_PERMISSION_STATE_DENY);return S_OK;}).Get(),&token);
                web_->add_NewWindowRequested(Microsoft::WRL::Callback<ICoreWebView2NewWindowRequestedEventHandler>([this,guard,generation](ICoreWebView2*,ICoreWebView2NewWindowRequestedEventArgs* args)->HRESULT{if(!guard->alive||generation!=guard->generation)return S_OK;LPWSTR uri{};args->get_Uri(&uri);if(uri){web_->Navigate(uri);CoTaskMemFree(uri);}args->put_Handled(TRUE);return S_OK;}).Get(),&token);
                try{auto base=std::filesystem::path(exePath()).parent_path()/L"Bridge";auto script=read(base/L"audio.js")+L"\n"+read(base/L"driver.js");
                    web_->AddScriptToExecuteOnDocumentCreated(script.c_str(),Microsoft::WRL::Callback<ICoreWebView2AddScriptToExecuteOnDocumentCreatedCompletedHandler>([this,guard,generation](HRESULT injected,LPCWSTR)->HRESULT{
                        if(!guard->alive||generation!=guard->generation)return S_OK;
                        if(FAILED(injected)){status=L"Audio bridge could not load";return S_OK;}
                        if(fixture_){ComPtr<ICoreWebView2_3> v3;if(SUCCEEDED(web_.As(&v3))){auto folder=std::filesystem::path(exePath()).parent_path()/L"Bridge";v3->SetVirtualHostNameToFolderMapping(L"chatgpt.com",folder.c_str(),COREWEBVIEW2_HOST_RESOURCE_ACCESS_KIND_DENY_CORS);web_->Navigate(L"https://chatgpt.com/fixture.html");}}
                        else web_->Navigate(L"https://chatgpt.com/");return S_OK;
                    }).Get());
                }catch(...){status=L"Browser bridge files missing. Reinstall FlowGPT.";}if(shown_)show();else hide();return S_OK;
            }).Get());return S_OK;
        }).Get());
        if(FAILED(hr))status=L"WebView2 could not start. Check the installed runtime.";
    }
    void call(const std::wstring& action,std::function<void(Json)> fn,const std::wstring& expected=L"") {
        if(!ready()){fn(error(L"Waiting for the browser"));return;}
        LPWSTR source{};web_->get_Source(&source);bool origin=source&&trusted(source);CoTaskMemFree(source);if(!origin){fn(error(L"Finish signing in to ChatGPT"));return;}
        int id=next_++;Json request;request.Insert(L"type",JValue::CreateStringValue(L"flow-request"));request.Insert(L"id",JValue::CreateNumberValue(id));request.Insert(L"action",JValue::CreateStringValue(action));request.Insert(L"expected",JValue::CreateStringValue(expected));
        pending_.emplace(id,Pending{now()+8,std::move(fn)});HRESULT hr=web_->PostWebMessageAsJson(request.Stringify().c_str());if(FAILED(hr)){auto cb=std::move(pending_[id].callback);pending_.erase(id);cb(error(L"Browser message could not be delivered"));}
    }
    void tick(){std::vector<int> expired;for(auto& p:pending_)if(now()>p.second.deadline)expired.push_back(p.first);for(int id:expired){auto it=pending_.find(id);if(it==pending_.end())continue;auto fn=std::move(it->second.callback);pending_.erase(it);fn(error(L"Browser response timed out"));}}
};
}
