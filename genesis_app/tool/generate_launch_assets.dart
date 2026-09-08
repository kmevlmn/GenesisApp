import 'dart:io';

import 'package:image/image.dart' as img;

/// Run from genesis_app: dart run tool/generate_launch_assets.dart
/// Native launch resources cannot import Flutter's color tokens directly.
void main() {
  final tokens = File('lib/ui/tokens/genesis_colors.dart').readAsStringSync();
  final match = RegExp(
    r'darkBackground\s*=\s*Color\(0xFF([0-9A-Fa-f]{6})\)',
  ).firstMatch(tokens);
  if (match == null) throw StateError('darkBackground token was not found');
  final hex = match.group(1)!;
  final rgb = [
    for (var i = 0; i < 6; i += 2)
      int.parse(hex.substring(i, i + 2), radix: 16),
  ];
  final source = img
      .decodePng(File('assets/images/app_icon.png').readAsBytesSync())!
      .convert(numChannels: 4);
  final rounded = img.copyCrop(
    source,
    x: 0,
    y: 0,
    width: source.width,
    height: source.height,
    radius: source.width * 12 / 96,
  );
  img.Image icon(int size) => img.copyResize(
    rounded,
    width: size,
    height: size,
    interpolation: img.Interpolation.average,
  );
  void png(String path, img.Image image) {
    File(path).writeAsBytesSync(img.encodePng(image));
  }

  const iosAssets = 'ios/Runner/Assets.xcassets/LaunchImage.imageset';
  for (final scale in [1, 2, 3]) {
    final suffix = scale == 1 ? '' : '@${scale}x';
    png('$iosAssets/LaunchImage$suffix.png', icon(96 * scale));
  }
  const androidDrawables = 'android/app/src/main/res/drawable-nodpi';
  png('$androidDrawables/genesis_launch_logo.png', icon(288));
  // Android 12's 288dp splash canvas contains a centered 96dp icon.
  // Padding also keeps the complete icon inside the system's circular mask.
  final android12 = img.Image(width: 864, height: 864, numChannels: 4);
  img.compositeImage(android12, icon(288), center: true);
  png('$androidDrawables/genesis_launch_logo_android12.png', android12);

  File(
    'android/app/src/main/res/values/genesis_startup_colors.xml',
  ).writeAsStringSync('''<?xml version="1.0" encoding="utf-8"?>
<!-- Generated from GenesisColors.darkBackground. Run tool/generate_launch_assets.dart. -->
<resources>
    <color name="genesis_dark_background">#$hex</color>
</resources>
''');
  final background =
      '<color key="backgroundColor" '
      'red="${rgb[0] / 255}" green="${rgb[1] / 255}" '
      'blue="${rgb[2] / 255}" alpha="1" '
      'colorSpace="custom" customColorSpace="sRGB"/>';
  for (final name in ['LaunchScreen', 'Main']) {
    final file = File('ios/Runner/Base.lproj/$name.storyboard');
    final xml = file.readAsStringSync();
    file.writeAsStringSync(
      xml.replaceAll(
        RegExp(r'<color key="backgroundColor"[^>]*/>'),
        background,
      ),
    );
  }
  stdout.writeln('Generated dark launch assets from app_icon.png and #$hex.');
}
