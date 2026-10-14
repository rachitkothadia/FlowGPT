#pragma once
#include "CurrencyData.h"
#include <cstdint>
#include <limits>
namespace flow_format {
struct MoneyToken { size_t start,end;std::string word; };
inline std::vector<MoneyToken> moneyTokens(const std::string& text){
    std::vector<MoneyToken> tokens;
    for(size_t p=0;p<text.size();){
        auto delimiter=[&](size_t i){char c=text[i];if(space(c)||c==';'||c==':'||c=='!'||c=='?'||c=='('||c==')')return true;
            return c==','&&!(i&&i+1<text.size()&&std::isdigit(static_cast<unsigned char>(text[i-1]))&&std::isdigit(static_cast<unsigned char>(text[i+1])));};
        if(delimiter(p)){++p;continue;}size_t from=p;while(p<text.size()&&!delimiter(p))++p;size_t end=p;
        while(end>from&&text[end-1]=='.')--end;
        if(end>from)tokens.push_back({from,end,lower(text.substr(from,end-from))});
    }return tokens;
}
inline std::string moneyDigits(const std::string& word){
    std::string out;bool digit=false;
    for(size_t p=0;p<word.size();){uint32_t c=static_cast<unsigned char>(word[p++]);unsigned n=0;
        if(c>=0xf0){c&=7;n=3;}else if(c>=0xe0){c&=15;n=2;}else if(c>=0xc0){c&=31;n=1;}
        while(n--){if(p==word.size())return {};c=(c<<6)|(static_cast<unsigned char>(word[p++])&63);}
        if(c=='.'||c==','||((c=='-'||c=='+'||c==0x2212)&&out.empty())){out+=c==0x2212?'-':char(c);continue;}
        bool found=false;for(uint32_t zero:{0x30u,0x660u,0x6f0u,0x966u,0x9e6u,0xa66u,0xae6u,0xb66u,0xbe6u,0xc66u,0xce6u,0xd66u,0xe50u,0xed0u,0xff10u})if(c>=zero&&c<zero+10){out+=char('0'+c-zero);found=true;digit=true;break;}
        if(!found)return {};
    }
    if(!digit||out.empty()||out.back()=='.'||out.back()==',')return {};return out;
}
inline const std::unordered_map<std::string,uint64_t>& smallMoneyNumbers(){
    static const std::unordered_map<std::string,uint64_t> words={
        {"zero",0},{"one",1},{"two",2},{"three",3},{"four",4},{"five",5},{"six",6},{"seven",7},{"eight",8},{"nine",9},{"ten",10},{"eleven",11},{"twelve",12},{"thirteen",13},{"fourteen",14},{"fifteen",15},{"sixteen",16},{"seventeen",17},{"eighteen",18},{"nineteen",19},{"twenty",20},{"thirty",30},{"forty",40},{"fifty",50},{"sixty",60},{"seventy",70},{"eighty",80},{"ninety",90},
        {"शून्य",0},{"एक",1},{"दो",2},{"दोन",2},{"तीन",3},{"चार",4},{"पांच",5},{"पाँच",5},{"पाच",5},{"छह",6},{"सहा",6},{"सात",7},{"आठ",8},{"नौ",9},{"नऊ",9},{"दस",10},{"दहा",10},{"ग्यारह",11},{"बारह",12},{"तेरह",13},{"चौदह",14},{"पंद्रह",15},{"सोलह",16},{"सत्रह",17},{"अठारह",18},{"उन्नीस",19},{"बीस",20},{"तीस",30},{"चालीस",40},{"पचास",50},{"साठ",60},{"सत्तर",70},{"अस्सी",80},{"नब्बे",90}
    };return words;
}
inline uint64_t moneyScale(const std::string& word){
    if(word=="hundred"||word=="सौ"||word=="शंभर")return 100;
    if(word=="thousand"||word=="हजार"||word=="हज़ार")return 1000;
    if(word=="lakh"||word=="lakhs"||word=="लाख")return 100000;
    if(word=="million")return 1000000;
    if(word=="crore"||word=="crores"||word=="करोड़"||word=="कोटी")return 10000000;
    if(word=="billion")return 1000000000;
    return 0;
}
inline bool moneyWord(const std::string& w){return !moneyDigits(w).empty()||smallMoneyNumbers().count(w)||moneyScale(w)||w=="and"||w=="a"||w=="point"||w=="decimal"||w=="negative"||w=="minus";}
inline std::string parseMoney(const std::vector<MoneyToken>& words,size_t a,size_t b){
    if(a>=b||b-a>16)return {};
    if(b==a+1&&!moneyDigits(words[a].word).empty())return moneyDigits(words[a].word);
    uint64_t total=0,part=0,last=0,lastScale=std::numeric_limits<uint64_t>::max();bool seen=false,negative=false,hasSmall=false;
    size_t i=a;if(words[i].word=="negative"||words[i].word=="minus"){negative=true;++i;}
    std::string fraction;
    for(;i<b;++i){auto w=words[i].word;
        if(w=="and"){if(!seen||i+1==b)return {};continue;}
        if(w=="a"){if(i+1>=b||!moneyScale(words[i+1].word))return {};part=1;seen=true;continue;}
        if(w=="point"||w=="decimal"){
            if(!seen||i+1==b)return {};for(++i;i<b;++i){auto it=smallMoneyNumbers().find(words[i].word);if(it==smallMoneyNumbers().end()||it->second>9)return {};fraction+=char('0'+it->second);}break;
        }
        auto scale=moneyScale(w);
        if(scale){if(scale==100){if(part>99||(hasSmall&&last>=100))return {};part=(part?part:1)*scale;}
            else {if(scale>=lastScale||part>std::numeric_limits<uint64_t>::max()/scale)return {};uint64_t value=(part?part:1)*scale;if(total>std::numeric_limits<uint64_t>::max()-value)return {};total+=value;part=0;lastScale=scale;}
            seen=true;hasSmall=false;continue;
        }
        auto number=smallMoneyNumbers().find(w);if(number==smallMoneyNumbers().end())return {};
        if(hasSmall&&!(last>=20&&last%10==0&&number->second<10))return {};
        if(part>std::numeric_limits<uint64_t>::max()-number->second)return {};part+=number->second;last=number->second;hasSmall=true;seen=true;
    }
    if(!seen||total>std::numeric_limits<uint64_t>::max()-part)return {};
    return (negative?"-":"")+std::to_string(total+part)+(fraction.empty()?"":"."+fraction);
}
inline std::string moneyDisplay(const std::string& symbol,const std::string& amount){
    std::string number=amount,sign;if(!number.empty()&&(number.front()=='-'||number.front()=='+')){sign=number.substr(0,1);number.erase(0,1);}
    bool code=symbol.size()==3&&std::all_of(symbol.begin(),symbol.end(),[](char c){return c>='A'&&c<='Z';});
    return sign+symbol+(code?" ":"")+number;
}
inline std::string normalizeMoney(const std::string& text){
    auto tokens=moneyTokens(text);auto mask=protectedBytes(text);struct Edit{size_t a,b;std::string value;};std::vector<Edit> edits;size_t consumed=0;
    for(size_t i=0;i<tokens.size();++i){if(tokens[i].start<consumed||mask[tokens[i].start])continue;
        size_t end=i;std::string symbol,alias;
        for(size_t j=i;j<std::min(tokens.size(),i+8);++j){if(j>i&&trim(text.substr(tokens[j-1].end,tokens[j].start-tokens[j-1].end)).size())break;if(mask[tokens[j].start])break;
            alias+=(j==i?"":" ")+tokens[j].word;auto found=currencyAliases().find(alias);if(found!=currencyAliases().end()){symbol=found->second;end=j+1;}
        }
        if(symbol.empty())continue;
        auto raw=text.substr(tokens[i].start,tokens[end-1].end-tokens[i].start);
        auto code=raw;for(auto& c:code)if(c>='a'&&c<='z')c=char(c-'a'+'A');bool iso=code.size()==3&&currencyCodes().count(code);
        if(iso&&raw!=code)continue;
        size_t a=i;while(a&&i-a<16&&moneyWord(tokens[a-1].word)&&trim(text.substr(tokens[a-1].end,tokens[a].start-tokens[a-1].end)).empty())--a;
        while(a<i&&tokens[a].word=="and")++a;
        auto amount=parseMoney(tokens,a,i);size_t b=end;
        // Prefix ISO money notation is allowed; verb homographs such as "won 100" are not.
        if(amount.empty()&&iso&&end<tokens.size()&&trim(text.substr(tokens[end-1].end,tokens[end].start-tokens[end-1].end)).empty()){
            b=end;while(b<tokens.size()&&b-end<16&&moneyWord(tokens[b].word)&&(! (b>end) || trim(text.substr(tokens[b-1].end,tokens[b].start-tokens[b-1].end)).empty()))++b;
            while(b>end&&tokens[b-1].word=="and")--b;
            amount=parseMoney(tokens,end,b);a=i;
        }
        if(amount.empty())continue;
        auto before=a?tokens[a-1].word:"";auto after=b<tokens.size()?tokens[b].word:"";
        bool technical=false;for(const auto* term:{"variable","code","course","class","version","build","status","rows","items","times","half","quarter","डेढ़","सवा","साढ़े","पौने"})if(before==term||after==term)technical=true;
        bool weight=false;
        if(raw=="pounds"||raw=="pound")for(const auto* term:{"of","weight","weighs","weighed","weigh","heavy","lbs","lb"})if(before==term||after==term)weight=true;
        bool unclearMultiplier=false;
        if(a&&moneyScale(tokens[a].word)&&trim(text.substr(tokens[a-1].end,tokens[a].start-tokens[a-1].end)).empty()){
            unclearMultiplier=true;
            for(const auto* word:{"paid","pay","cost","costs","owe","owes","need","needs","spend","spending","for","about","around","approximately","me","us","you","him","her","them","मुझे","हमें","तुम्हें","उसे","चाहिए","दिए","लगे"})if(before==word)unclearMultiplier=false;
        }
        if(technical||weight||unclearMultiplier||tokens[a].start<consumed)continue;
        edits.push_back({tokens[a].start,tokens[b-1].end,moneyDisplay(symbol,amount)});consumed=tokens[b-1].end;i=end-1;
    }
    auto result=text;for(auto e=edits.rbegin();e!=edits.rend();++e)result.replace(e->a,e->b-e->a,e->value);return result;
}
}
