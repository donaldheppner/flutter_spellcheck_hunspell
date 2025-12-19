import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// A widget that handles the platform-specific gesture logic for spell checking
/// on desktop, specifically mapping Right-Click to "Move Cursor" + "Open Menu".
class HunspellGestureDetector extends StatelessWidget {
  /// The [TextField] or [EditableText] widget to wrap.
  final Widget child;

  /// The [GlobalKey] attached to the [TextField].
  /// Required to locate the [EditableTextState] for programmatically showing the toolbar.
  final GlobalKey fieldKey;

  const HunspellGestureDetector({super.key, required this.child, required this.fieldKey});

  @override
  Widget build(BuildContext context) {
    return Listener(onPointerDown: (event) => _handlePointerDown(event), child: child);
  }

  void _handlePointerDown(PointerDownEvent event) {
    if (event.kind == PointerDeviceKind.mouse && event.buttons == kSecondaryMouseButton) {
      // 1. Synthesize Left Click to move cursor (Native Flutter placement)
      // Use a distinct pointer ID (999) to avoid conflict with the real mouse
      final down = PointerDownEvent(
        pointer: 999,
        position: event.position,
        kind: PointerDeviceKind.mouse,
        buttons: kPrimaryButton,
      );
      final up = PointerUpEvent(
        pointer: 999,
        position: event.position,
        kind: PointerDeviceKind.mouse,
        buttons: kPrimaryButton,
      );
      GestureBinding.instance.handlePointerEvent(down);
      GestureBinding.instance.handlePointerEvent(up);

      // 2. Schedule the Context Menu to open after the cursor has moved
      // and the selection is updated.
      // Use Future.microtask to account for the event loop processing.
      // (Note: Using microtask based on user preference, but delayed(zero) is robust too.
      // Keeping consistent with latest working state in main.dart).
      //
      // WAIT: In main.dart step 1046, user reverted to microtask.
      // I should stick to what was approved in main.dart: Microtask.
      Future.microtask(() {
        final editableTextState = _findEditableTextState(fieldKey);
        editableTextState?.showToolbar();
      });
    }
  }

  EditableTextState? _findEditableTextState(GlobalKey key) {
    EditableTextState? state;
    void visitor(Element element) {
      if (element.widget is EditableText) {
        state = (element as StatefulElement).state as EditableTextState;
        return;
      }
      element.visitChildren(visitor);
    }

    key.currentContext?.visitChildElements(visitor);
    return state;
  }
}
