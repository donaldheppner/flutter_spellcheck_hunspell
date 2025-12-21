import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// Configuration for which mouse click triggers the context menu.
enum ShowContextMenu { leftClick, rightClick, both, none }

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
  // Track if we are waiting for a left-click up event to show the menu
  bool _pendingLeftClickShow = false;

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

    // Reset pending state on any new down event
    _pendingLeftClickShow = false;

    if (isRightClick) {
      if (widget.showContextMenu == ShowContextMenu.rightClick || widget.showContextMenu == ShowContextMenu.both) {
        _handleRightClick(event);
      }
    } else if (isLeftClick) {
      if (widget.showContextMenu == ShowContextMenu.leftClick || widget.showContextMenu == ShowContextMenu.both) {
        // We defer showing the menu until PointerUp so the cursor moves first
        _pendingLeftClickShow = true;
      }
    }
  }

  void _handlePointerUp(PointerUpEvent event) {
    if (event.pointer == 999) return;
    if (event.kind != PointerDeviceKind.mouse) return;

    if (_pendingLeftClickShow) {
      _pendingLeftClickShow = false;
      // Schedule showing the toolbar.
      // We use a small delay or microtask to allow the TextField's tap handler
      // (which also runs on up) to update the selection first.
      Future.delayed(Duration.zero, () {
        _showToolbar(checkForMisspelling: true);
      });
    }
  }

  void _handleRightClick(PointerDownEvent event) {
    // 1. Synthesize Left Click to move cursor (Native Flutter placement)
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

    // 2. Schedule the Context Menu
    Future.delayed(Duration.zero, () {
      _showToolbar(checkForMisspelling: false);
    });
  }

  void _showToolbar({bool checkForMisspelling = false}) {
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

      if (!isMisspelled) {
        return;
      }
    }

    editableTextState.showToolbar();
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
