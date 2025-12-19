import 'dart:io';
import 'dart:ui';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:flutter_spellcheck_hunspell/hunspell_spell_check_service.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('HunspellSpellCheckService API', () {
    late HunspellSpellCheckService service;
    late String affPath;
    late String dicPath;

    setUp(() async {
      service = HunspellSpellCheckService();
      // Use system temp directory directly, avoiding channel calls
      final docsDir = Directory.systemTemp.createTempSync('hunspell_test');

      // Load assets directly from file system (since we are in root, assets are in example/assets)
      final affFile = File('example/assets/en_US.aff');
      final dicFile = File('example/assets/en_US.dic');

      affPath = '${docsDir.path}/test_api_en_US.aff';
      dicPath = '${docsDir.path}/test_api_en_US.dic';

      await File(affPath).writeAsBytes(await affFile.readAsBytes());
      await File(dicPath).writeAsBytes(await dicFile.readAsBytes());
    });

    tearDown(() {
      service.dispose();
      try {
        File(affPath).deleteSync();
        File(dicPath).deleteSync();
      } catch (_) {}
    });

    testWidgets('init and simple spell check', (WidgetTester tester) async {
      await service.init(affPath, dicPath);

      // Check known correct word
      final correct = await service.fetchSpellCheckSuggestions(const Locale('en', 'US'), 'hello');
      // service returns list of spans for ERRORS. Should be empty or null for correct.
      // Actually fetchSpellCheckSuggestions returns List<SuggestionSpan>?
      // If no errors, it might return empty list or not contain 'hello'.

      // Let's check a sentence with NO errors
      final emptyResult = await service.fetchSpellCheckSuggestions(const Locale('en', 'US'), 'hello world');
      // Depending on implementation, might be empty list
      expect(emptyResult, isEmpty);

      // Check known incorrect word
      final incorrect = await service.fetchSpellCheckSuggestions(const Locale('en', 'US'), 'helo world');
      expect(incorrect, isNotEmpty);
      expect(incorrect!.first.suggestions, contains('hello'));
    });

    testWidgets('personal dictionary operations', (WidgetTester tester) async {
      await service.init(affPath, dicPath);

      const word = 'zzzz';
      // Verify it is initially wrong
      var result = await service.fetchSpellCheckSuggestions(const Locale('en', 'US'), word);
      expect(result, isNotEmpty); // flagged as error

      // Add to dictionary
      final success = await service.updatePersonalDictionary(word);
      expect(success, isTrue);

      // Verify it is now correct
      // Wait a tiny bit for async propagation if needed, though updatePersonalDictionary awaits the isolate response
      result = await service.fetchSpellCheckSuggestions(const Locale('en', 'US'), word);
      // Should be empty (no errors)
      expect(result, isEmpty);
    });
  });
}
