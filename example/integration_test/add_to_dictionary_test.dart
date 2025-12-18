import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:flutter_spellcheck_hunspell_example/main.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Right-click "Add to Dictionary" removes squiggle', (WidgetTester tester) async {
    // 1. Launch App
    await tester.pumpWidget(const MyApp());
    await tester.pumpAndSettle();

    // 2. Find TextField
    final textFieldFinder = find.byType(TextField).first;
    expect(textFieldFinder, findsOneWidget);

    // 3. Enter misspelled text
    await tester.enterText(textFieldFinder, 'helo world');
    await tester.pumpAndSettle();

    // Wait for spell check (debounce/throttle/async)
    await tester.pump(const Duration(seconds: 2));

    // 4. Right Click "helo"
    // "helo" is at the start. We can tap near the top-left of the text field.
    final topLeft = tester.getTopLeft(textFieldFinder) + const Offset(10, 10);

    final gesture = await tester.startGesture(topLeft, kind: PointerDeviceKind.mouse, buttons: kSecondaryMouseButton);
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    // 5. Verify Context Menu appears with "Add to Dictionary"
    final addToDictFinder = find.text('Add to Dictionary');
    expect(addToDictFinder, findsOneWidget);

    // 6. Tap "Add to Dictionary"
    await tester.tap(addToDictFinder);
    await tester.pumpAndSettle();

    // Verify menu is gone
    expect(find.text('Add to Dictionary'), findsNothing);

    // Allow time for the async add operation and the re-check
    await tester.pump(const Duration(seconds: 2));

    // 8. Verify the red squiggle is GONE
    final editableFinder = find.byType(EditableText);
    final renderEditable = tester.renderObject<RenderEditable>(editableFinder);

    // Helper to traverse spans and check for red wavy underline
    bool hasRedSquiggle(InlineSpan? span) {
      if (span == null) return false;
      if (span is TextSpan) {
        if (span.style?.decoration == TextDecoration.underline &&
            span.style?.decorationStyle == TextDecorationStyle.wavy &&
            span.style?.decorationColor == Colors.red) {
          return true;
        }
        if (span.children != null) {
          return span.children!.any(hasRedSquiggle);
        }
      }
      return false;
    }

    final hasSquiggle = hasRedSquiggle(renderEditable.text);
    expect(hasSquiggle, isFalse, reason: "Red squiggle should be removed after adding word to dictionary");
  });
}
