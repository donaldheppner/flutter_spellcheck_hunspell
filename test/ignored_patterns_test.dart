import 'dart:io';
import 'dart:ui';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_spellcheck_hunspell/hunspell_spell_check_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late HunspellSpellCheckService service;
  late String affPath;
  late String dicPath;
  late Directory tempDir;

  setUpAll(() async {
    // Setup temporary dictionary files for testing
    tempDir = await Directory.systemTemp.createTemp('hunspell_test_');
    affPath = '${tempDir.path}/test.aff';
    dicPath = '${tempDir.path}/test.dic';

    // Simple dictionary: "hello", "flutter", "world"
    await File(affPath).writeAsString("SET UTF-8\n");
    await File(dicPath).writeAsString("3\nhello\nflutter\nworld\n");
  });

  setUp(() async {
    service = HunspellSpellCheckService();
    await service.init(affPath, dicPath);
  });

  tearDown(() {
    service.dispose();
  });

  test('Default configuration ignores URIs', () async {
    const text = "Checking http://example.com/badword and https://flutter.dev";
    final suggestions = await service.fetchSpellCheckSuggestions(const Locale('en'), text);

    // "badword" is inside the URL, so it should be ignored.
    // "Checking" is misspelled (not in our tiny dict).
    // "and" is misspelled (not in dict).
    // The URLs themselves should not trigger errors for their components.

    // Actually, our dict is tiny: hello, flutter, world.

    // "Checking" -> Misspelled
    // "http://example.com/badword" -> Ignored (no spelling errors reported for parts)
    // "and" -> Misspelled
    // "https://flutter.dev" -> Ignored

    // Let's look at the result spans.
    final misspelledWords = suggestions?.map((s) => text.substring(s.range.start, s.range.end)).toList();

    // "Checking" and "and" should be flagged.
    // Parts of the URL like "http", "example", "com", "badword" should NOT be flagged if ignored.
    expect(misspelledWords, contains('Checking'));
    expect(misspelledWords, contains('and'));

    expect(misspelledWords, isNot(contains('http')));
    expect(misspelledWords, isNot(contains('example')));
    expect(misspelledWords, isNot(contains('badword')));
    expect(misspelledWords, isNot(contains('flutter'))); // "flutter" is in dict anyway
    expect(misspelledWords, isNot(contains('dev')));
  });

  test('Custom ignored patterns work', () async {
    // Ignore words starting with #
    service.ignoredPatterns = [r'#\w+'];

    const text = "hello #unknown world #badword";
    // "hello", "world" are correct.
    // "#unknown", "#badword" should be ignored.
    // If not ignored, "unknown" and "badword" would be flagged (since they aren't in dict).

    // Wait a bit for sync (though setter sends message, it's async)
    // The service handles sync automatically but it is async.
    // In our implementation check() waits for response, and commands are processed in order in the isolate.
    // So sending setIgnoredPatterns then check should work sequentially.

    final suggestions = await service.fetchSpellCheckSuggestions(const Locale('en'), text);
    final misspelledWords = suggestions?.map((s) => text.substring(s.range.start, s.range.end)).toList();

    expect(misspelledWords, isEmpty);
  });

  test('Punctuation handling within ignored patterns', () async {
    // pattern with punctuation
    service.ignoredPatterns = [r'\w+\.\w+']; // e.g. "file.ext"

    const text = "open file.ext now";
    // "open", "now" -> misspelled (not in dict)
    // "file.ext" -> ignored

    final suggestions = await service.fetchSpellCheckSuggestions(const Locale('en'), text);
    final misspelledWords = suggestions?.map((s) => text.substring(s.range.start, s.range.end)).toList();

    expect(misspelledWords, contains('open'));
    expect(misspelledWords, contains('now'));
    expect(misspelledWords, isNot(contains('file')));
    expect(misspelledWords, isNot(contains('ext')));
  });

  test('Overlapping ignored ranges', () async {
    // If we have two patterns, and they overlap or are adjacent
    service.ignoredPatterns = [r'foo', r'bar'];

    // "foo" match 0-3
    // "bar" match 3-6
    // "foobar" as a word is 0-6.
    // Overlap with foo? Yes (0<3 && 6>0).
    // So "foobar" should be ignored (skipped).

    // What if we have "foo bar"?
    // "foo" (word 0-3) matches ignored "foo" (0-3). Skipped.
    // "bar" (word 4-7) matches ignored "bar" (4-7). Skipped.

    // Ideally we want to verify that partial overlaps also exclude the word.
    // E.g. ignore "boo".
    // Text "book". Word "book" (0-4). pattern "boo" (0-3).
    // Overlap: 0<3 && 4>0 -> True.
    // So "book" is skipped.

    service.ignoredPatterns = [r'boo'];
    const title = "book";
    final suggestions = await service.fetchSpellCheckSuggestions(const Locale('en'), title);
    expect(suggestions, isEmpty); // "book" skipped, so no misspelled "book" reported.
  });
}
