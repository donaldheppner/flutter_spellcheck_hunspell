import 'package:flutter/material.dart';
import 'package:flutter_spellcheck_hunspell/hunspell_spell_check_service.dart';

/// Helper to create a robust [SpellCheckConfiguration] for Hunspell.
class HunspellConfiguration {
  /// Creates a configuration with the standard red-wavy underline and a Robust
  /// toolbar builder that handles "Stale Offsets" (Dynamic Range Calculation)
  /// and "Reopening Loops" (Explicit Hide).
  static SpellCheckConfiguration build({required HunspellSpellCheckService service, TextStyle? misspelledTextStyle}) {
    return SpellCheckConfiguration(
      spellCheckService: service,
      misspelledTextStyle:
          misspelledTextStyle ??
          const TextStyle(
            color: Colors.red,
            decoration: TextDecoration.underline,
            decorationColor: Colors.red,
            decorationStyle: TextDecorationStyle.wavy,
          ),
      spellCheckSuggestionsToolbarBuilder: (BuildContext context, EditableTextState editableTextState) {
        return _buildRobustToolbar(context, editableTextState);
      },
    );
  }

  /// Builds a [contextMenuBuilder] that injects spell check suggestions and
  /// an "Add to Dictionary" button into the standard context menu.
  static Widget Function(BuildContext, EditableTextState) buildContextMenu({VoidCallback? onAddToDictionary}) {
    return (BuildContext context, EditableTextState editableTextState) {
      // distinct implementation for desktop right-click
      final suggestionSpan = editableTextState.findSuggestionSpanAtCursorIndex(
        editableTextState.currentTextEditingValue.selection.baseOffset,
      );

      final List<ContextMenuButtonItem> buttonItems = editableTextState.contextMenuButtonItems;

      if (suggestionSpan != null) {
        buttonItems.insert(
          0,
          ContextMenuButtonItem(
            label: 'Add to Dictionary',
            onPressed: () {
              // Make sure to hide toolbar here too
              editableTextState.hideToolbar();
              onAddToDictionary?.call();
            },
            type: ContextMenuButtonType.custom,
          ),
        );

        for (final suggestion in suggestionSpan.suggestions.reversed) {
          buttonItems.insert(
            0,
            ContextMenuButtonItem(
              label: suggestion,
              onPressed: () {
                editableTextState.hideToolbar();

                // Dynamic Range Calculation (Fixing Stale Offsets)
                final currentOffset = editableTextState.currentTextEditingValue.selection.baseOffset;
                final validRange = editableTextState.renderEditable.getWordBoundary(
                  TextPosition(offset: currentOffset),
                );

                final newText = editableTextState.currentTextEditingValue.text.replaceRange(
                  validRange.start,
                  validRange.end,
                  suggestion,
                );
                editableTextState.userUpdateTextEditingValue(
                  TextEditingValue(
                    text: newText,
                    selection: TextSelection.collapsed(offset: validRange.start + suggestion.length),
                  ),
                  SelectionChangedCause.toolbar,
                );
              },
            ),
          );
        }
      }

      return AdaptiveTextSelectionToolbar.buttonItems(
        anchors: editableTextState.contextMenuAnchors,
        buttonItems: buttonItems,
      );
    };
  }

  static Widget _buildRobustToolbar(BuildContext context, EditableTextState editableTextState) {
    final suggestionSpan = editableTextState.findSuggestionSpanAtCursorIndex(
      editableTextState.currentTextEditingValue.selection.baseOffset,
    );

    if (suggestionSpan == null) {
      return const SizedBox.shrink();
    }

    return AdaptiveTextSelectionToolbar.buttonItems(
      anchors: editableTextState.contextMenuAnchors,
      buttonItems: suggestionSpan.suggestions.map((suggestion) {
        return ContextMenuButtonItem(
          onPressed: () {
            // explicit hide to prevent reopening
            editableTextState.hideToolbar();

            // Dynamic Range Calculation (Fix "Stale Offsets")
            final currentOffset = editableTextState.currentTextEditingValue.selection.baseOffset;
            // Note: getWordBoundary needs TextPosition!
            final validRange = editableTextState.renderEditable.getWordBoundary(TextPosition(offset: currentOffset));

            final newText = editableTextState.currentTextEditingValue.text.replaceRange(
              validRange.start,
              validRange.end,
              suggestion,
            );
            editableTextState.userUpdateTextEditingValue(
              TextEditingValue(
                text: newText,
                selection: TextSelection.collapsed(offset: validRange.start + suggestion.length),
              ),
              SelectionChangedCause.toolbar,
            );
          },
          label: suggestion,
        );
      }).toList(),
    );
  }
}
