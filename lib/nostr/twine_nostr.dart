import 'dart:async';

import 'package:dart_nostr/dart_nostr.dart';

import 'account.dart';
import 'channel.dart';
import 'daemon.dart';
import 'fiber_node.dart';

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

  final _replies = StreamController<TwineEnvelope>.broadcast();
  StreamSubscription<NostrEvent>? _replySub;
  NostrEventsStream? _replyStream;
  final _fiberNodes = StreamController<String>.broadcast();
  StreamSubscription<NostrEvent>? _fiberSub;
  NostrEventsStream? _fiberStream;

  /// Replies from [daemon], decrypted and checked against that daemon's key.
  Stream<TwineEnvelope> get replies => _replies.stream;

  /// Fiber node pubkeys announced by [daemon].
  Stream<String> get fiberNodes => _fiberNodes.stream;

  /// Encrypts [envelope] to the chosen daemon and signs it with [account].
  NostrEvent seal(TwineEnvelope envelope) {
    final signer = account;
    final target = daemon;
    if (signer == null || target == null) {
      throw StateError('sign in and choose a daemon first');
    }
    return sealAction(
      sender: signer,
      recipientPublicKey: target.publicKey,
      envelope: envelope,
    );
  }

  /// Decrypts [event] when it was signed by the chosen daemon and addressed here.
  TwineEnvelope? open(NostrEvent event) {
    final signer = account;
    final target = daemon;
    if (signer == null || target == null) return null;
    return openReply(
      recipient: signer,
      senderPublicKey: target.publicKey,
      event: event,
    );
  }

  /// Publishes [envelope] to the connected relays.
  Future<void> send(TwineEnvelope envelope) async {
    final result = await nostr.publish(seal(envelope));
    if (result.isFailure) {
      throw TwineRelayException(result.failureOrNull!.message);
    }
  }

  /// Subscribes to kind-4242 events tagged to this account and authored by the daemon.
  void watchReplies() {
    stopWatching();
    final signer = account;
    final target = daemon;
    if (signer == null || target == null) {
      throw StateError('sign in and choose a daemon first');
    }
    final result = nostr.subscribe(
      NostrFilter(
        kinds: const [kindAction],
        authors: [target.publicKey],
        p: [signer.publicKey],
      ),
    );
    if (result.isFailure) {
      throw TwineRelayException(result.failureOrNull!.message);
    }
    final events = result.valueOrNull!;
    _replyStream = events;
    _replySub = events.stream.listen((event) {
      final envelope = openReply(
        recipient: signer,
        senderPublicKey: target.publicKey,
        event: event,
      );
      if (envelope != null && !_replies.isClosed) _replies.add(envelope);
    }, onError: (_) {});
  }

  /// Subscribes to this daemon's Fiber node announcement.
  void watchFiberNode() {
    _stopFiber();
    final target = daemon;
    if (target == null) {
      throw StateError('choose a daemon first');
    }
    final result = nostr.subscribe(
      NostrFilter(
        kinds: const [kindFiberNode],
        authors: [target.publicKey],
        additionalFilters: const {
          '#d': [fiberNodeTag],
        },
      ),
    );
    if (result.isFailure) {
      throw TwineRelayException(result.failureOrNull!.message);
    }
    final events = result.valueOrNull!;
    _fiberStream = events;
    _fiberSub = events.stream.listen((event) {
      final pubkey = openFiberNode(
        daemonPublicKey: target.publicKey,
        event: event,
      );
      if (pubkey != null && !_fiberNodes.isClosed) _fiberNodes.add(pubkey);
    }, onError: (_) {});
  }

  void stopWatching() {
    _replySub?.cancel();
    _replySub = null;
    _replyStream?.close();
    _replyStream = null;
    _stopFiber();
  }

  void _stopFiber() {
    _fiberSub?.cancel();
    _fiberSub = null;
    _fiberStream?.close();
    _fiberStream = null;
  }

  /// Opens [relays] and returns the ones whose sockets connected.
  /// Throws [TwineRelayException] when none do.
  Future<List<String>> connect(List<String> relays) async {
    stopWatching();
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
