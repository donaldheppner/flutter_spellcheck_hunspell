import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'dart:ui';

import 'package:ffi/ffi.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
export 'src/hunspell_configuration.dart';
export 'src/hunspell_gesture_detector.dart';
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

/// Commands sent to the isolate
enum _HunspellCommand { init, check, dispose, add, setIgnoredPatterns }

/// Request data sent to the isolate
class _HunspellRequest {
  final int id;
  final _HunspellCommand command;
  final List<dynamic>? args;

  _HunspellRequest(this.id, this.command, [this.args]);
}

/// Response data received from the isolate
class _HunspellResponse {
  final int id;
  final dynamic result;
  final bool error;

  _HunspellResponse(this.id, this.result, {this.error = false});
}

/// A request waiting to be processed.
class _QueuedRequest {
  final String text;
  final Completer<List<SuggestionSpan>?> completer;
  _QueuedRequest(this.text, this.completer);
}

class HunspellSpellCheckService extends SpellCheckService {
  Isolate? _isolate;
  SendPort? _sendPort;
  final ReceivePort _receivePort = ReceivePort();
  final Map<int, Completer<dynamic>> _pendingRequests = {};
  int _nextRequestId = 0;
  bool _isReady = false;

  // Throttling State
  bool _isProcessing = false;
  _QueuedRequest? _nextPendingRequest;

  List<String> _ignoredPatterns = [r"\w+://\S+"];

  HunspellSpellCheckService();

  /// Sets the list of regex patterns to ignore during spell checking.
  /// Synchronization with the background isolate is handled automatically.
  set ignoredPatterns(List<String> value) {
    _ignoredPatterns = value;
    if (_isReady) {
      _sendRequest(_HunspellCommand.setIgnoredPatterns, value);
    }
  }

  Future<void> init(String affPath, String dicPath) async {
    _isolate = await Isolate.spawn(_hunspellIsolateEntry, _receivePort.sendPort);

    final completer = Completer<void>();
    _receivePort.listen((message) {
      if (_sendPort == null && message is SendPort) {
        _sendPort = message;
        completer.complete();
      } else {
        _handleResponse(message);
      }
    });

    await completer.future;

    // Initialize the Hunspell instance inside the isolate
    await _sendRequest(_HunspellCommand.init, [affPath, dicPath]);

    // Sync initial ignored patterns
    await _sendRequest(_HunspellCommand.setIgnoredPatterns, _ignoredPatterns);

    _isReady = true;
  }

  void _handleResponse(dynamic message) {
    if (message is _HunspellResponse) {
      final completer = _pendingRequests.remove(message.id);
      if (completer != null) {
        if (message.error) {
          completer.completeError(message.result);
        } else {
          completer.complete(message.result);
        }
      }
    }
  }

  Future<dynamic> _sendRequest(_HunspellCommand command, [List<dynamic>? args]) {
    final id = _nextRequestId++;
    final completer = Completer<dynamic>();
    _pendingRequests[id] = completer;
    _sendPort?.send(_HunspellRequest(id, command, args));
    return completer.future;
  }

  @override
  Future<List<SuggestionSpan>?> fetchSpellCheckSuggestions(Locale locale, String text) {
    if (!_isReady) {
      return Future.value(null);
    }

    final completer = Completer<List<SuggestionSpan>?>();

    if (_isProcessing) {
      // If we are already running, queue this new request.
      // If there was ALREADY a next request waiting, cancel it (return null)
      // because it is now obsolete (the user has typed more characters).
      if (_nextPendingRequest != null) {
        _nextPendingRequest!.completer.complete(null);
      }
      _nextPendingRequest = _QueuedRequest(text, completer);
    } else {
      // Start processing immediately
      _isProcessing = true;
      _processRequest(text, completer);
    }

    return completer.future;
  }

