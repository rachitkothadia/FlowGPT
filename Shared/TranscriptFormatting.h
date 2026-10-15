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
        bool grouped=false;for(size_t j=1;j+1<token.size();++j)if(token[j]==','&&std::isdigit(static_cast<unsigned char>(token[j-1]))&&std::isdigit(static_cast<unsigned char>(token[j+1])))grouped=true;
        bool literal=grouped||token.find('/')!=std::string::npos||token.find('\\')!=std::string::npos||token.find('@')!=std::string::npos||token.find('_')!=std::string::npos;
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
}
#include "CurrencyFormatting.h"
namespace flow_format {
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
    if(positions.size()<2)return s;
    auto sequencePrefix=trim(s.substr(0,positions.front()));if(!sequencePrefix.empty()&&!cue(sequencePrefix))return s;
    size_t tail=s.size();
    for(const auto* marker:{"aur haan","और हाँ","અને હા","anyway ","afterwards "}) {
        auto p=t.find(marker,positions.back()+1);if(p!=std::string::npos&&boundary(s,p))tail=std::min(tail,p);
    }
    auto intro=trim(s.substr(0,positions.front()));if(!intro.empty()&&intro.back()!=':')intro+=':';
    std::string out=intro;
    for(size_t i=0;i<positions.size();++i){if(!out.empty())out+='\n';out+=std::to_string(i+1)+". "+trim(s.substr(positions[i],(i+1<positions.size()?positions[i+1]:tail)-positions[i]));}
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
    for(const auto* p:{"when ","if ","no ","not ","actually ","wait ","instead ","नहीं ","नाही ","i ","and i ","but ","because ","he ","she "})if(begins(t,p))return false;
    return true;
}
struct ListPiece { size_t begin,end,item;int kind=0; };
inline std::string unjoin(std::string text){
    text=lower(trim(text));
    for(const auto* prefix:{"and then ","then ","and ","और ","आणि ","અને "})if(begins(text,prefix)){text=text.substr(std::char_traits<char>::length(prefix));break;}
    return text;
}
inline bool connectorOnly(const std::string& source){
    auto t=lower(trim(source));while(!t.empty()&&(t.back()=='.'||t.back()==','||t.back()==':'))t.pop_back();
    for(const auto* word:{"and","then","and then","और","आणि","અને","et","und","y","e","и","と","和"})if(t==word)return true;
    return t.empty();
}
inline bool proceduralItem(const std::string& text){
    auto t=unjoin(text);
    for(const auto* p:{"open ","click ","press ","select ","edit ","save ","close ","type ","enter ","tap ","खोलो ","दबाओ ","निवडा "})if(begins(t,p))return true;
    return false;
}
inline bool monetaryItem(const std::string& text){
    for(const auto* symbol:{"₹","$","€","£","¥","₩","₽","₺","฿","₴","₱","₪","₫"})if(text.find(symbol)!=std::string::npos)return true;
    static const std::regex iso("(^| )([A-Z]{3}) [0-9]");return std::regex_search(text,iso);
}
inline int itemKind(const std::string& source){
    auto t=unjoin(source);while(!t.empty()&&(t.back()=='.'||t.back()==','))t.pop_back();
    if(connectorOnly(t)||t.find('?')!=std::string::npos)return 0;
    for(const auto* term:{"okay","ok","well","so","yeah","and yeah","हाँ","हां","ओके","अच्छा"})if(t==term)return 0;
    size_t count=1;for(char c:t)if(space(c))++count;if(count>22)return 0;
    for(const auto* p:{"when ","if ","no ","not ","actually ","wait ","instead ","नहीं ","नाही ","but ","because ","what ","how ","why "})if(begins(t,p))return 0;
    if(proceduralItem(t))return 3;
    // Parallel future-action phrases are items even when the language is mixed.
    bool action=false;
    if(t.find("would go for ")!=std::string::npos||t.find("will buy ")!=std::string::npos)action=true;
    auto words=moneyTokens(t);
    if(words.size()>=2){auto last=words.back().word;auto previous=words[words.size()-2].word;
        if((last=="है"||last=="हैं"||last=="है।")&&(previous.size()>=6&&(previous.compare(previous.size()-6,6,"ना")==0||previous.compare(previous.size()-6,6,"नी")==0)))action=true;
    }
    if(words.size()>=2&&(words.back().word=="आहे"||words.back().word=="आहे।")){
        auto prev=words[words.size()-2].word;
        if(prev.size()>=12&&(prev.compare(prev.size()-12,12,"ायचे")==0||prev.compare(prev.size()-12,12,"ायची")==0))action=true;
        if(!action)return 0;
    }
    if(action)return 2;
    for(const auto* p:{"अरे ","तू ","तुम ","तुम्ही ","मला ","मी ","मैं ","मुझे "})if(begins(t,p))return 0;
    if(t=="multiple things"||t=="several things"||t=="many things")return 0;
    for(const auto* p:{"i ","i'm ","i’ve ","we ","you ","he ","she ","it ","it's ","they "})if(begins(t,p))return 0;
    for(const auto* p:{" is "," was "," were "," am "," are "," went "," said "," felt "," happened "," because "," when "," while "," i "," i'm "," we "})if(t.find(p)!=std::string::npos&&!monetaryItem(t))return 0;
    return count<=10?1:0;
}
inline size_t itemStart(const std::string& s,size_t a,size_t b){
    auto t=lower(s.substr(a,b-a));size_t offset=0;
    for(const auto* p:{"like ","such as ","जैसे ","म्हणजे "})if(begins(t,p))return a+std::char_traits<char>::length(p);
    // A grammatical introduction may precede the first object; it is not required.
    for(const auto* p:{"things like ","items are ","it would be ","i want to ","we need ","i need ","i require ","buy ","bring ","pack ","collect ","order ","ये हैं ","हे आहेत "}){
        auto pos=t.find(p);if(pos!=std::string::npos&&boundary(t,pos))offset=std::max(offset,pos+std::char_traits<char>::length(p));
    }
    auto colon=t.find(':');if(colon!=std::string::npos)offset=std::max(offset,colon+1);
    while(a+offset<b&&space(s[a+offset]))++offset;return a+offset;
}
struct ListedSentence { std::string text;bool listed=false; };
inline bool additiveItem(const std::string& source){
    auto t=unjoin(source);
    for(const auto* prefix:{"also ","plus ","और एक ","आणखी ","इसके अलावा "})if(begins(t,prefix))return true;
    for(const auto* suffix:{" as well"," too"," भी"," सुद्धा"}){
        auto p=t.rfind(suffix);if(p!=std::string::npos){auto tail=trim(t.substr(p+std::char_traits<char>::length(suffix)));if(tail.empty()||tail=="."||tail=="।")return true;}
    }return false;
}
inline ListedSentence listSentence(const std::string& s,bool continuation){
    auto t=lower(trim(s));
    for(const auto* p:{"i am ","i'm ","it is ","it's ","i was ","it was "})if(begins(t,p)&&t.find("buy ")==std::string::npos)return {s,false};
    for(const auto* correction:{" no ","no actually ","not ","अरे नहीं","नहीं ","nahi "," wait i mean "})if(t.find(correction)!=std::string::npos)return {s,false};
    auto mask=protectedBytes(s);std::vector<ListPiece> pieces;size_t start=0;
    auto append=[&](size_t end){size_t a=start;while(a<end&&space(s[a]))++a;while(end>a&&space(s[end-1]))--end;if(a<end)pieces.push_back({a,end,itemStart(s,a,end),0});};
    for(size_t p=0;p<s.size();++p){if(mask[p])continue;
        if(s[p]==','){append(p);start=p+1;continue;}
        for(const auto* join:{" and then "," and "," then "," और "," आणि "," અને "," ਅਤੇ "," اور "," এবং "," আৰু "," ଏବଂ "," மற்றும் "," మరియు "," ಮತ್ತು "," ഒപ്പം "," र "," et "," und "," y "," e "," и "," と "," 和 "," 및 "}){
            size_t n=std::char_traits<char>::length(join);if(s.compare(p,n,join)==0){
                // A leading connector belongs to the item that follows it.
                if(!connectorOnly(s.substr(start,p-start))){append(p);start=p+1;}
                p+=n-1;break;
            }
        }
    }append(s.size());
    for(auto& part:pieces){
        auto original=lower(s.substr(part.begin,part.end-part.begin));
        bool conversational=original.find("i'm ")!=std::string::npos&&original.find("go for ")==std::string::npos;
        part.kind=itemKind(s.substr(part.item,part.end-part.item));
        if(conversational)part.kind=0;
        if(part.item==part.begin&&cue(s.substr(part.begin,part.end-part.begin))&&part.kind==2)part.kind=0;
    }
    // A short addressee before a question belongs to the question, not the shopping list.
    if(pieces.size()>=2&&s.find('?')!=std::string::npos){auto& before=pieces[pieces.size()-2];auto candidate=lower(trim(s.substr(before.begin,before.end-before.begin)));
        if(begins(candidate,"and ")&&std::count(candidate.begin(),candidate.end(),' ')<=1)before.kind=0;
    }
    size_t a=0,b=0;bool found=false;
    for(size_t i=0;i<pieces.size();){if(!pieces[i].kind){++i;continue;}size_t end=i;while(end<pieces.size()&&pieces[end].kind)++end;
        bool distinct=true;
        for(size_t k=i;k+1<end;++k)if(unjoin(s.substr(pieces[k].item,pieces[k].end-pieces[k].item))==unjoin(s.substr(pieces[k+1].item,pieces[k+1].end-pieces[k+1].item)))distinct=false;
        auto candidate=s.substr(pieces[i].item,pieces[i].end-pieces[i].item);
        bool single=continuation&&end==i+1&&(monetaryItem(candidate)||additiveItem(candidate));
        bool concise=true,actions=true;
        for(size_t k=i;k<end;++k){auto phrase=unjoin(s.substr(pieces[k].item,pieces[k].end-pieces[k].item));concise=concise&&std::count(phrase.begin(),phrase.end(),' ')<=1;actions=actions&&pieces[k].kind>=2;}
        bool explicitDelimiter=s.find(',')!=std::string::npos||s.find(':')!=std::string::npos;
        if((end-i>=2&&distinct&&(end-i>=3||explicitDelimiter||concise||actions||(continuation&&pieces[i].kind>=2)))||single){a=i;b=end;found=true;break;}i=end;
    }
    if(!found)return {s,false};
    bool ordered=b-a>=2;for(size_t i=a;i<b;++i)ordered=ordered&&pieces[i].kind==3;
    auto prefix=trim(s.substr(0,pieces[a].item));while(!prefix.empty()&&prefix.back()==',')prefix.pop_back();prefix=trim(prefix);
    bool resumed=continuation&&b==a+1;
    if(!prefix.empty()&&!resumed&&prefix.back()!=':')prefix+=':';
    if(resumed&&!prefix.empty()&&prefix.back()!=',')prefix+=',';
    std::string out=prefix;
    for(size_t i=a;i<b;++i){auto begin=i==a?pieces[i].item:pieces[i].begin;auto item=trim(s.substr(begin,pieces[i].end-begin));
        if(!out.empty())out+='\n';out+=ordered?std::to_string(i-a+1)+". ":"• ";out+=item;
    }
    auto suffix=trim(s.substr(pieces[b-1].end));if(!suffix.empty()&&suffix.front()==',')suffix=trim(suffix.substr(1));
    if(!suffix.empty())out+="\n\n"+suffix;
    return {out,true};
}
inline std::string enumerations(const std::string& s){
    auto mask=protectedBytes(s);std::string out;unsigned context=0;size_t from=0;bool priorListed=false;
    while(from<s.size()){
        bool existing=!mask[from]&&begins(s.substr(from),"• ");
        size_t lineEnd=s.find('\n',from);if(lineEnd==std::string::npos)lineEnd=s.size();
        size_t end=existing?lineEnd:std::min(lineEnd,sentenceEnd(s,mask,from));
        bool quoted=mask[from]&&((from&&mask[from-1])||s[from]=='`'||s[from]=='"'||begins(s.substr(from),"“")||begins(s.substr(from),"‘"));
        auto processed=existing?ListedSentence{s.substr(from,end-from),true}:quoted?ListedSentence{s.substr(from,end-from),false}:listSentence(s.substr(from,end-from),context>0);
        if(!quoted&&!out.empty()&&begins(processed.text,"• ")){
            auto at=out.find_last_not_of(" \t\r\n");auto gap=out.substr(at==std::string::npos?0:at+1);out=at==std::string::npos?"":out.substr(0,at+1);
            if(!out.empty())out+=priorListed?"\n":existing&&gap.find('\n')!=std::string::npos?gap:out.back()==':'?"\n":"\n\n";
        }
        out+=processed.text;priorListed=processed.listed;
        if(processed.listed)context=3;else if(context)--context;
        size_t next=end;while(next<s.size()&&space(s[next]))++next;
        if(next<s.size())out+=processed.listed?"\n\n":s.substr(end,next-end);
        from=next;
    }return out;
}
struct DeclaredSentence {size_t begin,end;unsigned ordinal;};
inline unsigned declaredOrdinal(const std::string& source){
    auto t=unjoin(source);if(begins(t,"the "))t=t.substr(4);
    static const char* words[]={"one","first","second","third","fourth","fifth","sixth","seventh","eighth","ninth","tenth","eleventh","twelfth","thirteenth","fourteenth","fifteenth","sixteenth","seventeenth","eighteenth","nineteenth","twentieth"};
    for(size_t i=0;i<sizeof(words)/sizeof(*words);++i){std::string w=words[i];if(begins(t,w+" is ")||begins(t,w+" would be "))return i<2?1:unsigned(i);}
    static const std::pair<const char*,unsigned> native[]={{"पहला",1},{"पहली",1},{"दूसरा",2},{"दूसरी",2},{"तीसरा",3},{"तीसरी",3},{"चौथा",4},{"पहिले",1},{"दुसरे",2},{"तिसरे",3}};
    for(const auto& w:native){std::string p=w.first;if(begins(t,p+" ")&&(t.find(" है")!=std::string::npos||t.find(" आहे")!=std::string::npos))return w.second;}
    return 0;
}
inline bool explanationSentence(const std::string& source){
    auto t=lower(trim(source));if(t.find('?')!=std::string::npos)return false;
    for(const auto* p:{"so for ","for that ","because ","since ","it ","it's ","this ","which ","that one ","इसके लिए ","क्योंकि ","त्यासाठी "})if(begins(t,p))return true;
    return false;
}
// Establish sibling item boundaries across sentences before splitting coordinated phrases.
// Explanatory sentences remain attached to the preceding declared object.
inline std::string declaredLists(const std::string& s){
    auto mask=protectedBytes(s);std::vector<DeclaredSentence> sentences;
    for(size_t p=0;p<s.size();){size_t end=sentenceEnd(s,mask,p);unsigned ordinal=mask[p]?0:declaredOrdinal(s.substr(p,end-p));sentences.push_back({p,end,ordinal});p=end;while(p<s.size()&&space(s[p]))++p;}
    struct Edit{size_t begin,end;std::string text;};std::vector<Edit> edits;
    for(size_t i=0;i<sentences.size();++i){if(sentences[i].ordinal!=1)continue;
        std::vector<size_t> starts{i};size_t end=i+1;unsigned next=2;
        for(;end<sentences.size();++end){auto& sentence=sentences[end];if(sentence.ordinal==next){starts.push_back(end);++next;continue;}
            if(!sentence.ordinal&&explanationSentence(s.substr(sentence.begin,sentence.end-sentence.begin)))continue;
            break;
        }
        if(starts.size()<2)continue;
        std::string out;
        for(size_t k=0;k<starts.size();++k){auto from=sentences[starts[k]].begin;auto through=sentences[k+1<starts.size()?starts[k+1]-1:end-1].end;
            if(!out.empty())out+='\n';out+="• "+trim(s.substr(from,through-from));
        }
        auto through=sentences[end-1].end;if(end<sentences.size()){through=sentences[end].begin;out+="\n\n";}
        edits.push_back({sentences[i].begin,through,out});i=end-1;
    }
    auto out=s;for(auto i=edits.rbegin();i!=edits.rend();++i)out.replace(i->begin,i->end-i->begin,i->text);return out;
}
inline std::string joinedConnectorBullets(const std::string& s){
    auto mask=protectedBytes(s);std::string out;size_t from=0;
    while(from<s.size()){
        auto end=s.find('\n',from);if(end==std::string::npos)end=s.size();auto line=s.substr(from,end-from);auto item=trim(line);
        while(!mask[from]&&begins(item,"• ")&&connectorOnly(item.substr(4))&&end<s.size()){
            auto next=end+1;while(next<s.size()&&space(s[next]))++next;
            if(s.compare(next,4,"• ")!=0||mask[next])break;
            auto nextEnd=s.find('\n',next);if(nextEnd==std::string::npos)nextEnd=s.size();
            line+=" "+s.substr(next+4,nextEnd-next-4);item=trim(line);end=nextEnd;
        }
        out+=line;if(end<s.size())out+='\n';from=end+1;
    }return out;
}
inline std::string circleExistingBullets(const std::string& text){
    auto mask=protectedBytes(text);std::vector<size_t> markers;
    for(size_t start=0;start<text.size();){size_t end=text.find('\n',start);if(end==std::string::npos)end=text.size();size_t at=start;while(at<end&&(text[at]==' '||text[at]=='\t'))++at;
        if(at+2<end&&!mask[at]&&(text[at]=='-'||text[at]=='*')&&text[at+1]==' '){
            auto item=trim(text.substr(at+2,end-at-2));bool pureNumber=!moneyDigits(item).empty();
            if(!pureNumber)markers.push_back(at);
        }
        start=end+1;
    }
    if(markers.size()<2)return text;auto out=text;for(auto at=markers.rbegin();at!=markers.rend();++at)out.replace(*at,1,"•");return out;
}
inline std::string format(const std::string& source) {
    if(source.size()>100000)return source;
    auto text=joinedConnectorBullets(circleExistingBullets(normalizeMoney(capitalize(fillers(source)))));
    if(text.find("\n1. ")!=std::string::npos)return text;
    auto numeric=separateNumeric(text);if(numeric!=text)return numeric;
    auto declared=declaredLists(text);if(declared!=text)return enumerations(declared);
    if(text.find("\n• ")==std::string::npos){auto ordered=spokenSequence(text);if(ordered!=text)return ordered;}
    return enumerations(text);
}
}
