#include "flutter_spellcheck_hunspell.h"
#include <hunspell/hunspell.hxx>
#include <cstring>
#include <vector>
#include <string>

// Internal structure to wrap Hunspell C++ object
struct HunspellHandle {
    Hunspell* hunspell;
};

FFI_PLUGIN_EXPORT HunspellHandle* Hunspell_create(const char* aff_path, const char* dic_path) {
    auto handle = new HunspellHandle();
    handle->hunspell = new Hunspell(aff_path, dic_path);
    return handle;
}

FFI_PLUGIN_EXPORT void Hunspell_destroy(HunspellHandle* handle) {
    if (handle) {
        if (handle->hunspell) {
            delete handle->hunspell;
        }
        delete handle;
    }
}

FFI_PLUGIN_EXPORT int Hunspell_spell(HunspellHandle* handle, const char* word) {
    if (!handle || !handle->hunspell) return 0;
    return handle->hunspell->spell(word);
}

FFI_PLUGIN_EXPORT char** Hunspell_suggest(HunspellHandle* handle, const char* word, int* count) {
    if (!handle || !handle->hunspell || !word || !count) return nullptr;

    std::vector<std::string> suggestions = handle->hunspell->suggest(word);
    
    *count = static_cast<int>(suggestions.size());
    if (*count == 0) return nullptr;

    // Allocate memory for the array of strings
    char** result = (char**)malloc(*count * sizeof(char*));
    if (!result) return nullptr;

    for (int i = 0; i < *count; ++i) {
        // Allocate memory for each string
        result[i] = _strdup(suggestions[i].c_str());
    }

    return result;
}

FFI_PLUGIN_EXPORT void Hunspell_free_suggestions(HunspellHandle* handle, char** slist, int n) {
    if (!slist) return;
    for (int i = 0; i < n; ++i) {
        if (slist[i]) free(slist[i]);
    }
    free(slist);
}
