import 'dart:io';
import 'dart:ui';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter_spellcheck_hunspell/hunspell_spell_check_service.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('HunspellSpellCheckService initializes and checks spelling', (WidgetTester tester) async {
    final service = HunspellSpellCheckService();

    // Setup: Copy assets to a temporary location for the test
    final docsDir = await getApplicationSupportDirectory();
    final affDetail = await rootBundle.load('assets/en_US.aff');
    final dicDetail = await rootBundle.load('assets/en_US.dic');

    final affPath = '${docsDir.path}/test_en_US.aff';
    final dicPath = '${docsDir.path}/test_en_US.dic';

    await File(affPath).writeAsBytes(affDetail.buffer.asUint8List());
    await File(dicPath).writeAsBytes(dicDetail.buffer.asUint8List());

    // Test: Initialize
    await service.init(affPath, dicPath);

    // Test: Check "speling" (incorrect)
    // The service might add start/end of sentence markers or similar,
    // but we expect "speling" to be flagged.
    final suggestions = await service.fetchSpellCheckSuggestions(const Locale('en', 'US'), 'This is a speling error');

    expect(suggestions, isNotNull);
    // Find the span for "speling"
    // "This is a " is 10 chars. "speling" is 7.
    // We expect a span starting around index 10.
    final errorSpan = suggestions!.firstWhere((s) => s.suggestions.contains('spelling'));

    expect(errorSpan.suggestions, contains('spelling'));

    // Test: Check "spelling" (correct)
    final correctSuggestions = await service.fetchSpellCheckSuggestions(
      const Locale('en', 'US'),
      'This is correct spelling',
    );

    // Should be no suggestions for "spelling"
    // Note: The service returns a list of spans for misspelled words.
    // Ideally this list is empty or contains spans for other words if they were wrong.
    // "spelling" shouldn't be in the list of spans.
    final hasSpellingError = correctSuggestions!.any(
      (s) => s.range.start == 16, // "This is correct " length 16
    );
    expect(hasSpellingError, isFalse);

    service.dispose();
  });
}
