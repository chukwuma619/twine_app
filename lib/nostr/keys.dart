import 'dart:math';

import 'package:pointycastle/export.dart';

/// Bech32 npub/nsec and x-only secp256k1 keys. Signing stays in Rust.
class TwineKeys {
  static const _order =
      'fffffffffffffffffffffffffffffffebaaedce6af48a03bbfd25e8cd0364141';
  static const _charset = 'qpzry9x8gf2tvdw0s3jn54khce6mua7l';

  static ({String privateKey, String publicKey, String npub, String nsec})
  generate() {
    for (var attempt = 0; attempt < 8; attempt++) {
      final secret = _randomSecret();
      if (!_validScalar(secret)) continue;
      return fromSecretHex(secret);
    }
    throw StateError('could not generate a nostr key');
  }

  static ({String privateKey, String publicKey, String npub, String nsec})?
  tryParse(String secret) {
    final trimmed = secret.trim().toLowerCase();
    if (trimmed.isEmpty) return null;
    final String hex;
    if (trimmed.startsWith('nsec1')) {
      hex = decodeBech32(trimmed, 'nsec') ?? '';
    } else {
      hex = trimmed;
    }
    if (!_validScalar(hex)) return null;
    return fromSecretHex(hex);
  }

  static ({String privateKey, String publicKey, String npub, String nsec})
  fromSecretHex(String hex) {
    final publicKey = publicFromSecret(hex);
    return (
      privateKey: hex,
      publicKey: publicKey,
      npub: encodeBech32('npub', publicKey),
      nsec: encodeBech32('nsec', hex),
    );
  }

  /// An `npub` or a 64-character hex public key. An `nsec` is rejected.
  static String? parsePublicKey(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;
    final lower = trimmed.toLowerCase();
    if (lower.startsWith('nsec1')) return null;
    if (lower.startsWith('npub1')) {
      return decodeBech32(lower, 'npub');
    }
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(lower)) return null;
    return lower;
  }

  static String encodeNpub(String hex) {
    final key = parsePublicKey(hex);
    if (key == null) throw FormatException('invalid public key');
    return encodeBech32('npub', key);
  }

  static String publicFromSecret(String hex) {
    final params = ECCurve_secp256k1();
    final point = params.G * BigInt.parse(hex, radix: 16);
    final x = point?.x?.toBigInteger();
    if (x == null) throw StateError('could not derive a public key');
    return x.toRadixString(16).padLeft(64, '0');
  }

  static bool _validScalar(String hex) {
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(hex)) return false;
    final scalar = BigInt.parse(hex, radix: 16);
    final curveOrder = BigInt.parse(_order, radix: 16);
    return scalar > BigInt.zero && scalar < curveOrder;
  }

  static String _randomSecret() {
    final random = Random.secure();
    final bytes = List<int>.generate(32, (_) => random.nextInt(256));
    return [
      for (final byte in bytes) byte.toRadixString(16).padLeft(2, '0'),
    ].join();
  }

  static String? decodeBech32(String value, String hrp) {
    try {
      final lower = value.toLowerCase();
      final sep = lower.lastIndexOf('1');
      if (sep < 1) return null;
      if (lower.substring(0, sep) != hrp) return null;
      final data = lower.substring(sep + 1);
      if (data.length < 6) return null;
      final values = <int>[];
      for (final rune in data.split('')) {
        final index = _charset.indexOf(rune);
        if (index < 0) return null;
        values.add(index);
      }
      if (!_verify(hrp, values)) return null;
      final bytes = _convertBits(values.sublist(0, values.length - 6), 5, 8, false);
      if (bytes == null || bytes.length != 32) return null;
      return [
        for (final byte in bytes) byte.toRadixString(16).padLeft(2, '0'),
      ].join();
    } catch (_) {
      return null;
    }
  }

  static String encodeBech32(String hrp, String hex) {
    final bytes = <int>[
      for (var i = 0; i < hex.length; i += 2)
        int.parse(hex.substring(i, i + 2), radix: 16),
    ];
    final data = _convertBits(bytes, 8, 5, true)!;
    final checksum = _createChecksum(hrp, data);
    final combined = [...data, ...checksum];
    return '$hrp' '1${[for (final value in combined) _charset[value]].join()}';
  }

  static List<int>? _convertBits(
    List<int> data,
    int from,
    int to,
    bool pad,
  ) {
    var acc = 0;
    var bits = 0;
    final maxv = (1 << to) - 1;
    final out = <int>[];
    for (final value in data) {
      if (value < 0 || value >> from != 0) return null;
      acc = (acc << from) | value;
      bits += from;
      while (bits >= to) {
        bits -= to;
        out.add((acc >> bits) & maxv);
      }
    }
    if (pad) {
      if (bits > 0) out.add((acc << (to - bits)) & maxv);
    } else if (bits >= from || ((acc << (to - bits)) & maxv) != 0) {
      if (bits >= from) return null;
      if (((acc << (to - bits)) & maxv) != 0) return null;
    }
    return out;
  }

  static List<int> _hrpExpand(String hrp) {
    return [
      for (final unit in hrp.codeUnits) unit >> 5,
      0,
      for (final unit in hrp.codeUnits) unit & 31,
    ];
  }

  static int _polymod(List<int> values) {
    const gen = [0x3b6a57b2, 0x26508e6d, 0x1ea119fa, 0x3d4233dd, 0x2a1462b3];
    var chk = 1;
    for (final value in values) {
      final b = chk >> 25;
      chk = ((chk & 0x1ffffff) << 5) ^ value;
      for (var i = 0; i < 5; i++) {
        if (((b >> i) & 1) == 1) chk ^= gen[i];
      }
    }
    return chk;
  }

  static List<int> _createChecksum(String hrp, List<int> data) {
    final values = [..._hrpExpand(hrp), ...data, 0, 0, 0, 0, 0, 0];
    final mod = _polymod(values) ^ 1;
    return [for (var i = 0; i < 6; i++) (mod >> (5 * (5 - i))) & 31];
  }

  static bool _verify(String hrp, List<int> data) {
    return _polymod([..._hrpExpand(hrp), ...data]) == 1;
  }
}
