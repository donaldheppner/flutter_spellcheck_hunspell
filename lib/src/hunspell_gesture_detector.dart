import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// Configuration for which mouse click triggers the context menu.
enum ShowContextMenu { rightClick, both, none }

/// A widget that handles the platform-specific gesture logic for spell checking
/// on desktop, specifically mapping clicks to "Move Cursor" + "Open Menu".
class HunspellGestureDetector extends StatefulWidget {
  /// The [TextField] or [EditableText] widget to wrap.
  final Widget child;

  /// The [GlobalKey] attached to the [TextField].
  /// Required to locate the [EditableTextState] for programmatically showing the toolbar.
  final GlobalKey fieldKey;

  /// Determines which mouse click triggers the context menu.
  final ShowContextMenu showContextMenu;

  const HunspellGestureDetector({
    super.key,
    required this.child,
    required this.fieldKey,
    this.showContextMenu = ShowContextMenu.rightClick,
  });

  @override
  State<HunspellGestureDetector> createState() => _HunspellGestureDetectorState();
}

class _HunspellGestureDetectorState extends State<HunspellGestureDetector> {
  @override
  Widget build(BuildContext context) {
    return Listener(onPointerDown: _handlePointerDown, onPointerUp: _handlePointerUp, child: widget.child);
  }

  void _handlePointerDown(PointerDownEvent event) {
    // Ignore our own synthesized events
    if (event.pointer == 999) return;
    if (event.kind != PointerDeviceKind.mouse) return;

    final isRightClick = event.buttons == kSecondaryMouseButton;
    final isLeftClick = event.buttons == kPrimaryButton;

    if (isRightClick) {
      if (widget.showContextMenu == ShowContextMenu.rightClick || widget.showContextMenu == ShowContextMenu.both) {
        _handleRightClick(event);
      }
    } else if (isLeftClick) {
      if (widget.showContextMenu == ShowContextMenu.both) {
        _handleLeftClick(event);
      }
    }
  }

  void _handlePointerUp(PointerUpEvent event) {
    if (event.pointer == 999) return;
    if (event.kind != PointerDeviceKind.mouse) return;
  }

  void _handleLeftClick(PointerDownEvent event) {
    // We defer to allow cursor movement (handled by Flutter natively for left click)
    Future.delayed(Duration.zero, () {
      _showToolbar(checkForMisspelling: true, eventPosition: event.position);
    });
  }

  void _handleRightClick(PointerDownEvent event) {
    // 1. Synthesize Left Click to move cursor (Native Flutter placement)
    _synthesizeTap(event.position, kPrimaryButton);

    // 2. Schedule the Context Menu
    Future.delayed(Duration.zero, () {
      _showToolbar(checkForMisspelling: false);
    });
  }

  void _showToolbar({bool checkForMisspelling = false, Offset? eventPosition}) {
    final editableTextState = _findEditableTextState(widget.fieldKey);
    if (editableTextState == null) return;

    if (checkForMisspelling) {
      final spellResults = editableTextState.spellCheckResults;
      if (spellResults == null) return;

      final selection = editableTextState.textEditingValue.selection;
      if (!selection.isValid || !selection.isCollapsed) return;

      bool isMisspelled = false;
      for (final span in spellResults.suggestionSpans) {
        // loose check: if cursor is touching the range
        // (inclusive of start/end to allow clicking 'around' the word easily)
        if (selection.baseOffset >= span.range.start && selection.baseOffset <= span.range.end) {
          isMisspelled = true;
          break;
        }
      }

      if (isMisspelled && eventPosition != null) {
        // Synthesize a Right Click (Secondary Tap) at the current location.
        // This forces the TextField to update its "last secondary tap position"
        // and show the menu at the correct spot.
        _synthesizeTap(eventPosition, kSecondaryButton);
      }
      // If not misspelled, do nothing.
      return;
    }

    // Fallback for direct invocation (Right Click behavior)
    editableTextState.showToolbar();
  }

  void _synthesizeTap(Offset position, int button) {
    final down = PointerDownEvent(pointer: 999, position: position, kind: PointerDeviceKind.mouse, buttons: button);
    final up = PointerUpEvent(pointer: 999, position: position, kind: PointerDeviceKind.mouse, buttons: button);
    GestureBinding.instance.handlePointerEvent(down);
    GestureBinding.instance.handlePointerEvent(up);
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
