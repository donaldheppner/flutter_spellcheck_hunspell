import 'dart:ffi';
import 'dart:io';
import 'package:ffi/ffi.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'flutter_spellcheck_hunspell_bindings_generated.dart';

class HunspellSpellCheckService extends SpellCheckService {
  final HunspellBindings _bindings;
  Pointer<HunspellHandle>? _hunspell;

  HunspellSpellCheckService({HunspellBindings? bindings})
    : _bindings =
          bindings ??
          HunspellBindings(
            DynamicLibrary.open(
              Platform.isWindows ? 'flutter_spellcheck_hunspell.dll' : 'libflutter_spellcheck_hunspell.so',
            ),
          );

  /// Initialize Hunspell with specific dictionary files.
  ///
  /// [affPath] and [dicPath] must be absolute paths to the files on disk.
  Future<void> init(String affPath, String dicPath) async {
    _disposeHunspell();

    final aff = affPath.toNativeUtf8();
    final dic = dicPath.toNativeUtf8();

    try {
      _hunspell = _bindings.Hunspell_create(aff.cast(), dic.cast());
    } finally {
      calloc.free(aff);
      calloc.free(dic);
    }
  }

  void _disposeHunspell() {
    if (_hunspell != null) {
      _bindings.Hunspell_destroy(_hunspell!);
      _hunspell = null;
    }
  }

  @override
  Future<List<SuggestionSpan>?> fetchSpellCheckSuggestions(Locale locale, String text) async {
    if (_hunspell == null) {
      // In a real app, you might want to load the dictionary based on the locale here
      // if not already initialized. For now, we assume init() was called manually.
      debugPrint('Hunspell not initialized. Call init() first.');
      return [];
    }

    final List<SuggestionSpan> spans = [];
    final words = text.split(RegExp(r'\s+'));

    int offset = 0;
    for (final word in words) {
      // Simple offset calculation - this is naive and might fail with complex whitespace
      // A more robust implementation would use a textizer or careful tracking
      final start = text.indexOf(word, offset);
      if (start == -1) {
        // Should not happen if we split by space correctly and text doesn't change
        continue;
      }
      offset = start + word.length;

      if (word.isEmpty) continue;

      // Strip punctuation for checking (simplistic)
      final cleanWord = word.replaceAll(RegExp(r'[^\w\-]'), '');
      if (cleanWord.isEmpty) continue;

      final wordPtr = cleanWord.toNativeUtf8();
      try {
        final result = _bindings.Hunspell_spell(_hunspell!, wordPtr.cast());
        if (result == 0) {
          // Misspelled
          final countPtr = calloc<Int>();
          final suggestionsPtr = _bindings.Hunspell_suggest(_hunspell!, wordPtr.cast(), countPtr);
          final count = countPtr.value;

          final List<String> suggestions = [];
          if (suggestionsPtr != nullptr) {
            for (int i = 0; i < count; i++) {
              final suggestion = suggestionsPtr[i].cast<Utf8>().toDartString();
              suggestions.add(suggestion);
            }
            _bindings.Hunspell_free_suggestions(_hunspell!, suggestionsPtr, count);
          }
          calloc.free(countPtr);

          spans.add(SuggestionSpan(TextRange(start: start, end: start + word.length), suggestions));
        }
      } finally {
        calloc.free(wordPtr);
      }
    }

    return spans;
  }

  void dispose() {
    _disposeHunspell();
  }
}
