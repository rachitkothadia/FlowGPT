#include "include/FlowFormatting.h"
#include "TranscriptFormatting.h"
#include <cstdlib>
#include <cstring>
extern "C" char* flow_format_transcript(const char* text) {
    if (!text) return nullptr;
    try {
        auto formatted = flow_format::format(text);
        auto result = static_cast<char*>(std::malloc(formatted.size()+1));
        if (result) std::memcpy(result, formatted.c_str(), formatted.size()+1);
        return result;
    } catch (...) { return nullptr; }
}
extern "C" void flow_free_transcript(char* text) { std::free(text); }
