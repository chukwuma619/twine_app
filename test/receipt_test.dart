import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:twine_app/market/chat.dart';
import 'package:twine_app/market/receipt.dart';

void main() {
  test('a picture that already fits is kept', () {
    final tiny = img.encodeJpg(img.Image(width: 2, height: 2), quality: 40);
    expect(tiny.length, lessThanOrEqualTo(maxReceiptBytes));
    expect(compressReceipt(tiny), tiny);
  });

  test('bytes that are not an image are refused', () {
    expect(compressReceipt(Uint8List.fromList([1, 2, 3, 4])), isNull);
    expect(compressReceipt(Uint8List(0)), isNull);
  });

  test('a large photo is compressed under the chat limit', () {
    final picture = img.Image(width: 900, height: 700);
    for (var y = 0; y < picture.height; y++) {
      for (var x = 0; x < picture.width; x++) {
        picture.setPixelRgb(
          x,
          y,
          (x * 17 + y * 3) & 255,
          (x * 13 + y * 11) & 255,
          (x * 29 + y * 7) & 255,
        );
      }
    }
    final original = img.encodeJpg(picture, quality: 95);
    expect(original.length, greaterThan(maxReceiptBytes));

    final compressed = compressReceipt(original);
    expect(compressed, isNotNull);
    expect(compressed!.length, lessThanOrEqualTo(maxReceiptBytes));
    expect(compressed.length, lessThan(original.length));
    expect(img.decodeJpg(compressed), isNotNull);
  });
}
