import 'dart:io';
import 'package:http/http.dart' as http;

Future<void> main() async {
  final assetsDir = Directory('example/assets');
  if (!await assetsDir.exists()) {
    await assetsDir.create(recursive: true);
  }

  final files = {
    'en_US.aff': 'https://cgit.freedesktop.org/libreoffice/dictionaries/plain/en/en_US.aff',
    'en_US.dic': 'https://cgit.freedesktop.org/libreoffice/dictionaries/plain/en/en_US.dic',
  };

  for (final entry in files.entries) {
    final filename = entry.key;
    final url = entry.value;
    final file = File('${assetsDir.path}/$filename');

    if (await file.exists()) {
      print('$filename already exists, skipping.');
      continue;
    }

    print('Downloading $filename from $url...');
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

  print('Dictionary download complete. Make sure to update example/pubspec.yaml assets if not already there.');
}
