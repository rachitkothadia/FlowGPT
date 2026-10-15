#pragma once
#include "Platform.h"
#include <winhttp.h>
#include <bcrypt.h>
#include <array>
#include <optional>
#include "ReleasePolicy.h"

namespace flow {
struct HttpHandle{HINTERNET value{};~HttpHandle(){if(value)WinHttpCloseHandle(value);}HttpHandle(const HttpHandle&)=delete;explicit HttpHandle(HINTERNET h):value(h){if(!h)winrt::throw_last_error();}};
inline std::vector<unsigned char> updateRequest(const std::wstring& url,size_t maximum){
    URL_COMPONENTS parts{sizeof(parts)};parts.dwSchemeLength=parts.dwHostNameLength=parts.dwUrlPathLength=parts.dwExtraInfoLength=DWORD(-1);
    if(!WinHttpCrackUrl(url.c_str(),DWORD(url.size()),0,&parts)||parts.nScheme!=INTERNET_SCHEME_HTTPS)throw std::runtime_error("Update URL invalid");
    std::wstring host(parts.lpszHostName,parts.dwHostNameLength),path(parts.lpszUrlPath,parts.dwUrlPathLength);if(parts.dwExtraInfoLength)path.append(parts.lpszExtraInfo,parts.dwExtraInfoLength);
    HttpHandle session(WinHttpOpen(L"FlowGPT/1.1 updates",WINHTTP_ACCESS_TYPE_AUTOMATIC_PROXY,WINHTTP_NO_PROXY_NAME,WINHTTP_NO_PROXY_BYPASS,0));
    WinHttpSetTimeouts(session.value,3000,5000,5000,15000);
    HttpHandle connection(WinHttpConnect(session.value,host.c_str(),parts.nPort,0));
    HttpHandle request(WinHttpOpenRequest(connection.value,L"GET",path.c_str(),nullptr,WINHTTP_NO_REFERER,WINHTTP_DEFAULT_ACCEPT_TYPES,WINHTTP_FLAG_SECURE));
    if(!WinHttpSendRequest(request.value,L"Accept: application/vnd.github+json\r\n",DWORD(-1),WINHTTP_NO_REQUEST_DATA,0,0,0)||!WinHttpReceiveResponse(request.value,nullptr))winrt::throw_last_error();
    DWORD code{},length=sizeof(code);if(!WinHttpQueryHeaders(request.value,WINHTTP_QUERY_STATUS_CODE|WINHTTP_QUERY_FLAG_NUMBER,nullptr,&code,&length,nullptr)||code!=200)throw std::runtime_error("Update server unavailable");
    std::vector<unsigned char> bytes;for(;;){DWORD available{};if(!WinHttpQueryDataAvailable(request.value,&available))winrt::throw_last_error();if(!available)break;
        if(available>maximum-bytes.size())throw std::runtime_error("Update exceeds size limit");size_t start=bytes.size();bytes.resize(start+available);DWORD received{};
        if(!WinHttpReadData(request.value,bytes.data()+start,available,&received))winrt::throw_last_error();bytes.resize(start+received);if(!received)break;}
    return bytes;
}
inline std::wstring updateText(const std::wstring& url){auto data=updateRequest(url,4*1024*1024);return wide(std::string(data.begin(),data.end()));}
inline std::wstring updateSha256(const std::vector<unsigned char>& bytes){
    BCRYPT_ALG_HANDLE provider{};if(BCryptOpenAlgorithmProvider(&provider,BCRYPT_SHA256_ALGORITHM,nullptr,0)<0)throw std::runtime_error("Checksum unavailable");
    struct Close{BCRYPT_ALG_HANDLE p;~Close(){BCryptCloseAlgorithmProvider(p,0);}}close{provider};
    std::array<unsigned char,32> digest{};if(BCryptHash(provider,nullptr,0,const_cast<PUCHAR>(bytes.data()),ULONG(bytes.size()),digest.data(),ULONG(digest.size()))<0)throw std::runtime_error("Checksum failed");
    const wchar_t alphabet[]=L"0123456789abcdef";std::wstring value;for(auto b:digest){value+=alphabet[b>>4];value+=alphabet[b&15];}return value;
}
class Updates {
public:
    struct State{bool busy=false,available=false,downloaded=false;std::wstring message=L"Check for a newer version of FlowGPT.",version,file;std::filesystem::path installer;};
private:
    mutable std::mutex mutex_;
    State state_;
    std::thread thread_;
    std::wstring assetUrl_,checksumUrl_;
    std::wstring verifiedDigest_;
    void launch(std::function<void()> task){if(thread_.joinable())thread_.join();thread_=std::thread([this,task]{HRESULT init=CoInitializeEx(nullptr,COINIT_MULTITHREADED);try{task();}catch(...){std::lock_guard lock(mutex_);state_.busy=false;state_.message=L"Could not reach the update server. Check your internet connection and try again.";}if(SUCCEEDED(init))CoUninitialize();});}
public:
    ~Updates(){if(thread_.joinable())thread_.join();}
    State state()const{std::lock_guard lock(mutex_);return state_;}
    void check(){
        {std::lock_guard lock(mutex_);if(state_.busy)return;state_={};state_.busy=true;state_.message=L"Checking for updates…";}
        launch([this]{
            auto releases=winrt::Windows::Data::Json::JsonArray::Parse(updateText(L"https://api.github.com/repos/rachitkothadia/FlowGPT/releases?per_page=100"));
            auto newest=*updateVersion(L"1.3.2");std::wstring version,file,url,checksum;
            for(auto item:releases){auto release=item.GetObject();if(release.GetNamedBoolean(L"draft",false))continue;
                auto assets=release.GetNamedArray(L"assets");std::wstring candidate,download,hash;
                for(auto asset:assets){auto a=asset.GetObject();auto name=std::wstring(a.GetNamedString(L"name"));
                    if(name.starts_with(L"FlowGPT-")&&name.ends_with(L"-Windows-x64-Setup.exe")){candidate=name;download=std::wstring(a.GetNamedString(L"browser_download_url"));}
                    if(name==L"SHA256SUMS.txt")hash=std::wstring(a.GetNamedString(L"browser_download_url"));}
                if(candidate.empty()||!trustedUpdateAsset(download)||!trustedUpdateAsset(hash))continue;
                auto v=candidate.substr(8,candidate.size()-8-22);auto number=updateVersion(v);
                if(number&&*number>newest){newest=*number;version=v;file=candidate;url=download;checksum=hash;}
            }
            std::lock_guard lock(mutex_);state_.busy=false;state_.available=!file.empty();state_.version=version;state_.file=file;assetUrl_=url;checksumUrl_=checksum;
            state_.message=file.empty()?L"You're up to date.":L"FlowGPT "+version+L" is available.";
        });
    }
    void download(){
        std::wstring url,checksum,file;{std::lock_guard lock(mutex_);if(state_.busy||!state_.available)return;state_.busy=true;state_.message=L"Downloading and verifying the update…";url=assetUrl_;checksum=checksumUrl_;file=state_.file;}
        launch([this,url,checksum,file]{
            auto expected=releaseChecksum(updateText(checksum),file);
            if(!expected)throw std::runtime_error("Release checksum missing or ambiguous");
            auto bytes=updateRequest(url,256*1024*1024);if(bytes.size()<2||bytes[0]!='M'||bytes[1]!='Z'||updateSha256(bytes)!=*expected)throw std::runtime_error("Installer checksum mismatch");
            auto directory=dataPath()/L"Updates";std::filesystem::create_directories(directory);auto target=directory/file;auto temporary=directory/(file+L".partial");
            {std::ofstream stream(temporary,std::ios::binary);stream.write(reinterpret_cast<const char*>(bytes.data()),std::streamsize(bytes.size()));stream.flush();if(!stream)throw std::runtime_error("Update could not be saved");}
            if(!MoveFileExW(temporary.c_str(),target.c_str(),MOVEFILE_REPLACE_EXISTING|MOVEFILE_WRITE_THROUGH))winrt::throw_last_error();
            std::lock_guard lock(mutex_);verifiedDigest_=*expected;state_.busy=false;state_.downloaded=true;state_.installer=target;state_.message=L"Update verified. Install it to keep your history and connection.";
        });
    }
    bool install(HWND owner){auto s=state();if(s.busy||!s.downloaded||s.installer.empty())return false;
        try{auto size=std::filesystem::file_size(s.installer);if(size<2||size>256*1024*1024)return false;std::ifstream stream(s.installer,std::ios::binary);std::vector<unsigned char> bytes(size);stream.read(reinterpret_cast<char*>(bytes.data()),std::streamsize(size));
            std::wstring expected;{std::lock_guard lock(mutex_);expected=verifiedDigest_;}if(!stream||bytes[0]!='M'||bytes[1]!='Z'||updateSha256(bytes)!=expected)return false;}catch(...){return false;}
        return reinterpret_cast<INT_PTR>(ShellExecuteW(owner,L"open",s.installer.c_str(),nullptr,nullptr,SW_SHOWNORMAL))>32;}
};
}
