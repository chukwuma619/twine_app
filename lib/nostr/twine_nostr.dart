import 'package:dart_nostr/dart_nostr.dart';

import 'account.dart';
import 'relays.dart';

class TwineRelayException implements Exception {
  TwineRelayException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Nostr client for the app. Connects to [twineRelays].
class TwineNostr {
  TwineNostr({Nostr? nostr})
    : nostr =
          nostr ??
          Nostr(
            clientOptions: const NostrClientOptions(
              connectionTimeout: Duration(seconds: 15),
            ),
          ) {
    this.nostr.disableLogs();
    current = this;
  }

  static TwineNostr? current;

  final Nostr nostr;

  /// Key that signs actions. Null until the user creates or imports one.
  TwineAccount? account;

  /// Opens [relays] and returns the ones whose sockets connected.
  /// Throws [TwineRelayException] when none do.
  Future<List<String>> connect({List<String> relays = twineRelays}) async {
    final result = await nostr.connect(relays);
    if (result.isFailure) {
      throw TwineRelayException(result.failureOrNull!.message);
    }

    final open = nostr.relays.relaysWebSocketsRegistry.keys.toList()..sort();
    if (open.isEmpty) {
      throw TwineRelayException('no nostr relay connected');
    }
    return open;
  }
}
