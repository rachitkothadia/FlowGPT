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
}