  Future<void> _processRequest(String text, Completer<List<SuggestionSpan>?> completer) async {
    try {
      // Offload the heavy calculation to the isolate
      final List<dynamic> results = await _sendRequest(_HunspellCommand.check, [text]);

      // Reconstruct SuggestionSpans from the raw data returned by the isolate
      final List<SuggestionSpan> spans = results.map((item) {
        final start = item['start'] as int;
        final end = item['end'] as int;
        final suggestions = (item['suggestions'] as List<dynamic>).cast<String>();
        return SuggestionSpan(TextRange(start: start, end: end), suggestions);
      }).toList();

      // Preserve the safety check: Wait for end of frame to avoid layout thrashing
      // while the context menu is trying to build and calculate anchors.
      if (SchedulerBinding.instance.schedulerPhase != SchedulerPhase.idle) {
        await SchedulerBinding.instance.endOfFrame;
        // Add one more yield to allow any pending microtasks (like gesture cleanup) to finish
        // before we trigger the text update which invalidates layout.
        await Future.delayed(Duration.zero);
      }

      if (!completer.isCompleted) {
        completer.complete(spans);
      }
    } catch (e) {
      if (!completer.isCompleted) {
        completer.completeError(e);
      }
    } finally {
      // Check if there is a next pending request
      if (_nextPendingRequest != null) {
        final next = _nextPendingRequest!;
        _nextPendingRequest = null;
        // Process the next one
        _processRequest(next.text, next.completer);
      } else {
        // No more work
        _isProcessing = false;
      }
    }
  }

  // Persistence
  File? _personalDictionaryFile;

  /// Sets the file used for the personal dictionary.
  /// If [file] exists, its contents are loaded into the dictionary.
  /// If it doesn't exist, it will be created when the first word is added.
  Future<void> setPersonalDictionary(File file) async {
    _personalDictionaryFile = file;
    if (await file.exists()) {
      try {
        final content = await file.readAsString();
        // Split by lines and trim whitespace
        final words = content.split('\n').map((w) => w.trim()).where((w) => w.isNotEmpty);
        for (final word in words) {
          // Load each word into the runtime dictionary
          // We fire-and-forget these requests to avoid blocking init too long,
          // or we could await them if strict order matters (usually fine).
          await _sendRequest(_HunspellCommand.add, [word]);
        }
      } catch (e) {
        // print("Error loading dictionary: $e");
      }
    }
  }

  /// Adds [word] to the personal dictionary at runtime AND persists it to disk if configured.
  /// Returns `true` if successful.
  Future<bool> updatePersonalDictionary(String word) async {
    if (!_isReady) return false;

    // 1. Add to runtime memory
    final result = await _sendRequest(_HunspellCommand.add, [word]);
    final success = result as bool;

    // 2. Persist to storage if configured
    if (success && _personalDictionaryFile != null) {
      try {
        // Append word on a new line
        await _personalDictionaryFile!.writeAsString('$word\n', mode: FileMode.append);
      } catch (e) {
        // print("Error saving word: $e");
      }
    }

    return success;
  }

  void dispose() {
    _sendRequest(_HunspellCommand.dispose);
    _receivePort.close();
    _isolate?.kill();
    _isolate = null;

    // Clear pending
    if (_nextPendingRequest != null) {
      _nextPendingRequest!.completer.complete(null);
      _nextPendingRequest = null;
    }
  }
}

