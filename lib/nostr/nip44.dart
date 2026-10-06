/// NIP-44 version 2, matching nostr 0.45 (the daemon).
///
/// The conversation key is HKDF-extract over the x coordinate of
/// `secret * even-Y(recipient)`. Message keys are 76 bytes of HKDF-expand.
/// The payload is version `2`, a 32-byte nonce, ChaCha20 ciphertext, and
/// HMAC-SHA256, then standard base64.
library;

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:pointycastle/export.dart';

class Nip44Exception implements Exception {
  Nip44Exception(this.message);

  final String message;

  @override
  String toString() => message;
}

const _version = 2;
const _salt = 'nip44-v2';
const _minPayload = 1 + 32 + 34 + 32;
const _maxPlaintext = 1 << 20;

String nip44ConversationKeyHex(String secretKey, String publicKey) {
  return _hex.encode(conversationKey(secretKey, publicKey));
}

String nip44Encrypt({
  required String secretKey,
  required String publicKey,
  required String plaintext,
  List<int>? nonce,
}) {
  final message = utf8.encode(plaintext);
  if (message.isEmpty) throw Nip44Exception('message empty');
  if (message.length > _maxPlaintext) throw Nip44Exception('message too long');

  final messageNonce = nonce == null
      ? _randomNonce()
      : Uint8List.fromList(nonce);
  if (messageNonce.length != 32) {
    throw Nip44Exception('nonce must be 32 bytes');
  }

  final keys = _messageKeys(
    conversationKey(secretKey, publicKey),
    messageNonce,
  );
  final padded = _pad(message);
  final cipher = ChaCha7539Engine()
    ..init(
      true,
      ParametersWithIV(
        KeyParameter(Uint8List.sublistView(keys, 0, 32)),
        Uint8List.sublistView(keys, 32, 44),
      ),
    );
  cipher.processBytes(padded, 0, padded.length, padded, 0);

  final mac = _hmac(
    Uint8List.sublistView(keys, 44, 76),
    Uint8List.fromList([...messageNonce, ...padded]),
  );

  return base64.encode([_version, ...messageNonce, ...padded, ...mac]);
}

String nip44Decrypt({
  required String secretKey,
  required String publicKey,
  required String payload,
}) {
  final Uint8List bytes;
  try {
    bytes = base64.decode(payload);
  } catch (_) {
    throw Nip44Exception('payload is not base64');
  }
  if (bytes.length < _minPayload) {
    throw Nip44Exception('payload size is too short');
  }
  if (bytes[0] != _version) {
    throw Nip44Exception('unknown version: ${bytes[0]}');
  }

  return _openPayload(conversationKey(secretKey, publicKey), bytes);
}

/// [conversationKeyHex] is 32 bytes of hex, the value a dispute sends the solver.
String nip44DecryptWithConversationKey({
  required String conversationKeyHex,
  required String payload,
}) {
  final Uint8List bytes;
  try {
    bytes = base64.decode(payload);
  } catch (_) {
    throw Nip44Exception('payload is not base64');
  }
  return _openPayload(_hex.decode(_hexKey(conversationKeyHex)), bytes);
}

String _openPayload(Uint8List conversation, Uint8List bytes) {
  if (bytes.length < _minPayload) {
    throw Nip44Exception('payload size is too short');
  }
  if (bytes[0] != _version) {
    throw Nip44Exception('unknown version: ${bytes[0]}');
  }

  final nonce = Uint8List.sublistView(bytes, 1, 33);
  final ciphertext = Uint8List.sublistView(bytes, 33, bytes.length - 32);
  final mac = Uint8List.sublistView(bytes, bytes.length - 32);
  final keys = _messageKeys(conversation, nonce);
  final calculated = _hmac(
    Uint8List.sublistView(keys, 44, 76),
    Uint8List.fromList([...nonce, ...ciphertext]),
  );
  if (!_macEqual(mac, calculated)) throw Nip44Exception('invalid HMAC');

  final plain = Uint8List.fromList(ciphertext);
  final cipher = ChaCha7539Engine()
    ..init(
      false,
      ParametersWithIV(
        KeyParameter(Uint8List.sublistView(keys, 0, 32)),
        Uint8List.sublistView(keys, 32, 44),
      ),
    );
  cipher.processBytes(plain, 0, plain.length, plain, 0);

  final body = _unpad(plain);
  if (body.length > _maxPlaintext) throw Nip44Exception('message too long');
  try {
    return utf8.decode(body);
  } catch (_) {
    throw Nip44Exception('plaintext is not text');
  }
}

Uint8List conversationKey(String secretKey, String publicKey) {
  final shared = _sharedX(secretKey, publicKey);
  return _hmac(utf8.encode(_salt), shared);
}

Uint8List _messageKeys(Uint8List conversation, Uint8List nonce) {
  final out = Uint8List(76);
  var written = 0;
  Uint8List previous = Uint8List(0);
  var counter = 1;
  while (written < out.length) {
    final mac = HMac(SHA256Digest(), 64)..init(KeyParameter(conversation));
    if (written > 0) mac.update(previous, 0, previous.length);
    mac.update(nonce, 0, nonce.length);
    final block = Uint8List(1)..[0] = counter;
    mac.update(block, 0, 1);
    final hash = Uint8List(32);
    mac.doFinal(hash, 0);
    final take = min(out.length - written, hash.length);
    out.setRange(written, written + take, hash);
    previous = hash;
    written += take;
    counter += 1;
  }
  return out;
}

