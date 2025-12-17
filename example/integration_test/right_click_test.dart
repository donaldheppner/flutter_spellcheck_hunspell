import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:flutter_spellcheck_hunspell_example/main.dart' as app;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Right-click moves cursor in multi-line text', (WidgetTester tester) async {
    app.main();
    await tester.pumpAndSettle();

    final textFieldFinder = find.byType(TextField);
    expect(textFieldFinder, findsOneWidget);

    // Enter multi-line text
    await tester.enterText(textFieldFinder, 'Line 1 word\nLine 2 target\nLine 3 word');
    await tester.pumpAndSettle();

    // Find the word 'target' in line 2
    // We need to tap slightly offset to ensure we hit the specific word
    // Layout:
    // Line 1 word
    // Line 2 target
    // Line 3 word

    // We'll calculate the center of the TextField and then offset based on expected font size,
    // or we can use custom logic. Ideally we just click in the middle area which should be line 2.
    final textFieldCenter = tester.getCenter(textFieldFinder);

    // Perform a right click at the center (Line 2)
    final gesture = await tester.startGesture(
      textFieldCenter,
      kind: PointerDeviceKind.mouse,
      buttons: kSecondaryMouseButton,
    );
    await gesture.up();
    await tester.pumpAndSettle();

    // Verify Cursor Position
    // The cursor should now be at the location we clicked.
    // "Line 1 word\n" is 12 chars.
    // "Line 2 target" starts at 12. "target" ends at 25.
    // If we clicked center, we *expect* to be somewhere in Line 2.
    // We can check the selection property of the TextField's controller.

    final TextField textField = tester.widget(textFieldFinder);
    final selection = textField.controller!.selection;

    // Verify that the selection is valid and likely within the second line range
    expect(selection.baseOffset, greaterThan(12), reason: 'Cursor should be after Line 1');
    expect(selection.baseOffset, lessThan(30), reason: 'Cursor should be inside Line 2');

    // Verify Context Menu is OPEN
    // Flutter context menus are usually implemented as OverlayEntries.
    // We can check for a widget that looks like a menu item.
    // The example app adds "Add to Dictionary".
    expect(find.text('Add to Dictionary'), findsOneWidget);
  });
}
