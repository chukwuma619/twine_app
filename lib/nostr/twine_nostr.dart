import 'package:dart_nostr/dart_nostr.dart';

import 'account.dart';
import 'daemon.dart';

class TwineRelayException implements Exception {
  TwineRelayException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Nostr client for the app. Relays come from the daemon the user picked.
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

  /// Daemon this install is pointed at. Null until the user chooses one.
  TwineDaemon? daemon;

  /// Opens [relays] and returns the ones whose sockets connected.
  /// Throws [TwineRelayException] when none do.
  Future<List<String>> connect(List<String> relays) async {
    await nostr.disconnect();
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
