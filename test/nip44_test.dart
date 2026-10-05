import 'dart:typed_data';

import 'package:dart_nostr/dart_nostr.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twine_app/nostr/account.dart';
import 'package:twine_app/nostr/nip44.dart';

void main() {
  final nostr = Nostr();

  test('conversation keys match the NIP-44 vectors', () {
    const cases = [
      (
        'fffffffffffffffffffffffffffffffebaaedce6af48a03bbfd25e8cd0364139',
        '0000000000000000000000000000000000000000000000000000000000000002',
        '8b6392dbf2ec6a2b2d5b1477fc2be84d63ef254b667cadd31bd3f444c44ae6ba',
      ),
      (
        '0000000000000000000000000000000000000000000000000000000000000002',
        '1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdeb',
        'be234f46f60a250bef52a5ee34c758800c4ca8e5030bf4cc1a31d37ba2104d43',
      ),
      (
        '0000000000000000000000000000000000000000000000000000000000000001',
        '79be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798',
        '3b4610cb7189beb9cc29eb3716ecc6102f1247e8f3101a03a1787d8908aeb54e',
      ),
    ];

    for (final (secret, publicKey, expected) in cases) {
      expect(nip44ConversationKeyHex(secret, publicKey), expected);
    }
  });

  test('padded lengths match the NIP-44 vectors', () {
    const cases = [
      (16, 32),
      (32, 32),
      (33, 64),
      (37, 64),
      (45, 64),
      (49, 64),
      (64, 64),
      (65, 96),
      (100, 128),
      (111, 128),
      (200, 224),
      (250, 256),
      (320, 320),
      (383, 384),
      (384, 384),
      (400, 448),
      (500, 512),
      (512, 512),
      (515, 640),
      (700, 768),
      (800, 896),
      (900, 1024),
      (1020, 1024),
      (65536, 65536),
    ];

    for (final (length, padded) in cases) {
      expect(nip44PaddedLength(length), padded);
    }
  });

  test('encrypt and decrypt match the NIP-44 vectors', () {
    const cases = [
      (
        '0000000000000000000000000000000000000000000000000000000000000001',
        '0000000000000000000000000000000000000000000000000000000000000002',
        '0000000000000000000000000000000000000000000000000000000000000001',
        'a',
        'AgAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAABee0G5VSK0/9YypIObAtDKfYEAjD35uVkHyB0F4DwrcNaCXlCWZKaArsGrY6M9wnuTMxWfp1RTN9Xga8no+kF5Vsb',
      ),
      (
        '0000000000000000000000000000000000000000000000000000000000000002',
        '0000000000000000000000000000000000000000000000000000000000000001',
        'f00000000000000000000000000000f00000000000000000000000000000000f',
        '🍕🫃',
        'AvAAAAAAAAAAAAAAAAAAAPAAAAAAAAAAAAAAAAAAAAAPSKSK6is9ngkX2+cSq85Th16oRTISAOfhStnixqZziKMDvB0QQzgFZdjLTPicCJaV8nDITO+QfaQ61+KbWQIOO2Yj',
      ),
      (
        '5c0c523f52a5b6fad39ed2403092df8cebc36318b39383bca6c00808626fab3a',
        '4b22aa260e4acb7021e32f38a6cdf4b673c6a277755bfce287e370c924dc936d',
        'b635236c42db20f021bb8d1cdff5ca75dd1a0cc72ea742ad750f33010b24f73b',
        '表ポあA鷗ŒéＢ逍Üßªąñ丂㐀𠀀',
        'ArY1I2xC2yDwIbuNHN/1ynXdGgzHLqdCrXUPMwELJPc7s7JqlCMJBAIIjfkpHReBPXeoMCyuClwgbT419jUWU1PwaNl4FEQYKCDKVJz+97Mp3K+Q2YGa77B6gpxB/lr1QgoqpDf7wDVrDmOqGoiPjWDqy8KzLueKDcm9BVP8xeTJIxs=',
      ),
    ];

    for (final (sec1, sec2, nonceHex, plaintext, ciphertext) in cases) {
      final sender = TwineAccount.tryParse(nostr, sec1)!;
      final recipient = TwineAccount.tryParse(nostr, sec2)!;
      final nonce = _unhex(nonceHex);

      expect(
        nip44Encrypt(
          secretKey: sender.privateKey,
          publicKey: recipient.publicKey,
          plaintext: plaintext,
          nonce: nonce,
        ),
        ciphertext,
      );
      expect(
        nip44Decrypt(
          secretKey: recipient.privateKey,
          publicKey: sender.publicKey,
          payload: ciphertext,
        ),
        plaintext,
      );
    }
  });

  test('a message encrypts back to itself', () {
    final sender = TwineAccount.generate(nostr);
    final recipient = TwineAccount.generate(nostr);
    const plaintext = '{"action":"new-order","payload":{"side":"sell"}}';

    final ciphertext = nip44Encrypt(
      secretKey: sender.privateKey,
      publicKey: recipient.publicKey,
      plaintext: plaintext,
    );

    expect(
      nip44Decrypt(
        secretKey: recipient.privateKey,
        publicKey: sender.publicKey,
        payload: ciphertext,
      ),
      plaintext,
    );
  });

  test('an empty message and a bad mac are rejected', () {
    final sender = TwineAccount.generate(nostr);
    final recipient = TwineAccount.generate(nostr);

    expect(
      () => nip44Encrypt(
        secretKey: sender.privateKey,
        publicKey: recipient.publicKey,
        plaintext: '',
      ),
      throwsA(isA<Nip44Exception>()),
    );

    final ciphertext = nip44Encrypt(
      secretKey: sender.privateKey,
      publicKey: recipient.publicKey,
      plaintext: 'a',
    );
    final flipped = ciphertext.startsWith('A')
        ? 'B${ciphertext.substring(1)}'
        : 'A${ciphertext.substring(1)}';
    expect(
      () => nip44Decrypt(
        secretKey: recipient.privateKey,
        publicKey: sender.publicKey,
        payload: flipped,
      ),
      throwsA(isA<Nip44Exception>()),
    );
  });
}

Uint8List _unhex(String hex) {
  final out = Uint8List(hex.length ~/ 2);
  for (var i = 0; i < out.length; i++) {
    out[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
  }
  return out;
}
