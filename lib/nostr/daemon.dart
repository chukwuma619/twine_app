/// A daemon somebody else is running. The app stores its public key and relays.
library;

import 'package:dart_nostr/dart_nostr.dart';

/// A daemon somebody else is running. The app only stores its public key and relays.
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

  static TwineDaemon? tryParse(
    Nostr nostr, {
    required String pubkey,
    required String relays,
  }) {
    final parsedKey = parsePublicKey(nostr, pubkey);
    final parsedRelays = parseRelays(relays);
    if (parsedKey == null || parsedRelays == null) return null;
    return TwineDaemon(
      publicKey: parsedKey,
      npub: nostr.bech32.encodePublicKeyToNpub(parsedKey),
      relays: parsedRelays,
    );
  }

  /// An `npub` or a 64-character hex public key. An `nsec` is rejected.
  static String? parsePublicKey(Nostr nostr, String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;
    final lower = trimmed.toLowerCase();
    if (lower.startsWith('nsec1')) return null;

    if (lower.startsWith('npub1')) {
      try {
        final decoded = nostr.bech32.decodeBech32(lower);
        if (decoded.length < 2 || decoded[1] != 'npub') return null;
        final hex = decoded[0].toLowerCase();
        if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(hex)) return null;
        return hex;
      } catch (_) {
        return null;
      }
    }

    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(lower)) return null;
    return lower;
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
