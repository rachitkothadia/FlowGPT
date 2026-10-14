#include "../TranscriptFormatting.h"
#include <chrono>
#include <iostream>
int main(){
    std::string text="Shopping list: ";for(int i=0;i<1000;++i){if(i)text+=", ";text+="item"+std::to_string(i);}
    auto start=std::chrono::steady_clock::now();auto out=flow_format::format(text);
    auto elapsed=std::chrono::duration<double,std::milli>(std::chrono::steady_clock::now()-start).count();
    size_t bullets=0,offset=0;while((offset=out.find("\n- ",offset))!=std::string::npos){++bullets;offset+=3;}
    if(bullets!=1000||flow_format::format(out)!=out)return 1;
    std::cout<<"1000 arbitrary items: "<<elapsed<<" ms; all 1000 retained\n";
}
