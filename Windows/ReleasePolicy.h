#pragma once
#include <array>
#include <optional>
#include <string>

namespace flow {
inline std::optional<std::array<unsigned,3>> updateVersion(const std::wstring& value){
    std::array<unsigned,3> parts{};size_t start=0;
    for(size_t i=0;i<3;++i){size_t end=value.find(L'.',start);if(i==2)end=value.size();if(end==std::wstring::npos||end==start||end-start>6)return{};
        unsigned n=0;for(size_t p=start;p<end;++p){if(value[p]<L'0'||value[p]>L'9')return{};n=n*10+unsigned(value[p]-L'0');}parts[i]=n;start=end+1;}
    if(start!=value.size()+1)return{};return parts;
}
inline bool trustedUpdateAsset(const std::wstring& url){return url.rfind(L"https://github.com/rachitkothadia/FlowGPT/releases/download/",0)==0;}
inline std::optional<std::wstring> releaseChecksum(const std::wstring& sums,const std::wstring& file){
    std::optional<std::wstring> result;size_t start=0;
    while(start<sums.size()){
        auto end=sums.find(L'\n',start);auto line=sums.substr(start,end==std::wstring::npos?std::wstring::npos:end-start);
        if(!line.empty()&&line.back()==L'\r')line.pop_back();
        if(!line.empty()){
            if(line.size()<67||line[64]!=L' '||(line[65]!=L' '&&line[65]!=L'*'))return {};
            auto digest=line.substr(0,64);for(auto& c:digest){if(c>=L'A'&&c<=L'F')c+=L'a'-L'A';if(!((c>=L'0'&&c<=L'9')||(c>=L'a'&&c<=L'f')))return {};}
            if(line.substr(66)==file){if(result)return {};result=digest;}
        }
        if(end==std::wstring::npos)break;start=end+1;
    }
    return result;
}
}
