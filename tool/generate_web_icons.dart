import 'dart:io';

import 'package:image/image.dart' as image;

/// Resize the existing app artwork for browser and PWA icon requirements.
/// Run from the repository root: dart run tool/generate_web_icons.dart
void main() {
  final original =
      image.decodePng(File('assets/icons/app_icon.png').readAsBytesSync());
  if (original == null) throw StateError('App icon is not a valid PNG');
  for (final size in [192, 512]) {
    final resized = image.copyResize(original,
        width: size, height: size, interpolation: image.Interpolation.average);
    File('web/icons/finn-$size.png').writeAsBytesSync(image.encodePng(resized));
  }
}
