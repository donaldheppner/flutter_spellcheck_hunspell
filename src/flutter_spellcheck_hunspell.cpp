#include "flutter_spellcheck_hunspell.h"
#include <hunspell.hxx>
#include <cstring>
#include <vector>
#include <string>

extern "C" {

FFI_PLUGIN_EXPORT HunspellHandle* FlutterHunspell_create(const char* aff_path, const char* dic_path) {
    return reinterpret_cast<HunspellHandle*>(new Hunspell(aff_path, dic_path));
}

FFI_PLUGIN_EXPORT void FlutterHunspell_destroy(HunspellHandle* handle) {
    delete reinterpret_cast<Hunspell*>(handle);
}

FFI_PLUGIN_EXPORT int FlutterHunspell_spell(HunspellHandle* handle, const char* word) {
    if (!handle || !word) return 0;
    
    // Convert to std::string handling potential null termination issues, though const char* implies it.
    std::string wordStr(word);
    
    return reinterpret_cast<Hunspell*>(handle)->spell(wordStr) ? 1 : 0;
}

FFI_PLUGIN_EXPORT char** FlutterHunspell_suggest(HunspellHandle* handle, const char* word, int* count) {
    if (!handle || !word || !count) return nullptr;

    std::vector<std::string> suggestions = reinterpret_cast<Hunspell*>(handle)->suggest(word);
    
    *count = static_cast<int>(suggestions.size());
    if (*count == 0) return nullptr;

    // Allocate array of pointers
    char** result = (char**)malloc(sizeof(char*) * (*count));
    if (!result) return nullptr;

    for (int i = 0; i < *count; ++i) {
        // Allocate memory for each string and copy
        size_t len = suggestions[i].length() + 1;
        result[i] = (char*)malloc(len);
        if (result[i]) {
            memcpy(result[i], suggestions[i].c_str(), len);
        } else {
            // Memory allocation failed, cleanup up specifically would be good but for now simple return
            // In a robust system we'd unwind.
        }
    }
    return result;
}

FFI_PLUGIN_EXPORT void FlutterHunspell_free_suggestions(HunspellHandle* handle, char** slist, int n) {
    if (slist) {
        for (int i = 0; i < n; ++i) {
            if (slist[i]) {
                free(slist[i]);
            }
        }
        free(slist);
    }
}

} // extern "C"
