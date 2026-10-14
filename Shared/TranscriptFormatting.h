#pragma once
#include <algorithm>
#include <cctype>
#include <regex>
#include <string>
#include <vector>
#include <utility>

// UTF-8 text is kept byte-for-byte except presentation and unambiguous fillers.
// No model, substitutions, user history, dictionary correction or speech execution.
namespace flow_format {
inline bool space(char c) { return c==' '||c=='\t'||c=='\r'||c=='\n'; }
inline bool asciiWord(char c) { return std::isalnum(static_cast<unsigned char>(c))||c=='_'; }
inline std::string trim(const std::string& s) { auto a=s.find_first_not_of(" \t\r\n");return a==std::string::npos?"":s.substr(a,s.find_last_not_of(" \t\r\n")-a+1); }
inline std::string lower(std::string s) { for(auto& c:s)if(c>='A'&&c<='Z')c=char(c-'A'+'a');return s; }
inline bool begins(const std::string& s,const std::string& p) { return s.compare(0,p.size(),p)==0; }
inline bool boundary(const std::string& s,size_t p) { return p==0||space(s[p-1])||s[p-1]==':'||s[p-1]==','||s[p-1]=='.'; }
inline std::vector<bool> protectedBytes(const std::string& s) {
    std::vector<bool> mask(s.size(),false);
    for(size_t i=0;i<s.size();++i){
        char q=s[i];
        if(q=='`'||q=='"'||(q=='\''&&(i==0||!asciiWord(s[i-1])))) {
            size_t end=s.find(q,i+1);if(end==std::string::npos)end=s.size()-1;
            for(size_t p=i;p<=end;++p)mask[p]=true;i=end;
        }
    }
    for(const auto& pair:std::vector<std::pair<std::string,std::string>>{{"“","”"},{"‘","’"}}) {
        size_t from=0;
        while((from=s.find(pair.first,from))!=std::string::npos){auto end=s.find(pair.second,from+pair.first.size());end=end==std::string::npos?s.size():end+pair.second.size();for(size_t p=from;p<end;++p)mask[p]=true;from=end;}
    }
    for(size_t i=0;i<s.size();) {
        if(space(s[i])){++i;continue;}size_t end=i;while(end<s.size()&&!space(s[end]))++end;
        auto token=s.substr(i,end-i);
        bool literal=token.find('/')!=std::string::npos||token.find('\\')!=std::string::npos||token.find('@')!=std::string::npos||token.find('_')!=std::string::npos;
        // Filenames, domains, dotted identifiers and decimal numbers.
        for(size_t p=1;p+1<token.size();++p)if(token[p]=='.'&&asciiWord(token[p-1])&&asciiWord(token[p+1]))literal=true;
        if(literal){size_t last=end;while(last>i&&(s[last-1]==','||s[last-1]=='.'||s[last-1]==';'||s[last-1]=='!'||s[last-1]=='?'))--last;for(size_t p=i;p<last;++p)mask[p]=true;}i=end;
    }
    return mask;
}
inline std::string fillers(const std::string& s) {
    auto mask=protectedBytes(s);std::string out;size_t kept=0;
    // Never treat code identifiers or explanations of words as hesitation.
    bool code=s.find('=')!=std::string::npos||s.find("The word ")!=std::string::npos||s.find(" is a variable")!=std::string::npos;
    for(size_t i=0;i<s.size();) {
        if(!boundary(s,i)||!asciiWord(s[i])){++i;continue;}size_t end=i;while(end<s.size()&&asciiWord(s[end]))++end;
        auto word=lower(s.substr(i,end-i));bool filler=word=="um"||word=="umm"||word=="uh"||word=="err";
        auto before=filler?lower(trim(s.substr(0,i))):std::string{};
        auto after=filler?lower(trim(s.substr(end))):std::string{};
        bool meaningful=begins(after,"is ")||begins(after,"means ")||begins(after,"on ")||begins(after,"or ");
        bool context=!meaningful&&(i==0||(!before.empty()&&(before.back()==','||before.back()=='.'))||begins(after,"and ")||begins(after,"so "));
        if(filler&&context&&!mask[i]&&!code) {
            size_t through=end;if(through<s.size()&&s[through]==',')++through;while(through<s.size()&&(s[through]==' '||s[through]=='\t'))++through;
            out+=s.substr(kept,i-kept);kept=through;i=through;
        }else i=end;
    }
    return out+s.substr(kept);
}
inline std::string capitalize(std::string s) {
    auto a=s.find_first_not_of(" \t\r\n");if(a==std::string::npos)return s;
    auto rest=lower(s.substr(a));
    // Capitalize only ordinary introductory function words; preserve names/acronyms/code.
    for(const auto* word:{"okay","listen","i","aur"}) {
        std::string w=word;if(begins(rest,w)&&(rest.size()==w.size()||!asciiWord(rest[w.size()]))){s[a]=char(std::toupper(static_cast<unsigned char>(s[a])));break;}
    }
    return s;
}
inline bool cue(const std::string& s) {
    auto t=lower(s);
    for(const auto* p:{"list","lists","steps","tasks","items","things","required","requirements","ingredients","following","kaam","काम","चीज","सूची","यादी","કામ","યાદી"}){
        auto at=t.find(p);size_t n=std::char_traits<char>::length(p);
        while(at!=std::string::npos){if(static_cast<unsigned char>(*p)>=128||(boundary(t,at)&&(at+n==t.size()||!asciiWord(t[at+n]))))return true;at=t.find(p,at+1);}
    }
    return false;
}
inline std::string separateNumeric(const std::string& s) {
    auto mask=protectedBytes(s);static const std::regex numeric("(^|[ \\t\\n])([0-9]+)\\.[ \\t]+");
    std::vector<size_t> positions;size_t next=1;
    for(std::sregex_iterator i(s.begin(),s.end(),numeric),e;i!=e;++i){
        auto p=size_t(i->position(2));if(mask[p])continue;
        if(i->str(2)!=std::to_string(next++))return s;positions.push_back(p);
    }
    if(positions.size()<2)return s;auto prefix=trim(s.substr(0,positions.front()));if(!prefix.empty()&&prefix.back()!=':')return s;
    auto out=s;for(auto i=positions.rbegin();i!=positions.rend();++i){size_t a=*i;while(a&&(out[a-1]==' '||out[a-1]=='\t'))--a;if(a&&out[a-1]!='\n')out.replace(a,*i-a,"\n");}return out;
}
struct Ordinal { const char* text; size_t number; };
inline std::string spokenSequence(const std::string& s) {
    static const Ordinal words[]={{"first",1},{"second",2},{"third",3},{"fourth",4},{"fifth",5},{"sixth",6},{"seventh",7},{"eighth",8},{"ninth",9},{"tenth",10},
        {"pehla",1},{"pehle",1},{"dusra",2},{"teesra",3},{"पहला",1},{"पहले",1},{"दूसरा",2},{"तीसरा",3},{"प्रथम",1},{"दुसरा",2},{"तिसरा",3},{"પહેલું",1},{"પહેલું",1},{"પહેલું",1},{"બીજા",2},{"બીજું",2},{"ત્રીજું",3}};
    auto t=lower(s);auto mask=protectedBytes(s);std::vector<size_t> positions;size_t next=1;
    for(size_t i=0;i<t.size();++i) {
        if(mask[i]||!boundary(s,i))continue;
        for(const auto& w:words){size_t n=std::char_traits<char>::length(w.text);if(t.compare(i,n,w.text)==0&&(i+n==t.size()||space(t[i+n])||t[i+n]==','||t[i+n]==':')) {
            if(w.number==next){positions.push_back(i);++next;}break;
        }}
    }
    if(positions.size()<2||!cue(s.substr(0,positions.front())))return s;
    size_t tail=s.size();
    for(const auto* marker:{"aur haan","और हाँ","અને હા","anyway ","afterwards "}) {
        auto p=t.find(marker,positions.back()+1);if(p!=std::string::npos&&boundary(s,p))tail=std::min(tail,p);
    }
    auto intro=trim(s.substr(0,positions.front()));if(!intro.empty()&&intro.back()!=':')intro+=':';
    std::string out=intro;
    for(size_t i=0;i<positions.size();++i)out+="\n"+std::to_string(i+1)+". "+trim(s.substr(positions[i],(i+1<positions.size()?positions[i+1]:tail)-positions[i]));
    if(tail<s.size())out+="\n\n"+capitalize(trim(s.substr(tail)));
    return out;
}
inline size_t sentenceEnd(const std::string& s,const std::vector<bool>& mask,size_t from) {
    for(size_t i=from;i<s.size();++i){if(mask[i])continue;
        if(s.compare(i,3,"।")==0)return i+3;
        if((s[i]=='.'||s[i]=='!'||s[i]=='?')&&(i+1==s.size()||space(s[i+1])))return i+1;
    }return s.size();
}
inline bool listItem(const std::string& text) {
    auto t=lower(trim(text));size_t count=1;for(char c:t)if(space(c))++count;
    if(t.empty()||count>16)return false;
    for(const auto* p:{"when ","if ","no ","actually ","wait ","instead ","नहीं ","नाही ","i ","and i ","but ","because ","he ","she "})if(begins(t,p))return false;
    return true;
}
inline std::string enumerations(const std::string& s) {
    if(s.find("\n- ")!=std::string::npos||s.find("\n1. ")!=std::string::npos)return s;
    auto mask=protectedBytes(s);auto t=lower(s);
    for(size_t p=0;p<s.size();++p) {
        if(mask[p])continue;size_t from=std::string::npos;
        if(s[p]==':')from=p+1;
        // Introduced noun enumerations need no spoken "colon" command.
        for(const auto* marker:{"it would be ","things like ","items are ","we need ","i need ","i require ","includes ","include ","these are ","ये हैं ","हे आहेत "}) {
            size_t n=std::char_traits<char>::length(marker);
            if(t.compare(p,n,marker)==0&&boundary(s,p)&&cue(s.substr(0,p+n)))from=p+n;
        }
        if(from==std::string::npos||s.substr(0,from).find('=')!=std::string::npos)continue;
        while(from<s.size()&&space(s[from]))++from;
        size_t end=sentenceEnd(s,mask,from);std::vector<std::string> items;size_t start=from;
        for(size_t j=from;j<end;++j)if(s[j]==','&&!mask[j]){items.push_back(trim(s.substr(start,j-start+1)));start=j+1;}
        items.push_back(trim(s.substr(start,end-start)));
        if(items.size()==1&&cue(s.substr(0,from))) {
            // Conjunction-only enumerations require an explicit list introduction.
            std::vector<size_t> separators;
            for(size_t j=from;j<end;++j){if(mask[j])continue;
                for(const auto* join:{" and then "," and "," और "," आणि "," અને "}) {
                    size_t n=std::char_traits<char>::length(join);
                    if(t.compare(j,n,join)==0){separators.push_back(j);j+=n-1;break;}
                }
            }
            if(separators.size()>=2){items.clear();start=from;
                for(auto j:separators){items.push_back(trim(s.substr(start,j-start)));start=j+1;}
                items.push_back(trim(s.substr(start,end-start)));
            }
        }
        // A trailing personal sentence after the enumeration stays prose.
        if(items.size()>=3&&(begins(lower(items.back()),"and i ")||begins(lower(items.back()),"and we "))) {
            end=start;items.pop_back();
        }
        if(items.size()<2||!std::all_of(items.begin(),items.end(),listItem))continue;
        // At least two separators unless explicit colon or a clear list introduction.
        if(items.size()<3&&s[p]!=':')continue;
        auto prefix=trim(s.substr(0,from));if(!prefix.empty()&&prefix.back()!=':')prefix+=':';
        bool todo=t.substr(0,from).find("to-do list")!=std::string::npos||t.substr(0,from).find("todo list")!=std::string::npos;
        auto out=prefix;for(const auto& item:items)out+=todo?"\n- [ ] "+item:"\n- "+item;
        auto rest=trim(s.substr(end));if(!rest.empty())out+="\n\n"+enumerations(rest);
        return out;
    }
    return s;
}
inline std::string format(const std::string& source) {
    if(source.size()>100000)return source;
    auto text=capitalize(fillers(source));
    if(text.find("\n- ")!=std::string::npos||text.find("\n1. ")!=std::string::npos)return text;
    auto numeric=separateNumeric(text);if(numeric!=text)return numeric;
    auto ordered=spokenSequence(text);if(ordered!=text)return ordered;
    return enumerations(text);
}
}
