import 'dart:typed_data';

import 'package:image/image.dart' as img;

import 'chat.dart';

/// Shrinks a receipt until it fits in one chat event.
/// A picture that already fits is returned unchanged.
/// Returns null when the bytes are not an image, or when shrinking still
/// leaves it over [maxReceiptBytes].
Uint8List? compressReceipt(Uint8List bytes) {
  if (bytes.isEmpty) return null;
  if (bytes.length <= maxReceiptBytes) {
    return img.decodeImage(bytes) == null ? null : bytes;
  }
  final decoded = img.decodeImage(bytes);
  if (decoded == null) return null;

  const steps = <(int, int)>[
    (1280, 55),
    (1280, 40),
    (1280, 28),
    (960, 40),
    (960, 28),
    (720, 35),
    (720, 22),
    (480, 30),
    (480, 18),
    (320, 20),
    (240, 15),
  ];
  int? fitted;
  img.Image current = decoded;
  for (final (edge, quality) in steps) {
    if (fitted != edge) {
      current = _fit(decoded, edge);
      fitted = edge;
    }
    final encoded = img.encodeJpg(current, quality: quality);
    if (encoded.length <= maxReceiptBytes) return encoded;
  }
  return null;
}

img.Image _fit(img.Image source, int edge) {
  final longest = source.width > source.height ? source.width : source.height;
  if (longest <= edge) return source;
  if (source.width >= source.height) {
    return img.copyResize(
      source,
      width: edge,
      interpolation: img.Interpolation.average,
    );
  }
  return img.copyResize(
    source,
    height: edge,
    interpolation: img.Interpolation.average,
  );
}
