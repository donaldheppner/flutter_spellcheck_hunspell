import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_spellcheck_hunspell/src/hunspell_configuration.dart';
import 'package:flutter_spellcheck_hunspell/hunspell_spell_check_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('HunspellConfiguration', () {
    test('build returns valid SpellCheckConfiguration', () {
      final service = HunspellSpellCheckService();
      final config = HunspellConfiguration.build(service: service);

      expect(config.spellCheckService, equals(service));
      expect(config.misspelledTextStyle, isNotNull);
      expect(config.spellCheckSuggestionsToolbarBuilder, isNotNull);
    });
  });
}
