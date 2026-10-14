#pragma once
#include <string>
#include <vector>
#include <cwctype>
#include <limits>
#include <stdexcept>
#include "../Shared/TranscriptFormatting.h"

namespace flow {
class TranscriptFinalizer {
    std::wstring text_;double since_=0;bool candidate_=false;
public:
    void reset(){text_.clear();since_=0;candidate_=false;}
    bool accept(const std::wstring& text,bool ready,bool recording,bool transcribing,double time){
        if(!ready||recording||transcribing||text.empty()){reset();return false;}
        if(!candidate_||text!=text_){text_=text;since_=time;candidate_=true;return false;}
        return time-since_>=0.2;
    }
};
// Both platforms use the same native UTF-8 formatting engine.
inline std::string transcriptUTF8(const std::wstring& source) {
    std::string result;
    for(size_t i=0;i<source.size();++i){uint32_t c=uint32_t(source[i]);
        if(c>=0xd800&&c<=0xdbff&&i+1<source.size()){uint32_t low=uint32_t(source[++i]);if(low<0xdc00||low>0xdfff)throw std::runtime_error("Invalid Unicode");c=0x10000+((c-0xd800)<<10)+(low-0xdc00);}
        if(c>=0xd800&&c<=0xdfff)throw std::runtime_error("Invalid Unicode");
        if(c<0x80)result+=char(c);
        else if(c<0x800){result+=char(0xc0|(c>>6));result+=char(0x80|(c&63));}
        else if(c<0x10000){result+=char(0xe0|(c>>12));result+=char(0x80|((c>>6)&63));result+=char(0x80|(c&63));}
        else if(c<=0x10ffff){result+=char(0xf0|(c>>18));result+=char(0x80|((c>>12)&63));result+=char(0x80|((c>>6)&63));result+=char(0x80|(c&63));}
        else throw std::runtime_error("Invalid Unicode");
    }return result;
}
inline std::wstring transcriptWide(const std::string& source){
    std::wstring result;
    for(size_t i=0;i<source.size();){uint32_t c=static_cast<unsigned char>(source[i++]);unsigned count=0;
        if(c>=0xf0){c&=7;count=3;}else if(c>=0xe0){c&=15;count=2;}else if(c>=0xc0){c&=31;count=1;}
        while(count--){if(i==source.size())throw std::runtime_error("Invalid Unicode");c=(c<<6)|(static_cast<unsigned char>(source[i++])&63);}
        if(sizeof(wchar_t)==2&&c>0xffff){c-=0x10000;result+=wchar_t(0xd800+(c>>10));result+=wchar_t(0xdc00+(c&1023));}else result+=wchar_t(c);
    }return result;
}
inline std::wstring readableTranscript(const std::wstring& source){
    try{return transcriptWide(flow_format::format(transcriptUTF8(source)));}catch(...){return source;}
}
}
