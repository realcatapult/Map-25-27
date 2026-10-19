import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';

const _iosIcons = <String, int>{
  'Icon-App-20x20@1x.png': 20,
  'Icon-App-20x20@2x.png': 40,
  'Icon-App-20x20@3x.png': 60,
  'Icon-App-29x29@1x.png': 29,
  'Icon-App-29x29@2x.png': 58,
  'Icon-App-29x29@3x.png': 87,
  'Icon-App-40x40@1x.png': 40,
  'Icon-App-40x40@2x.png': 80,
  'Icon-App-40x40@3x.png': 120,
  'Icon-App-60x60@2x.png': 120,
  'Icon-App-60x60@3x.png': 180,
  'Icon-App-76x76@1x.png': 76,
  'Icon-App-76x76@2x.png': 152,
  'Icon-App-83.5x83.5@2x.png': 167,
  'Icon-App-1024x1024@1x.png': 1024,
};

const _androidIcons = <String, int>{
  'mipmap-mdpi': 48,
  'mipmap-hdpi': 72,
  'mipmap-xhdpi': 96,
  'mipmap-xxhdpi': 144,
  'mipmap-xxxhdpi': 192,
};

void main() {
  test('generate platform app icons from images/logo.png', () async {
    final logoFile = File(_path(['images', 'logo.png']));
    if (!await logoFile.exists()) {
      throw StateError('Source logo not found: ${logoFile.path}');
    }

    final codec = await ui.instantiateImageCodec(await logoFile.readAsBytes());
    final frame = await codec.getNextFrame();
    final logo = frame.image;
    try {
      for (final entry in _iosIcons.entries) {
        final file = File(
          _path([
            'ios',
            'Runner',
            'Assets.xcassets',
            'AppIcon.appiconset',
            entry.key,
          ]),
        );
        await file.writeAsBytes(await _renderIcon(logo, entry.value));
      }

      for (final entry in _androidIcons.entries) {
        final file = File(
          _path([
            'android',
            'app',
            'src',
            'main',
            'res',
            entry.key,
            'ic_launcher.png',
          ]),
        );
        await file.writeAsBytes(await _renderIcon(logo, entry.value));
      }
    } finally {
      logo.dispose();
      codec.dispose();
    }
  });
}

Future<List<int>> _renderIcon(ui.Image logo, int pixels) async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  const background = ui.Color(0xFFF6F3EC);
  canvas.drawColor(background, ui.BlendMode.src);

  final margin = pixels * 0.06;
  final destination = ui.Rect.fromLTWH(
    margin,
    margin,
    pixels - margin * 2,
    pixels - margin * 2,
  );
  final source = ui.Rect.fromLTWH(
    0,
    0,
    logo.width.toDouble(),
    logo.height.toDouble(),
  );
  canvas.drawImageRect(
    logo,
    source,
    destination,
    ui.Paint()..filterQuality = ui.FilterQuality.high,
  );

  final picture = recorder.endRecording();
  final image = await picture.toImage(pixels, pixels);
  picture.dispose();
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  if (data == null) throw StateError('Could not encode $pixels px app icon.');
  return data.buffer.asUint8List();
}

String _path(List<String> parts) => parts.join(Platform.pathSeparator);
