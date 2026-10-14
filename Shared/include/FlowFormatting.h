#pragma once
#include <stddef.h>
#ifdef __cplusplus
extern "C" {
#endif
char* flow_format_transcript(const char* text);
void flow_free_transcript(char* text);
#ifdef __cplusplus
}
#endif
