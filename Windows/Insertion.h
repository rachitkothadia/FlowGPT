#pragma once
#include "Platform.h"
#include <condition_variable>
#include <future>
#include <optional>
#include <utility>
#include <ole2.h>

namespace flow {
class ClipboardLease {
    static void release(UINT id,HANDLE handle) noexcept {
        if(!handle)return;
        if(id==CF_BITMAP||id==CF_DSPBITMAP||id==CF_PALETTE)DeleteObject(handle);
        else if(id==CF_ENHMETAFILE||id==CF_DSPENHMETAFILE)DeleteEnhMetaFile(static_cast<HENHMETAFILE>(handle));
        else if(id==CF_METAFILEPICT||id==CF_DSPMETAFILEPICT){
            auto p=static_cast<METAFILEPICT*>(GlobalLock(handle));
            if(p){DeleteMetaFile(p->hMF);GlobalUnlock(handle);}GlobalFree(handle);
        }else GlobalFree(handle);
    }
    struct Format {
        UINT id{};HANDLE handle{};
        Format(UINT i,HANDLE h):id(i),handle(h){}
        Format(const Format&)=delete;
        Format& operator=(const Format&)=delete;
        Format(Format&& other)noexcept:id(other.id),handle(std::exchange(other.handle,nullptr)){}
        ~Format(){release(id,handle);}
    };
    std::vector<Format> saved_;
    DWORD owned_=0;
    std::wstring published_;
    static size_t formatBytes(UINT id,HANDLE handle){
        if(!handle||id==CF_OWNERDISPLAY)return 0;
        if(id==CF_BITMAP||id==CF_DSPBITMAP){BITMAP bitmap{};if(!GetObjectW(handle,sizeof(bitmap),&bitmap))return 0;
            uint64_t n=uint64_t(std::abs(bitmap.bmHeight))*uint64_t(std::abs(bitmap.bmWidthBytes));return n<=32*1024*1024?size_t(n):0;}
        if(id==CF_PALETTE){UINT count=GetPaletteEntries(static_cast<HPALETTE>(handle),0,0,nullptr);return count<=65536?size_t(count)*sizeof(PALETTEENTRY):0;}
        if(id==CF_ENHMETAFILE||id==CF_DSPENHMETAFILE)return GetEnhMetaFileBits(static_cast<HENHMETAFILE>(handle),0,nullptr);
        if(id==CF_METAFILEPICT||id==CF_DSPMETAFILEPICT){size_t n=GlobalSize(handle);if(n<sizeof(METAFILEPICT))return 0;auto p=static_cast<METAFILEPICT*>(GlobalLock(handle));if(!p)return 0;
            size_t bytes=GetMetaFileBitsEx(p->hMF,0,nullptr);GlobalUnlock(handle);return bytes+n;}
        return GlobalSize(handle);
    }
    bool matches(HANDLE handle)const{
        size_t bytes=handle?GlobalSize(handle):0;
        size_t required=(published_.size()+1)*sizeof(wchar_t);
        if(bytes<required||bytes>32*1024*1024||bytes%sizeof(wchar_t))return false;
        const void* p=GlobalLock(handle);if(!p)return false;
        bool equal=memcmp(p,published_.c_str(),required)==0;GlobalUnlock(handle);return equal;
    }
    void restoreContents()noexcept{
        if(!EmptyClipboard())return;
        for(auto& f:saved_)if(f.handle&&SetClipboardData(f.id,f.handle))f.handle=nullptr;
    }
public:
    bool write(HWND owner,const std::wstring& text)noexcept{
        if(!validText(text)||!OpenClipboard(owner))return false;
        struct Close{bool active=true;void finish(){if(active){CloseClipboard();active=false;}}~Close(){finish();}}close;
        try{
            size_t total=0;unsigned count=0;
            for(UINT id=EnumClipboardFormats(0);id;id=EnumClipboardFormats(id)){
                HANDLE original=GetClipboardData(id);size_t bytes=formatBytes(id,original);
                if(!bytes||bytes>32*1024*1024||total>64*1024*1024-bytes||++count>128)return false;
                HANDLE copy=OleDuplicateData(original,CLIPFORMAT(id),0);if(!copy)return false;
                Format snapshot(id,copy);saved_.push_back(std::move(snapshot));total+=bytes;
            }
            published_=text;
            HGLOBAL memory=GlobalAlloc(GMEM_MOVEABLE,(text.size()+1)*sizeof(wchar_t));if(!memory)return false;
            void* p=GlobalLock(memory);if(!p){GlobalFree(memory);return false;}
            memcpy(p,text.c_str(),(text.size()+1)*sizeof(wchar_t));GlobalUnlock(memory);
            if(!EmptyClipboard()){GlobalFree(memory);return false;}
            if(!SetClipboardData(CF_UNICODETEXT,memory)){GlobalFree(memory);restoreContents();return false;}
            close.finish();owned_=GetClipboardSequenceNumber();return true;
        }catch(...){return false;}
    }
    void restore(HWND owner)noexcept{
        if(!owned_||!mayRestore(owned_,GetClipboardSequenceNumber()))return;
        if(!OpenClipboard(owner))return;
        if(GetClipboardOwner()==owner&&matches(GetClipboardData(CF_UNICODETEXT))&&mayRestore(owned_,GetClipboardSequenceNumber()))restoreContents();
        CloseClipboard();owned_=0;
    }
};

// UI Automation providers are queried from a windowless MTA. The WinUI thread
// only submits work and polls plain results, so provider COM calls cannot reenter
// its completion timer or run a second paste while the first is still pending.
class Insertion {
public:
    using PatternQuery=std::function<HRESULT(IUIAutomationElement*,PATTERNID,REFIID,void**)>;
private:
    class FocusEvents final:public Microsoft::WRL::RuntimeClass<Microsoft::WRL::RuntimeClassFlags<Microsoft::WRL::ClassicCom>,IUIAutomationFocusChangedEventHandler,Microsoft::WRL::FtmBase>{
        std::shared_ptr<std::atomic<uint64_t>> epoch_;
    public:
        explicit FocusEvents(std::shared_ptr<std::atomic<uint64_t>> epoch):epoch_(std::move(epoch)){}
        HRESULT STDMETHODCALLTYPE HandleFocusChangedEvent(IUIAutomationElement*)override{epoch_->fetch_add(1);return S_OK;}
    };
    std::mutex mutex_;
    std::condition_variable wake_;
    std::deque<std::function<void()>> jobs_;
    bool stopping_=false;
    ComPtr<IUIAutomation> automation_;
    std::shared_ptr<std::atomic<uint64_t>> focusEpoch_=std::make_shared<std::atomic<uint64_t>>(0);
    ComPtr<FocusEvents> focusEvents_;
    bool focusSubscribed_=false;
    HWND nativeFocus_{};
    std::vector<int> rawId_;
    uint64_t validatedFocusEpoch_=0;
    HWND window_{},leaseOwner_{};
    DWORD pid_{};
    std::vector<int> id_;
    std::unique_ptr<ClipboardLease> lease_;
    bool sent_=false;
    std::future<bool> captureFuture_,pasteFuture_;
    PatternQuery query_;
    std::atomic<uint64_t> generation_{0};
    std::thread thread_;

