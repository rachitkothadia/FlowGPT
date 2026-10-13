#pragma once
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <windows.h>
#include <windowsx.h>
#include <shellapi.h>
#include <shlobj.h>
#include <commctrl.h>
#include <dwmapi.h>
#include <mmdeviceapi.h>
#include <audioclient.h>
#include <functiondiscoverykeys_devpkey.h>
#include <uiautomation.h>
#include <wrl.h>
#include <winrt/Windows.Data.Json.h>
#include <winrt/Windows.Foundation.h>
#include <fstream>
#include <filesystem>
#include <thread>
#include <atomic>
#include <functional>
#include <chrono>
#include "Core.h"

using Microsoft::WRL::ComPtr;
namespace flow {
using Json = winrt::Windows::Data::Json::JsonObject;
using JValue = winrt::Windows::Data::Json::JsonValue;
inline double now() { return std::chrono::duration<double>(std::chrono::steady_clock::now().time_since_epoch()).count(); }
inline std::wstring wide(const std::string& s) { return std::wstring(winrt::to_hstring(s)); }
inline std::string utf8(const std::wstring& s) { return winrt::to_string(s); }
inline std::wstring exePath() { wchar_t value[32768]{}; GetModuleFileNameW(nullptr,value,32768); return value; }
inline std::wstring utc() { SYSTEMTIME t{}; GetSystemTime(&t); wchar_t s[40]{}; swprintf_s(s,L"%04u-%02u-%02uT%02u:%02u:%02uZ",t.wYear,t.wMonth,t.wDay,t.wHour,t.wMinute,t.wSecond); return s; }
inline std::wstring guid() { GUID g{}; CoCreateGuid(&g); wchar_t s[40]{}; StringFromGUID2(g,s,40); return s; }
inline std::filesystem::path dataPath() { PWSTR p{}; winrt::check_hresult(SHGetKnownFolderPath(FOLDERID_LocalAppData,0,nullptr,&p)); std::filesystem::path result(p); CoTaskMemFree(p); return result / L"FlowGPT"; }
inline std::wstring read(const std::filesystem::path& p) { std::ifstream f(p,std::ios::binary); if(!f) throw std::runtime_error("File read failed"); std::string s((std::istreambuf_iterator<char>(f)),{}); if(s.size()>20000000) throw std::runtime_error("File exceeds limit"); return wide(s); }
inline void atomicWrite(const std::filesystem::path& p, const std::wstring& value) {
    std::filesystem::create_directories(p.parent_path()); auto temporary = p; temporary += guid()+L".tmp";
    auto text = utf8(value); HANDLE f = CreateFileW(temporary.c_str(),GENERIC_WRITE,0,nullptr,CREATE_NEW,FILE_ATTRIBUTE_NORMAL,nullptr);
    if(f==INVALID_HANDLE_VALUE) throw std::runtime_error("Cannot create private history file");
    DWORD written{}; bool good = WriteFile(f,text.data(),DWORD(text.size()),&written,nullptr) && written==text.size() && FlushFileBuffers(f);
    CloseHandle(f);
    if(!good || !MoveFileExW(temporary.c_str(),p.c_str(),MOVEFILE_REPLACE_EXISTING|MOVEFILE_WRITE_THROUGH)) { DeleteFileW(temporary.c_str()); throw std::runtime_error("History could not be saved"); }
}
struct Entry { std::wstring id, date, text; };
class Store {
    std::filesystem::path root_;
public:
    std::vector<Entry> entries;
    Json settings;
    explicit Store(std::filesystem::path root = dataPath()) : root_(std::move(root)) {}
    std::filesystem::path root() const { return root_; }
    void load() {
        if(std::filesystem::exists(root_/L"settings.json")) settings = Json::Parse(read(root_/L"settings.json"));
        if(!std::filesystem::exists(root_/L"history.json")) return;
        auto json = Json::Parse(read(root_/L"history.json"));
        if(json.GetNamedNumber(L"version")!=1) throw std::runtime_error("Unsupported history version");
        auto a = json.GetNamedArray(L"entries");
        if(a.Size()>100) throw std::runtime_error("Invalid history size");
        for(auto v:a) { auto o=v.GetObject(); auto text=std::wstring(o.GetNamedString(L"text")); if(!validText(text)) throw std::runtime_error("Invalid history entry"); entries.push_back({std::wstring(o.GetNamedString(L"id")),std::wstring(o.GetNamedString(L"date")),text}); }
    }
    void persist(const std::vector<Entry>& values) {
        Json o; o.Insert(L"version",JValue::CreateNumberValue(1)); winrt::Windows::Data::Json::JsonArray a;
        for(const auto& e:values) { Json v; v.Insert(L"id",JValue::CreateStringValue(e.id)); v.Insert(L"date",JValue::CreateStringValue(e.date)); v.Insert(L"text",JValue::CreateStringValue(e.text)); a.Append(v); }
        o.Insert(L"entries",a); atomicWrite(root_/L"history.json",std::wstring(o.Stringify())); entries=values;
    }
    void save(const std::wstring& text) { if(!validText(text)) throw std::runtime_error("Empty or oversized transcript"); auto copy=entries; copy.insert(copy.begin(),{guid(),utc(),text}); if(copy.size()>100) copy.resize(100); persist(copy); }
    void erase(const std::wstring& id) { auto copy=entries; copy.erase(std::remove_if(copy.begin(),copy.end(),[&](auto& e){return e.id==id;}),copy.end()); persist(copy); }
    void setting(const std::wstring& key, const winrt::Windows::Data::Json::IJsonValue& value) { auto copy=Json::Parse(settings.Stringify()); copy.Insert(key,value); atomicWrite(root_/L"settings.json",std::wstring(copy.Stringify())); settings=copy; }
};
inline std::vector<std::pair<std::wstring,std::wstring>> microphones() {
    ComPtr<IMMDeviceEnumerator> enumeration; winrt::check_hresult(CoCreateInstance(__uuidof(MMDeviceEnumerator),nullptr,CLSCTX_ALL,IID_PPV_ARGS(&enumeration)));
    ComPtr<IMMDeviceCollection> devices; winrt::check_hresult(enumeration->EnumAudioEndpoints(eCapture,DEVICE_STATE_ACTIVE,&devices)); UINT n{}; devices->GetCount(&n);
    std::vector<std::pair<std::wstring,std::wstring>> result;
    for(UINT i=0;i<n;++i) { ComPtr<IMMDevice> d; devices->Item(i,&d); LPWSTR id{}; d->GetId(&id); ComPtr<IPropertyStore> props; d->OpenPropertyStore(STGM_READ,&props); PROPVARIANT name{}; PropVariantInit(&name); props->GetValue(PKEY_Device_FriendlyName,&name); result.push_back({id,name.vt==VT_LPWSTR?name.pwszVal:L"Microphone"}); PropVariantClear(&name); CoTaskMemFree(id); }
    return result;
}
class Microphone {
    std::thread thread_;
    HANDLE stop_ = CreateEventW(nullptr,TRUE,FALSE,nullptr);
    std::atomic<long> error_{S_OK};
    std::atomic<bool> running_{false};
    std::atomic<double> first_{0};
public:
    AudioQueue audio;
    double began=0;
    ~Microphone() { stop(); CloseHandle(stop_); }
    bool running() const { return running_; }
    long error() const { return error_; }
    double firstMs() const { return first_>0?(first_-began)*1000:0; }
    void start(std::wstring device) {
        stop(); audio.reset(); ResetEvent(stop_); error_=S_OK; first_=0; began=now(); running_=true;
        thread_=std::thread([this,device] {
            HRESULT init=CoInitializeEx(nullptr,COINIT_MULTITHREADED); HRESULT hr=S_OK;
            try {
                ComPtr<IMMDeviceEnumerator> enumeration; winrt::check_hresult(CoCreateInstance(__uuidof(MMDeviceEnumerator),nullptr,CLSCTX_ALL,IID_PPV_ARGS(&enumeration)));
                ComPtr<IMMDevice> input;
                hr=device.empty()?enumeration->GetDefaultAudioEndpoint(eCapture,eConsole,&input):enumeration->GetDevice(device.c_str(),&input); winrt::check_hresult(hr);
                ComPtr<IAudioClient> client; winrt::check_hresult(input->Activate(__uuidof(IAudioClient),CLSCTX_ALL,nullptr,&client));
                WAVEFORMATEX format{WAVE_FORMAT_IEEE_FLOAT,1,16000,64000,4,32,0};
                winrt::check_hresult(client->Initialize(AUDCLNT_SHAREMODE_SHARED,AUDCLNT_STREAMFLAGS_EVENTCALLBACK|AUDCLNT_STREAMFLAGS_AUTOCONVERTPCM|AUDCLNT_STREAMFLAGS_SRC_DEFAULT_QUALITY,1000000,0,&format,nullptr));
                HANDLE event=CreateEventW(nullptr,FALSE,FALSE,nullptr); if(!event) winrt::throw_last_error();
                struct Close { HANDLE h; ~Close(){CloseHandle(h);} } cleanup{event};
                winrt::check_hresult(client->SetEventHandle(event)); ComPtr<IAudioCaptureClient> capture; winrt::check_hresult(client->GetService(IID_PPV_ARGS(&capture)));
                winrt::check_hresult(client->Start()); HANDLE events[]{stop_,event};
                while(WaitForMultipleObjects(2,events,FALSE,2000)!=WAIT_OBJECT_0) {
                    UINT packet{}; winrt::check_hresult(capture->GetNextPacketSize(&packet));
                    while(packet) {
                        BYTE* bytes{}; UINT frames{}; DWORD flags{}; winrt::check_hresult(capture->GetBuffer(&bytes,&frames,&flags,nullptr,nullptr));
                        if(first_==0) first_=now();
                        std::vector<float> silence;
                        const float* data=reinterpret_cast<const float*>(bytes);
                        if(flags&AUDCLNT_BUFFERFLAGS_SILENT) { silence.assign(frames,0); data=silence.data(); }
                        bool accepted=audio.push(data,frames); capture->ReleaseBuffer(frames);
                        if(!accepted) { if(audio.failed()) error_=HRESULT_FROM_WIN32(ERROR_BUFFER_OVERFLOW); SetEvent(stop_); break; }
                        winrt::check_hresult(capture->GetNextPacketSize(&packet));
                    }
                }
                client->Stop();
            } catch(const winrt::hresult_error& e) { error_=e.code(); } catch(...) { error_=E_FAIL; }
            audio.freeze(); running_=false; if(SUCCEEDED(init)) CoUninitialize();
        });
    }
    void stop() { audio.freeze(); SetEvent(stop_); if(thread_.joinable()) thread_.join(); running_=false; }
};
class ClipboardLease {
    struct Format { UINT id; std::vector<unsigned char> data; };
    std::vector<Format> saved_;
    DWORD owned_=0;
public:
    bool write(HWND owner,const std::wstring& text) {
        if(!OpenClipboard(owner)) return false;
        struct Close { ~Close(){CloseClipboard();} } close;
        for(UINT id=EnumClipboardFormats(0);id;id=EnumClipboardFormats(id)) {
            HANDLE handle=GetClipboardData(id); size_t n=GlobalSize(handle);
            // Do not destroy unsupported GDI/delayed formats to perform a paste.
            if(!handle || !n || n>32*1024*1024) return false;
            const auto* bytes=static_cast<unsigned char*>(GlobalLock(handle)); if(!bytes) return false;
            saved_.push_back({id,std::vector<unsigned char>(bytes,bytes+n)}); GlobalUnlock(handle);
        }
        HGLOBAL memory=GlobalAlloc(GMEM_MOVEABLE,(text.size()+1)*sizeof(wchar_t)); if(!memory) return false;
        auto p=GlobalLock(memory); if(!p){GlobalFree(memory);return false;} memcpy(p,text.c_str(),(text.size()+1)*sizeof(wchar_t)); GlobalUnlock(memory);
        if(!EmptyClipboard() || !SetClipboardData(CF_UNICODETEXT,memory)){GlobalFree(memory); restoreContents();return false;}
        owned_=GetClipboardSequenceNumber(); return true;
    }
    void restoreContents() {
        EmptyClipboard();
        for(auto& f:saved_) { HGLOBAL memory=GlobalAlloc(GMEM_MOVEABLE,f.data.size()); if(!memory)continue; void* p=GlobalLock(memory); if(!p){GlobalFree(memory);continue;} memcpy(p,f.data.data(),f.data.size()); GlobalUnlock(memory); if(!SetClipboardData(f.id,memory))GlobalFree(memory); }
    }
    void restore(HWND owner) { if(!owned_ || !mayRestore(owned_,GetClipboardSequenceNumber())) return; if(!OpenClipboard(owner))return; if(mayRestore(owned_,GetClipboardSequenceNumber()))restoreContents(); CloseClipboard(); owned_=0; }
};
class Insertion {
    ComPtr<IUIAutomation> automation_;
    HWND window_{};
    DWORD pid_{};
    std::vector<int> id_;
    std::unique_ptr<ClipboardLease> lease_;
    bool sent_=false;
    static std::vector<int> runtimeId(IUIAutomationElement* element) {
        SAFEARRAY* array{}; if(FAILED(element->GetRuntimeId(&array))||!array)return{};
        LONG lower{},upper{}; SafeArrayGetLBound(array,1,&lower); SafeArrayGetUBound(array,1,&upper); std::vector<int> values;
        for(LONG i=lower;i<=upper;++i){int value{};SafeArrayGetElement(array,&i,&value);values.push_back(value);}SafeArrayDestroy(array);return values;
    }
    static bool editable(IUIAutomationElement* e) {
        ComPtr<IUIAutomationValuePattern> value;
        if(SUCCEEDED(e->GetCurrentPatternAs(UIA_ValuePatternId,IID_PPV_ARGS(&value)))) { BOOL readonly=TRUE; return SUCCEEDED(value->get_CurrentIsReadOnly(&readonly))&&!readonly; }
        CONTROLTYPEID type{};e->get_CurrentControlType(&type);
        ComPtr<IUIAutomationTextPattern> text;
        return (type==UIA_EditControlTypeId||type==UIA_DocumentControlTypeId)&&SUCCEEDED(e->GetCurrentPatternAs(UIA_TextPatternId,IID_PPV_ARGS(&text)));
    }
public:
    Insertion(){CoCreateInstance(CLSID_CUIAutomation,nullptr,CLSCTX_INPROC_SERVER,IID_PPV_ARGS(&automation_));}
    bool capture() {
        sent_=false; id_.clear(); window_=GetForegroundWindow(); GetWindowThreadProcessId(window_,&pid_);
        if(pid_==GetCurrentProcessId()||!automation_)return false;
        ComPtr<IUIAutomationElement> element; if(FAILED(automation_->GetFocusedElement(&element)))return false;
        BOOL password{}; if(FAILED(element->get_CurrentIsPassword(&password))||password)return false;
        if(!editable(element.Get()))return false;
        id_=runtimeId(element.Get()); return !id_.empty();
    }
    bool valid() {
        if(!automation_||GetForegroundWindow()!=window_)return false;
        ComPtr<IUIAutomationElement> element;if(FAILED(automation_->GetFocusedElement(&element)))return false;
        BOOL password{},enabled{}; element->get_CurrentIsPassword(&password); element->get_CurrentIsEnabled(&enabled);
        if(password||!enabled||!editable(element.Get()))return false;
        ComPtr<IUIAutomationValuePattern> value; if(SUCCEEDED(element->GetCurrentPatternAs(UIA_ValuePatternId,IID_PPV_ARGS(&value)))){BOOL readonly{};if(SUCCEEDED(value->get_CurrentIsReadOnly(&readonly))&&readonly)return false;}
        return sameTarget(reinterpret_cast<uintptr_t>(window_),reinterpret_cast<uintptr_t>(GetForegroundWindow()),id_,runtimeId(element.Get()));
    }
    bool paste(HWND owner,const std::wstring& text) {
        if(sent_||!valid()||!validText(text))return false;
        lease_=std::make_unique<ClipboardLease>();if(!lease_->write(owner,text)){lease_.reset();return false;}
        if(!valid()){lease_->restore(owner);lease_.reset();return false;}
        // Wait until the global shortcut modifiers have been released before paste.
        INPUT events[4]{};
        for(auto& e:events)e.type=INPUT_KEYBOARD;
        events[0].ki.wVk=VK_CONTROL;events[1].ki.wVk='V';events[2].ki.wVk='V';events[2].ki.dwFlags=KEYEVENTF_KEYUP;events[3].ki.wVk=VK_CONTROL;events[3].ki.dwFlags=KEYEVENTF_KEYUP;
        sent_=true;return SendInput(4,events,sizeof(INPUT))==4;
    }
    void restore(HWND owner){if(lease_)lease_->restore(owner);lease_.reset();}
};
inline bool startupEnabled() { HKEY key{}; if(RegOpenKeyExW(HKEY_CURRENT_USER,L"Software\\Microsoft\\Windows\\CurrentVersion\\Run",0,KEY_READ,&key)!=ERROR_SUCCESS)return false; LONG result=RegQueryValueExW(key,L"FlowGPT",nullptr,nullptr,nullptr,nullptr);RegCloseKey(key);return result==ERROR_SUCCESS; }
inline void startup(bool enable) { HKEY key{};winrt::check_win32(RegCreateKeyExW(HKEY_CURRENT_USER,L"Software\\Microsoft\\Windows\\CurrentVersion\\Run",0,nullptr,0,KEY_WRITE,nullptr,&key,nullptr)); LONG hr;
    if(enable){auto command=L"\""+exePath()+L"\" --background";hr=RegSetValueExW(key,L"FlowGPT",0,REG_SZ,reinterpret_cast<const BYTE*>(command.c_str()),DWORD((command.size()+1)*2));}
    else{hr=RegDeleteValueW(key,L"FlowGPT");if(hr==ERROR_FILE_NOT_FOUND)hr=ERROR_SUCCESS;}RegCloseKey(key);winrt::check_win32(hr);
}
}
