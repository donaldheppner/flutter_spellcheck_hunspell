// ignore_for_file: avoid_print

import 'dart:io';
import 'package:http/http.dart' as http;

Future<void> main() async {
  final assetsDir = Directory('example/assets');
  if (!assetsDir.existsSync()) {
    assetsDir.createSync(recursive: true);
  }

  final files = {
    'en_US.aff': 'https://raw.githubusercontent.com/LibreOffice/dictionaries/master/en/en_US.aff',
    'en_US.dic': 'https://raw.githubusercontent.com/LibreOffice/dictionaries/master/en/en_US.dic',
  };

  for (final entry in files.entries) {
    final filename = entry.key;
    final url = entry.value;
    final file = File('example/assets/$filename');

    if (file.existsSync()) {
      print('$filename already exists, skipping.');
      continue;
    }

    print('Downloading $filename...');
    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        await file.writeAsBytes(response.bodyBytes);
        print('Downloaded $filename.');
      } else {
        print('Failed to download $filename: ${response.statusCode}');
      }
    } catch (e) {
      print('Error downloading $filename: $e');
    }
  }
}