    std::future<bool> submit(std::function<bool()> operation){
        auto task=std::make_shared<std::packaged_task<bool()>>([operation=std::move(operation)]{try{return operation();}catch(...){return false;}});
        auto result=task->get_future();{std::lock_guard lock(mutex_);jobs_.push_back([task]{(*task)();});}wake_.notify_one();return result;
    }
    static std::vector<int> runtimeId(IUIAutomationElement* element){
        if(!element)return{};SAFEARRAY* array{};if(FAILED(element->GetRuntimeId(&array))||!array)return{};
        struct Free{SAFEARRAY* a;~Free(){SafeArrayDestroy(a);}}free{array};
        LONG lower{},upper{};if(FAILED(SafeArrayGetLBound(array,1,&lower))||FAILED(SafeArrayGetUBound(array,1,&upper))||upper<lower||upper-lower>128)return{};
        std::vector<int> values;for(LONG i=lower;i<=upper;++i){int value{};if(FAILED(SafeArrayGetElement(array,&i,&value)))return{};values.push_back(value);}return values;
    }
    static bool allowed(IUIAutomationElement* e){
        if(!e)return false;BOOL password=TRUE,enabled=FALSE;
        return SUCCEEDED(e->get_CurrentIsPassword(&password))&&SUCCEEDED(e->get_CurrentIsEnabled(&enabled))&&!password&&enabled;
    }
    static bool writableRange(IUIAutomationTextRange* range){
        if(!range)return false;VARIANT value;VariantInit(&value);
        HRESULT hr=range->GetAttributeValue(UIA_IsReadOnlyAttributeId,&value);
        bool editable=SUCCEEDED(hr)&&value.vt==VT_BOOL&&value.boolVal==VARIANT_FALSE;VariantClear(&value);return editable;
    }
    bool editable(IUIAutomationElement* e){
        if(!allowed(e))return false;
        ComPtr<IUIAutomationValuePattern> value;
        if(SUCCEEDED(query_(e,UIA_ValuePatternId,__uuidof(IUIAutomationValuePattern),reinterpret_cast<void**>(value.GetAddressOf())))&&value){BOOL readonly=TRUE;return SUCCEEDED(value->get_CurrentIsReadOnly(&readonly))&&!readonly;}
        ComPtr<IUIAutomationTextPattern2> caret;
        if(SUCCEEDED(query_(e,UIA_TextPattern2Id,__uuidof(IUIAutomationTextPattern2),reinterpret_cast<void**>(caret.GetAddressOf())))&&caret){BOOL active=FALSE;ComPtr<IUIAutomationTextRange> range;
            if(SUCCEEDED(caret->GetCaretRange(&active,&range))&&active&&writableRange(range.Get()))return true;}
        ComPtr<IUIAutomationTextPattern> text;
        if(FAILED(query_(e,UIA_TextPatternId,__uuidof(IUIAutomationTextPattern),reinterpret_cast<void**>(text.GetAddressOf())))||!text)return false;
        ComPtr<IUIAutomationTextRangeArray> selection;if(FAILED(text->GetSelection(&selection))||!selection)return false;
        int count{};if(FAILED(selection->get_Length(&count))||count!=1)return false;
        ComPtr<IUIAutomationTextRange> range;return SUCCEEDED(selection->GetElement(0,&range))&&writableRange(range.Get());
    }
    HWND nativeFocus()const{
        GUITHREADINFO info{sizeof(info)};DWORD thread=GetWindowThreadProcessId(window_,nullptr);
        return thread&&GetGUIThreadInfo(thread,&info)&&info.hwndFocus&&(info.hwndFocus==window_||IsChild(window_,info.hwndFocus))?info.hwndFocus:nullptr;
    }
    ComPtr<IUIAutomationElement> editor(ComPtr<IUIAutomationElement>* raw=nullptr){
        ComPtr<IUIAutomationElement> focused;if(!automation_||FAILED(automation_->GetFocusedElement(&focused))||!allowed(focused.Get()))return{};
        if(raw)*raw=focused;
        ComPtr<IUIAutomationTreeWalker> walker;automation_->get_ControlViewWalker(&walker);
        for(unsigned depth=0;focused&&depth<6;++depth){
            int process{};if(FAILED(focused->get_CurrentProcessId(&process))||DWORD(process)!=pid_)return{};
            if(editable(focused.Get()))return focused;
            if(!walker)return{};ComPtr<IUIAutomationElement> parent;if(FAILED(walker->GetParentElement(focused.Get(),&parent)))return{};focused=parent;
        }return{};
    }
    bool captureImpl(HWND target,uint64_t generation){
        sent_=false;id_.clear();rawId_.clear();window_=target;GetWindowThreadProcessId(window_,&pid_);nativeFocus_=nativeFocus();
        if(!focusSubscribed_||!nativeFocus_||!window_||GetForegroundWindow()!=window_||pid_==GetCurrentProcessId())return false;
        auto epoch=focusEpoch_->load();ComPtr<IUIAutomationElement> raw;auto e=editor(&raw);auto id=runtimeId(e.Get());auto rawId=runtimeId(raw.Get());
        if(generation!=generation_||GetForegroundWindow()!=window_||nativeFocus()!=nativeFocus_||focusEpoch_->load()!=epoch||id.empty()||rawId.empty())return false;
        id_=std::move(id);rawId_=std::move(rawId);return true;
    }
    bool validImpl(){
        if(!automation_||!focusSubscribed_||GetForegroundWindow()!=window_||nativeFocus()!=nativeFocus_)return false;DWORD pid{};GetWindowThreadProcessId(window_,&pid);if(pid!=pid_)return false;
        auto epoch=focusEpoch_->load();ComPtr<IUIAutomationElement> raw;auto e=editor(&raw);auto currentId=runtimeId(e.Get());auto currentRawId=runtimeId(raw.Get());
        ComPtr<IUIAutomationElement> finalRaw;if(FAILED(automation_->GetFocusedElement(&finalRaw))||!finalRaw)return false;auto finalRawId=runtimeId(finalRaw.Get());
        bool same=sameTarget(reinterpret_cast<uintptr_t>(window_),reinterpret_cast<uintptr_t>(GetForegroundWindow()),id_,currentId)&&!rawId_.empty()&&rawId_==currentRawId&&rawId_==finalRawId&&nativeFocus()==nativeFocus_&&focusEpoch_->load()==epoch;
        if(same)validatedFocusEpoch_=epoch;return same;
    }
    bool pasteImpl(HWND owner,const std::wstring& text,uint64_t generation){
        if(generation!=generation_||sent_||!validText(text)||!validImpl())return false;
        if(GetAsyncKeyState(VK_CONTROL)&0x8000||GetAsyncKeyState(VK_MENU)&0x8000||GetAsyncKeyState(VK_SHIFT)&0x8000)return false;
        if(lease_)lease_->restore(leaseOwner_);lease_=std::make_unique<ClipboardLease>();leaseOwner_=owner;
        if(!lease_->write(owner,text)){lease_.reset();return false;}
        if(generation!=generation_||!validImpl()){lease_->restore(owner);lease_.reset();return false;}
        INPUT events[4]{};for(auto& e:events)e.type=INPUT_KEYBOARD;
        events[0].ki.wVk=VK_CONTROL;events[1].ki.wVk='V';events[2].ki.wVk='V';events[2].ki.dwFlags=KEYEVENTF_KEYUP;events[3].ki.wVk=VK_CONTROL;events[3].ki.dwFlags=KEYEVENTF_KEYUP;
        // Providers can block while the user switches applications. Check the
        // native foreground again after every provider call, just before input.
        if(generation!=generation_||nativeFocus()!=nativeFocus_||focusEpoch_->load()!=validatedFocusEpoch_||GetForegroundWindow()!=window_){lease_->restore(owner);lease_.reset();return false;}
        sent_=true;UINT delivered=SendInput(4,events,sizeof(INPUT));
        if(delivered!=4){INPUT release[2]{};for(auto& e:release){e.type=INPUT_KEYBOARD;e.ki.dwFlags=KEYEVENTF_KEYUP;}release[0].ki.wVk='V';release[1].ki.wVk=VK_CONTROL;SendInput(2,release,sizeof(INPUT));}
        return delivered==4;
    }
    static std::optional<bool> poll(std::future<bool>& future){
        if(!future.valid()||future.wait_for(std::chrono::seconds(0))!=std::future_status::ready)return{};
        try{return future.get();}catch(...){return false;}
    }
public:
    explicit Insertion(PatternQuery query={}):query_(query?std::move(query):PatternQuery([](IUIAutomationElement* e,PATTERNID id,REFIID iid,void** value){return e->GetCurrentPatternAs(id,iid,value);})),thread_([this]{
        HRESULT initialized=CoInitializeEx(nullptr,COINIT_MULTITHREADED);
        if(SUCCEEDED(initialized)){CoCreateInstance(CLSID_CUIAutomation,nullptr,CLSCTX_INPROC_SERVER,IID_PPV_ARGS(&automation_));ComPtr<IUIAutomation2> timed;
            if(automation_&&SUCCEEDED(automation_.As(&timed))&&timed){timed->put_ConnectionTimeout(250);timed->put_TransactionTimeout(250);}
            if(automation_){focusEvents_=Microsoft::WRL::Make<FocusEvents>(focusEpoch_);if(focusEvents_)focusSubscribed_=SUCCEEDED(automation_->AddFocusChangedEventHandler(nullptr,focusEvents_.Get()));}}
        for(;;){std::function<void()> job;{std::unique_lock lock(mutex_);wake_.wait(lock,[this]{return stopping_||!jobs_.empty();});if(jobs_.empty()&&stopping_)break;job=std::move(jobs_.front());jobs_.pop_front();}job();}
        if(lease_)lease_->restore(leaseOwner_);lease_.reset();if(focusSubscribed_)automation_->RemoveFocusChangedEventHandler(focusEvents_.Get());focusEvents_.Reset();automation_.Reset();if(SUCCEEDED(initialized))CoUninitialize();
    }){}
    ~Insertion(){++generation_;{std::lock_guard lock(mutex_);stopping_=true;}wake_.notify_one();if(thread_.joinable()){
        // Removing a global UIA subscription may marshal back to this WinUI
        // apartment. A plain join blocks that callback and deadlocks Quit.
        HANDLE worker=thread_.native_handle();DWORD index{};
        while(WaitForSingleObject(worker,0)==WAIT_TIMEOUT){HRESULT wait=CoWaitForMultipleHandles(COWAIT_DISPATCH_CALLS|COWAIT_DISPATCH_WINDOW_MESSAGES,50,1,&worker,&index);if(FAILED(wait)&&wait!=RPC_S_CALLPENDING)Sleep(1);}
        thread_.join();}}
    void beginCapture(){auto version=++generation_;HWND target=GetForegroundWindow();captureFuture_=submit([this,target,version]{return captureImpl(target,version);});}
    std::optional<bool> captured(){return poll(captureFuture_);}
    void beginPaste(HWND owner,std::wstring text){auto version=generation_.load();pasteFuture_=submit([this,owner,text=std::move(text),version]{return pasteImpl(owner,text,version);});}
    std::optional<bool> pasted(){return poll(pasteFuture_);}
    void restoreLater(HWND owner){(void)submit([this,owner]{if(lease_)lease_->restore(owner);lease_.reset();return true;});}
    void cancel(HWND owner){++generation_;restoreLater(owner);}
    // Synchronous adapters are only used by disposable native regression probes.
    bool capture(){auto version=++generation_;HWND target=GetForegroundWindow();return submit([this,target,version]{return captureImpl(target,version);}).get();}
    bool valid(){return submit([this]{return validImpl();}).get();}
    bool paste(HWND owner,const std::wstring& text){auto version=generation_.load();return submit([this,owner,text,version]{return pasteImpl(owner,text,version);}).get();}
    void restore(HWND owner){submit([this,owner]{if(lease_)lease_->restore(owner);lease_.reset();return true;}).get();}
};
}
