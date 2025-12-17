import 'dart:io';
import 'dart:ui';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_spellcheck_hunspell/hunspell_spell_check_service.dart';
import 'package:path_provider/path_provider.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  final HunspellSpellCheckService _spellCheckService = HunspellSpellCheckService();
  final GlobalKey _textFieldKey = GlobalKey();
  final TextEditingController _controller = TextEditingController();
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _initHunspell();
  }

  Future<void> _initHunspell() async {
    // Copy assets to extensive storage because Hunspell needs file paths
    final docsDir = await getApplicationSupportDirectory();
    final affDetail = await rootBundle.load('assets/en_US.aff');
    final dicDetail = await rootBundle.load('assets/en_US.dic');

    final affPath = '${docsDir.path}/en_US.aff';
    final dicPath = '${docsDir.path}/en_US.dic';

    await File(affPath).writeAsBytes(affDetail.buffer.asUint8List());
    await File(dicPath).writeAsBytes(dicDetail.buffer.asUint8List());

    await _spellCheckService.init(affPath, dicPath);

    if (mounted) {
      setState(() {
        _ready = true;
      });
    }
  }

  @override
  void dispose() {
    _spellCheckService.dispose();
    _controller.dispose();
    super.dispose();
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

  Widget _buildSpellCheckToolbar(BuildContext context, EditableTextState editableTextState) {
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
            // Explicitly hide toolbar to prevent reopening loops
            editableTextState.hideToolbar();
            final newText = editableTextState.currentTextEditingValue.text.replaceRange(
              suggestionSpan.range.start,
              suggestionSpan.range.end,
              suggestion,
            );
            editableTextState.userUpdateTextEditingValue(
              TextEditingValue(
                text: newText,
                selection: TextSelection.collapsed(offset: suggestionSpan.range.start + suggestion.length),
              ),
              SelectionChangedCause.toolbar,
            );
          },
          label: suggestion,
        );
      }).toList(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        appBar: AppBar(title: const Text('Hunspell Spell Check')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: _ready
                ? Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text('Type something (try "speling"):'),
                      SizedBox(height: 20),
                      Listener(
                        onPointerDown: (event) {
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
                            Future.microtask(() {
                              final editableTextState = _findEditableTextState(_textFieldKey);
                              editableTextState?.showToolbar();
                            });
                          }
                        },
                        child: TextField(
                          key: _textFieldKey,
                          controller: _controller,
                          maxLines: null,
                          style: const TextStyle(fontSize: 18.0, height: 1.5, color: Colors.black),
                          spellCheckConfiguration: SpellCheckConfiguration(
                            spellCheckService: _spellCheckService,
                            misspelledTextStyle: const TextStyle(
                              color: Colors.red, // Highlight misspelled words in red
                              decoration: TextDecoration.underline,
                              decorationColor: Colors.red,
                              decorationStyle: TextDecorationStyle.wavy,
                            ),
                            spellCheckSuggestionsToolbarBuilder:
                                (BuildContext context, EditableTextState editableTextState) {
                                  return _buildSpellCheckToolbar(context, editableTextState);
                                },
                          ),
                          contextMenuBuilder: (BuildContext context, EditableTextState editableTextState) {
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
                                    // TODO: Implement Learn
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
                                      final newText = editableTextState.currentTextEditingValue.text.replaceRange(
                                        suggestionSpan.range.start,
                                        suggestionSpan.range.end,
                                        suggestion,
                                      );
                                      editableTextState.userUpdateTextEditingValue(
                                        TextEditingValue(
                                          text: newText,
                                          selection: TextSelection.collapsed(
                                            offset: suggestionSpan.range.start + suggestion.length,
                                          ),
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
                          },
                        ),
                      ),
                    ],
                  )
                : const CircularProgressIndicator(),
          ),
        ),
      ),
    );
  }
}
