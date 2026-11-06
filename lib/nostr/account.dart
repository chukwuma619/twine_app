import 'keys.dart';

/// The daemon treats [publicKey] as the account.
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

  static TwineAccount generate() {
    final keys = TwineKeys.generate();
    return TwineAccount(
      privateKey: keys.privateKey,
      publicKey: keys.publicKey,
      npub: keys.npub,
      nsec: keys.nsec,
    );
  }

  /// Accepts an `nsec` or a 64-character hex secret. Returns null when it is not a key.
  static TwineAccount? tryParse(String secret) {
    final keys = TwineKeys.tryParse(secret);
    if (keys == null) return null;
    return TwineAccount(
      privateKey: keys.privateKey,
      publicKey: keys.publicKey,
      npub: keys.npub,
      nsec: keys.nsec,
    );
  }
}
