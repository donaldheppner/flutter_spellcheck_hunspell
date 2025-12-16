import 'dart:io';
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
    super.dispose();
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
                      TextField(
                        maxLines: null,
                        spellCheckConfiguration: SpellCheckConfiguration(
                          spellCheckService: _spellCheckService,
                          misspelledTextStyle: const TextStyle(
                            color: Colors.red, // Highlight misspelled words in red
                            decoration: TextDecoration.underline,
                            decorationColor: Colors.red,
                            decorationStyle: TextDecorationStyle.wavy,
                          ),
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