/// Entry point for the background isolate
void _hunspellIsolateEntry(SendPort sendPort) {
  final receivePort = ReceivePort();
  sendPort.send(receivePort.sendPort);

  final bindings = HunspellBindings(_dylib);
  Pointer<HunspellHandle>? hunspell;
  List<String> ignoredPatterns = [];

  receivePort.listen((message) {
    if (message is _HunspellRequest) {
      try {
        switch (message.command) {
          case _HunspellCommand.init:
            final affPath = message.args![0] as String;
            final dicPath = message.args![1] as String;

            final aff = affPath.toNativeUtf8();
            final dic = dicPath.toNativeUtf8();
            hunspell = bindings.FlutterHunspell_create(aff.cast(), dic.cast());
            malloc.free(aff);
            malloc.free(dic);

            sendPort.send(_HunspellResponse(message.id, true));
            break;

          case _HunspellCommand.setIgnoredPatterns:
            ignoredPatterns = (message.args as List).cast<String>();
            sendPort.send(_HunspellResponse(message.id, true));
            break;

          case _HunspellCommand.check:
            if (hunspell == null) {
              sendPort.send(_HunspellResponse(message.id, []));
              break;
            }
            final text = message.args![0] as String;
            final results = _checkText(bindings, hunspell!, text, ignoredPatterns);
            sendPort.send(_HunspellResponse(message.id, results));
            break;

          case _HunspellCommand.dispose:
            if (hunspell != null) {
              bindings.FlutterHunspell_destroy(hunspell!);
              hunspell = null;
            }
            sendPort.send(_HunspellResponse(message.id, true));
            receivePort.close();
            break;

          case _HunspellCommand.add:
            if (hunspell == null) {
              sendPort.send(_HunspellResponse(message.id, false));
              break;
            }
            final word = message.args![0] as String;
            final wordPtr = word.toNativeUtf8();
            final result = bindings.FlutterHunspell_add(hunspell!, wordPtr.cast());
            malloc.free(wordPtr);
            sendPort.send(_HunspellResponse(message.id, result == 0));
            break;
        }
      } catch (e) {
        sendPort.send(_HunspellResponse(message.id, e.toString(), error: true));
      }
    }
  });
}

/// Helper to perform the actual spell check logic (Pure Dart + FFI, no Flutter dependencies)
List<Map<String, dynamic>> _checkText(
  HunspellBindings bindings,
  Pointer<HunspellHandle> hunspell,
  String text,
  List<String> ignoredPatterns,
) {
  final List<Map<String, dynamic>> results = [];

  // 1. Identify masked ranges
  final List<TextRange> maskedRanges = [];
  for (final pattern in ignoredPatterns) {
    try {
      final regExp = RegExp(pattern);
      final matches = regExp.allMatches(text);
      for (final match in matches) {
        maskedRanges.add(TextRange(start: match.start, end: match.end));
      }
    } catch (e) {
      // Ignore invalid regex patterns to prevent crashes
    }
  }

  // Regex to find words: Unicode letters, marks, numbers, underscores, and apostrophes.
  // This effectively skips punctuation and whitespace.
  final RegExp wordRegex = RegExp(r"[\p{L}\p{M}\p{N}_']+", unicode: true);
  final matches = wordRegex.allMatches(text);

  for (final match in matches) {
    final word = match.group(0)!;
    final wordStart = match.start;
    final wordEnd = match.end;

    // 2. Optimization check: Skip if word falls inside any masked range
    bool isMasked = false;
    for (final range in maskedRanges) {
      if (wordStart < range.end && wordEnd > range.start) {
        isMasked = true;
        break;
      }
    }
    if (isMasked) continue;

    final wordPtr = word.toNativeUtf8();
    final result = bindings.FlutterHunspell_spell(hunspell, wordPtr.cast());

    if (result == 0) {
      // Misspelled
      final countPtr = malloc<Int>();
      final suggestionsPtr = bindings.FlutterHunspell_suggest(hunspell, wordPtr.cast(), countPtr);
      final count = countPtr.value;

      final List<String> suggestions = [];
      if (suggestionsPtr != nullptr) {
        for (int i = 0; i < count; i++) {
          final strPtr = suggestionsPtr[i];
          suggestions.add(strPtr.cast<Utf8>().toDartString());
        }
        bindings.FlutterHunspell_free_suggestions(hunspell, suggestionsPtr, count);
      }
      malloc.free(countPtr);

      results.add({'start': wordStart, 'end': wordEnd, 'suggestions': suggestions});
    }
    malloc.free(wordPtr);
  }
  return results;
}
