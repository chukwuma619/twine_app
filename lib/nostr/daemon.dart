import 'keys.dart';

/// The daemon a new install offers. A person can replace it before connecting.
const officialDaemonNpub =
    'npub1avxxz0xj3pgxugrr9s9e56xsfhw0f3slgrusw3960s4ak8ys0lsqhs05j6';

const officialDaemonRelays = ['wss://relay.backr.site'];

/// Doorbell host. Override with `--dart-define=TWINE_PUSH_URL=`.
const officialPushUrl = String.fromEnvironment(
  'TWINE_PUSH_URL',
  defaultValue: 'https://push.backr.site',
);

/// The app only stores this daemon's public key and relays.
class TwineDaemon {
  const TwineDaemon({
    required this.publicKey,
    required this.npub,
    required this.relays,
  });

  /// Hex public key. Actions are encrypted to this key.
  final String publicKey;

  final String npub;

  /// Websocket URLs from that daemon's `TWINE_RELAYS` list.
  final List<String> relays;

  static TwineDaemon? tryParse({
    required String pubkey,
    required String relays,
  }) {
    final parsedKey = parsePublicKey(pubkey);
    final parsedRelays = parseRelays(relays);
    if (parsedKey == null || parsedRelays == null) return null;
    return TwineDaemon(
      publicKey: parsedKey,
      npub: TwineKeys.encodeNpub(parsedKey),
      relays: parsedRelays,
    );
  }

  /// An `npub` or a 64-character hex public key. An `nsec` is rejected.
  static String? parsePublicKey(String raw) {
    return TwineKeys.parsePublicKey(raw);
  }

  /// Comma, space, or newline separated `ws://` and `wss://` URLs.
  static List<String>? parseRelays(String raw) {
    final relays = <String>[];
    for (final piece in raw.split(RegExp(r'[\s,]+'))) {
      if (piece.isEmpty) continue;
      final relay = _normalizeRelay(piece);
      if (relay == null) return null;
      if (!relays.contains(relay)) relays.add(relay);
    }
    if (relays.isEmpty) return null;
    return relays;
  }

  static String? _normalizeRelay(String raw) {
    final uri = Uri.tryParse(raw.trim());
    if (uri == null || uri.host.isEmpty) return null;
    final scheme = uri.scheme.toLowerCase();
    if (scheme != 'ws' && scheme != 'wss') return null;
    final port = uri.hasPort ? ':${uri.port}' : '';
    final path = uri.path == '/' ? '' : uri.path;
    return '$scheme://${uri.host.toLowerCase()}$port$path';
  }
}
