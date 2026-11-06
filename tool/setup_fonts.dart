// Fetches the bundled Myanmar Unicode fonts into `fonts/` so the app renders
// Myanmar text offline. Run once after checkout (or to refresh the fonts):
//
//   dart run tool/setup_fonts.dart
//
// Sources:
//  * Pyidaungsu        – https://github.com/AungMyoKyaw/Myanmar-Unicode-Fonts
//  * Noto Sans Myanmar – https://github.com/google/fonts (variable font)
import 'dart:io';

const _targets = <(String, String)>[
  (
    'https://raw.githubusercontent.com/AungMyoKyaw/Myanmar-Unicode-Fonts/master/Pyidaungsu/pyidaungsu.ttf',
    'fonts/Pyidaungsu-Regular.ttf',
  ),
  (
    'https://raw.githubusercontent.com/google/fonts/main/ofl/notosansmyanmar/NotoSansMyanmar%5Bwdth%2Cwght%5D.ttf',
    'fonts/NotoSansMyanmar-Regular.ttf',
  ),
];

Future<void> main() async {
  final fontsDir = Directory('fonts');
  if (!fontsDir.existsSync()) fontsDir.createSync(recursive: true);

  final client = HttpClient();
  for (final (url, path) in _targets) {
    stdout.writeln('Downloading $url');
    final request = await client.getUrl(Uri.parse(url));
    final response = await request.close();
    if (response.statusCode != 200) {
      stderr.writeln('  ✗ HTTP ${response.statusCode}');
      continue;
    }
    final file = File(path);
    final sink = file.openWrite();
    await for (final chunk in response) {
      sink.add(chunk);
    }
    await sink.flush();
    await sink.close();
    final size = await file.length();
    stdout.writeln('  ✓ $path (${size ~/ 1024} KB)');
  }
  client.close();
}
