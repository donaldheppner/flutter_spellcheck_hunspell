import 'dart:ffi';
import 'dart:io';
import 'dart:ui';

import 'package:ffi/ffi.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_spellcheck_hunspell/flutter_spellcheck_hunspell_bindings_generated.dart';

const String _libName = 'flutter_spellcheck_hunspell';

/// The dynamic library in which the symbols for [HunspellBindings] can be found.
final DynamicLibrary _dylib = () {
  if (Platform.isMacOS || Platform.isIOS) {
    return DynamicLibrary.open('$_libName.framework/$_libName');
  }
  if (Platform.isAndroid || Platform.isLinux) {
    return DynamicLibrary.open('lib$_libName.so');
  }
  if (Platform.isWindows) {
    return DynamicLibrary.open('$_libName.dll');
  }
  throw UnsupportedError('Unknown platform: ${Platform.operatingSystem}');
}();

class HunspellSpellCheckService extends SpellCheckService {
  final HunspellBindings _bindings;
  Pointer<HunspellHandle>? _hunspell;

  HunspellSpellCheckService({HunspellBindings? bindings}) : _bindings = bindings ?? HunspellBindings(_dylib);

  Future<void> init(String affPath, String dicPath) async {
    final aff = affPath.toNativeUtf8();
    final dic = dicPath.toNativeUtf8();
    _hunspell = _bindings.FlutterHunspell_create(aff.cast(), dic.cast());
    malloc.free(aff);
    malloc.free(dic);
  }

  @override
  Future<List<SuggestionSpan>?> fetchSpellCheckSuggestions(Locale locale, String text) async {
    // Wait for the end of the frame to ensure we don't invalidate layout
    // while the context menu is trying to build and calculate anchors.
    if (SchedulerBinding.instance.schedulerPhase != SchedulerPhase.idle) {
      await SchedulerBinding.instance.endOfFrame;
    }

    if (_hunspell == null) {
      return null;
    }

    final List<SuggestionSpan> spans = [];
    final words = text.split(RegExp(r'\s+'));

    int offset = 0;
    for (final word in words) {
      if (word.isEmpty) {
        offset += 1; // Default split might leave empty strings if multiple spaces
        continue;
      }

      // Must calculate correct offset in original text to handle multiple spaces properly
      // This simple split/iteration assumes single space separation which is brittle.
      // A better approach find the word in the text starting from current offset.
      final wordStart = text.indexOf(word, offset);
      if (wordStart == -1) break; // Should not happen

      offset = wordStart + word.length;

      // Strip punctuation? Hunspell might handle it or we might need to.
      // For now pass raw.
      final wordPtr = word.toNativeUtf8();
      final result = _bindings.FlutterHunspell_spell(_hunspell!, wordPtr.cast());

      if (result == 0) {
        // Misspelled
        final countPtr = malloc<Int>();
        final suggestionsPtr = _bindings.FlutterHunspell_suggest(_hunspell!, wordPtr.cast(), countPtr);
        final count = countPtr.value;

        final List<String> suggestions = [];
        if (suggestionsPtr != nullptr) {
          for (int i = 0; i < count; i++) {
            final strPtr = suggestionsPtr[i];
            suggestions.add(strPtr.cast<Utf8>().toDartString());
          }
          _bindings.FlutterHunspell_free_suggestions(_hunspell!, suggestionsPtr, count);
        }
        malloc.free(countPtr);

        spans.add(SuggestionSpan(TextRange(start: wordStart, end: wordStart + word.length), suggestions));
      }
      malloc.free(wordPtr);
    }

    return spans;
  }

  void dispose() {
    if (_hunspell != null) {
      _bindings.FlutterHunspell_destroy(_hunspell!);
      _hunspell = null;
    }
  }
}
