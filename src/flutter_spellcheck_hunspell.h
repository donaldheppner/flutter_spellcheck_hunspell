#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>

#if _WIN32
#include <windows.h>
#else
#include <pthread.h>
#include <unistd.h>
#endif

#if _WIN32
#define FFI_PLUGIN_EXPORT __declspec(dllexport)
#else
#define FFI_PLUGIN_EXPORT
#endif

#ifdef __cplusplus
extern "C" {
#endif

typedef struct HunspellHandle HunspellHandle;

FFI_PLUGIN_EXPORT HunspellHandle* FlutterHunspell_create(const char* aff_path, const char* dic_path);
FFI_PLUGIN_EXPORT void FlutterHunspell_destroy(HunspellHandle* handle);
FFI_PLUGIN_EXPORT int FlutterHunspell_spell(HunspellHandle* handle, const char* word);
FFI_PLUGIN_EXPORT char** FlutterHunspell_suggest(HunspellHandle* handle, const char* word, int* count);
FFI_PLUGIN_EXPORT int FlutterHunspell_add(HunspellHandle* handle, const char* word);
FFI_PLUGIN_EXPORT void FlutterHunspell_free_suggestions(HunspellHandle* handle, char** slist, int n);

#ifdef __cplusplus
}
#endif
