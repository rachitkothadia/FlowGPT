#pragma once
#include <string>
#include <vector>
#include <cwctype>
#include <limits>

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
// This formatter only changes whitespace around already spoken/written numeric
// labels. It never guesses lists from prose, edits a token, or interprets speech.
inline std::wstring readableTranscript(const std::wstring& source){
    if(source.find_first_of(L"`\"'“”‘’")!=std::wstring::npos||source.find(L"://")!=std::wstring::npos||source.find(L"www.")!=std::wstring::npos||source.find(L"\\")!=std::wstring::npos||source.find(L"/")!=std::wstring::npos)return source;
    struct Marker{size_t position;uint64_t number;};std::vector<Marker> markers;
    for(size_t i=0;i<source.size();++i){
        if(source[i]<L'0'||source[i]>L'9'||(i&& !iswspace(source[i-1])))continue;
        size_t end=i;uint64_t value=0;bool overflow=false;
        while(end<source.size()&&source[end]>=L'0'&&source[end]<=L'9'){
            unsigned digit=unsigned(source[end]-L'0');if(value>(std::numeric_limits<uint64_t>::max()-digit)/10){overflow=true;break;}value=value*10+digit;++end;
        }
        if(overflow||end>=source.size()||source[end]!=L'.'||end+1>=source.size()||!iswspace(source[end+1]))continue;
        markers.push_back({i,value});i=end;
    }
    if(markers.size()<2||markers.front().number!=1)return source;
    size_t prefix=markers.front().position;while(prefix&&iswspace(source[prefix-1]))--prefix;
    if(prefix&&source[prefix-1]!=L':')return source;
    for(size_t i=1;i<markers.size();++i)if(markers[i].number!=markers[i-1].number+1)return source;
    std::wstring result=source;
    for(auto it=markers.rbegin();it!=markers.rend();++it){
        if(!it->position)continue;size_t start=it->position;
        while(start&& (result[start-1]==L' '||result[start-1]==L'\t'))--start;
        if(start&&result[start-1]==L'\n')continue;
        result.replace(start,it->position-start,L"\n");
    }
    return result;
}
}
