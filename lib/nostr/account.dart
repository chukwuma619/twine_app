import 'package:dart_nostr/dart_nostr.dart';

/// The Nostr key that signs actions. The daemon treats [publicKey] as the account.
class TwineAccount {
  const TwineAccount({
    required this.privateKey,
    required this.publicKey,
    required this.npub,
    required this.nsec,
  });

  /// 32-byte secret, hex-encoded.
  final String privateKey;

  /// Hex public key. This is the sender the daemon records.
  final String publicKey;

  final String npub;
  final String nsec;

  static TwineAccount generate(Nostr nostr) {
    for (var attempt = 0; attempt < 8; attempt++) {
      final pair = nostr.keys.generateKeyPair();
      if (_validScalar(pair.private)) return _fromPair(nostr, pair);
    }
    throw StateError('could not generate a nostr key');
  }

  /// Accepts an `nsec` or a 64-character hex secret. Returns null when it is not a key.
  static TwineAccount? tryParse(Nostr nostr, String secret) {
    final trimmed = secret.trim().toLowerCase();
    if (trimmed.isEmpty) return null;

    final String hex;
    if (trimmed.startsWith('nsec1')) {
      try {
        final decoded = nostr.bech32.decodeBech32(trimmed);
        if (decoded.length < 2 || decoded[1] != 'nsec') return null;
        hex = decoded[0].toLowerCase();
      } catch (_) {
        return null;
      }
    } else {
      hex = trimmed;
    }

    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(hex)) return null;
    if (!_validScalar(hex)) return null;
    if (!nostr.keys.isValidPrivateKey(hex)) return null;

    final pair = nostr.keys.generateKeyPairFromExistingPrivateKey(hex);
    return _fromPair(nostr, pair);
  }

  /// secp256k1 scalars the daemon will accept: 1 through curve order − 1.
  static bool _validScalar(String hex) {
    const order =
        'fffffffffffffffffffffffffffffffebaaedce6af48a03bbfd25e8cd0364141';
    final scalar = BigInt.parse(hex, radix: 16);
    final curveOrder = BigInt.parse(order, radix: 16);
    return scalar > BigInt.zero && scalar < curveOrder;
  }

  static TwineAccount _fromPair(Nostr nostr, NostrKeyPairs pair) {
    return TwineAccount(
      privateKey: pair.private,
      publicKey: pair.public,
      npub: nostr.bech32.encodePublicKeyToNpub(pair.public),
      nsec: nostr.bech32.encodePrivateKeyToNsec(pair.private),
    );
  }
}