Uint8List _pad(List<int> plaintext) {
  final paddedLen = nip44PaddedLength(plaintext.length);
  final prefix = plaintext.length < 65536
      ? _be16(plaintext.length)
      : <int>[0, 0, ..._be32(plaintext.length)];
  final padded = Uint8List(prefix.length + paddedLen);
  padded.setRange(0, prefix.length, prefix);
  padded.setRange(prefix.length, prefix.length + plaintext.length, plaintext);
  return padded;
}

Uint8List _unpad(Uint8List decrypted) {
  if (decrypted.length < 2) throw Nip44Exception('invalid padding');
  final legacy = (decrypted[0] << 8) | decrypted[1];
  final int prefixLen;
  final int length;
  if (legacy != 0) {
    prefixLen = 2;
    length = legacy;
  } else {
    if (decrypted.length < 6) throw Nip44Exception('invalid padding');
    prefixLen = 6;
    length =
        (decrypted[2] << 24) |
        (decrypted[3] << 16) |
        (decrypted[4] << 8) |
        decrypted[5];
    if (length < 65536) throw Nip44Exception('invalid padding');
  }
  if (length == 0) throw Nip44Exception('message empty');
  final end = prefixLen + length;
  if (end > decrypted.length) throw Nip44Exception('invalid padding');
  if (decrypted.length != prefixLen + nip44PaddedLength(length)) {
    throw Nip44Exception('invalid padding');
  }
  return Uint8List.sublistView(decrypted, prefixLen, end);
}

int nip44PaddedLength(int length) {
  if (length <= 32) return 32;
  final nextPower = 1 << (_log2Floor(length - 1) + 1);
  final chunk = nextPower <= 256 ? 32 : nextPower ~/ 8;
  return chunk * (((length - 1) ~/ chunk) + 1);
}

int _log2Floor(int value) {
  if (value == 0) return 0;
  return value.bitLength - 1;
}

Uint8List _sharedX(String secretKey, String publicKey) {
  final scalarHex = _hexKey(secretKey);
  final pointHex = _hexKey(publicKey);
  final params = ECCurve_secp256k1();
  final x = BigInt.parse(pointHex, radix: 16);
  final point = params.curve.createPoint(x, _liftX(x));
  final shared = point * BigInt.parse(scalarHex, radix: 16);
  final sharedX = shared?.x?.toBigInteger();
  if (sharedX == null) throw Nip44Exception('could not derive a shared secret');
  return _hex.decode(sharedX.toRadixString(16).padLeft(64, '0'));
}

/// Even Y for [x], the same lift the daemon uses before ECDH.
BigInt _liftX(BigInt x) {
  final p = BigInt.parse(
    'fffffffffffffffffffffffffffffffffffffffffffffffffffffffefffffc2f',
    radix: 16,
  );
  if (x >= p) throw Nip44Exception('public key is not on the curve');
  final ySq = (x.modPow(BigInt.from(3), p) + BigInt.from(7)) % p;
  final y = ySq.modPow((p + BigInt.one) ~/ BigInt.from(4), p);
  if (y.modPow(BigInt.two, p) != ySq) {
    throw Nip44Exception('public key is not on the curve');
  }
  return y.isEven ? y : p - y;
}

Uint8List _hmac(List<int> key, List<int> message) {
  final mac = HMac(SHA256Digest(), 64)
    ..init(KeyParameter(Uint8List.fromList(key)));
  mac.update(Uint8List.fromList(message), 0, message.length);
  final out = Uint8List(32);
  mac.doFinal(out, 0);
  return out;
}

bool _macEqual(Uint8List left, Uint8List right) {
  if (left.length != right.length) return false;
  var diff = 0;
  for (var i = 0; i < left.length; i++) {
    diff |= left[i] ^ right[i];
  }
  return diff == 0;
}

Uint8List _randomNonce() {
  final random = Random.secure();
  return Uint8List.fromList(List.generate(32, (_) => random.nextInt(256)));
}

List<int> _be16(int value) => [(value >> 8) & 0xff, value & 0xff];

List<int> _be32(int value) => [
  (value >> 24) & 0xff,
  (value >> 16) & 0xff,
  (value >> 8) & 0xff,
  value & 0xff,
];

String _hexKey(String value) {
  final hex = value.trim().toLowerCase();
  if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(hex)) {
    throw Nip44Exception('key must be 32 bytes of hex');
  }
  return hex;
}

const _hex = _Hex();

class _Hex {
  const _Hex();

  Uint8List decode(String hex) {
    final out = Uint8List(hex.length ~/ 2);
    for (var i = 0; i < out.length; i++) {
      out[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
    }
    return out;
  }

  String encode(List<int> bytes) {
    final buffer = StringBuffer();
    for (final byte in bytes) {
      buffer.write(byte.toRadixString(16).padLeft(2, '0'));
    }
    return buffer.toString();
  }
}
