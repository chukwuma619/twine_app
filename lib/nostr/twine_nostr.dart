/// Relay client. Relays come from the daemon the user picked.
library;

import 'dart:async';

import 'package:dart_nostr/dart_nostr.dart';

import '../constant.dart';
import 'account.dart';
import 'action.dart';
import 'daemon.dart';
import 'envelope.dart';
import 'catalog.dart';
import 'fiber_node.dart';
import 'order.dart';
import 'reply.dart';

class TwineRelayException implements Exception {
  TwineRelayException(this.message);

  final String message;

  @override
  String toString() => message;
}

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

  final _replies = StreamController<DaemonReplyEvent>.broadcast();
  StreamSubscription<NostrEvent>? _replySub;
  NostrEventsStream? _replyStream;
  final _orders = StreamController<TwineOrder>.broadcast();
  StreamSubscription<NostrEvent>? _orderSub;
  NostrEventsStream? _orderStream;
  NostrEventsStream? _orderReplay;
  final _fiberNodes = StreamController<String>.broadcast();
  StreamSubscription<NostrEvent>? _fiberSub;
  NostrEventsStream? _fiberStream;
  final _catalogs = StreamController<OpenedCatalog>.broadcast();
  StreamSubscription<NostrEvent>? _catalogSub;
  NostrEventsStream? _catalogStream;
  Timer? _relayWatch;
  String _openSockets = '';

  /// Replies from [daemon], decrypted and checked against that daemon's key.
  Stream<DaemonReplyEvent> get replies => _replies.stream;

  /// Public orders [daemon] has published.
  Stream<TwineOrder> get orders => _orders.stream;

  /// Fiber node pubkeys announced by [daemon].
  Stream<String> get fiberNodes => _fiberNodes.stream;

  /// Payment catalogs announced by [daemon].
  Stream<OpenedCatalog> get catalogs => _catalogs.stream;

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
    _replySub?.cancel();
    _replySub = null;
    _replyStream?.close();
    _replyStream = null;
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
      final createdAt = event.createdAt;
      if (envelope != null && createdAt != null && !_replies.isClosed) {
        _replies.add(
          DaemonReplyEvent(envelope: envelope, createdAt: createdAt),
        );
      }
    }, onError: (_) {});
  }

  /// Subscribes to public orders this daemon has published.
  void watchOrders() {
    _stopOrders();
    final target = daemon;
    if (target == null) {
      throw StateError('choose a daemon first');
    }
    final result = nostr.subscribe(
      NostrFilter(kinds: const [kindOrder], authors: [target.publicKey]),
    );
    if (result.isFailure) {
      throw TwineRelayException(result.failureOrNull!.message);
    }
    final events = result.valueOrNull!;
    _orderStream = events;
    _orderSub = events.stream.listen((event) {
      final order = TwineOrder.open(
        daemonPublicKey: target.publicKey,
        event: event,
      );
      if (order != null && !_orders.isClosed) _orders.add(order);
    }, onError: (_) {});
  }

  /// Asks the relays for the orders they already have, and leaves the open
  /// subscription in place so a public order published a moment later still
  /// arrives on it.
  void replayOrders() {
    if (_orderSub == null) {
      watchOrders();
      return;
    }
    final target = daemon;
    if (target == null) {
      throw StateError('choose a daemon first');
    }
    final result = nostr.subscribe(
      NostrFilter(kinds: const [kindOrder], authors: [target.publicKey]),
    );
    if (result.isFailure) {
      throw TwineRelayException(result.failureOrNull!.message);
    }
    _orderReplay = result.valueOrNull;
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

  /// Subscribes to this daemon's payment catalog.
  void watchCatalog() {
    _stopCatalog();
    final target = daemon;
    if (target == null) {
      throw StateError('choose a daemon first');
    }
    final result = nostr.subscribe(
      NostrFilter(
        kinds: const [kindCatalog],
        authors: [target.publicKey],
        additionalFilters: const {
          '#d': [paymentCatalogTag],
        },
      ),
    );
    if (result.isFailure) {
      throw TwineRelayException(result.failureOrNull!.message);
    }
    final events = result.valueOrNull!;
    _catalogStream = events;
    _catalogSub = events.stream.listen((event) {
      final catalog = openCatalog(
        daemonPublicKey: target.publicKey,
        event: event,
      );
      if (catalog != null && !_catalogs.isClosed) _catalogs.add(catalog);
    }, onError: (_) {});
  }

  void stopWatching() {
    _relayWatch?.cancel();
    _relayWatch = null;
    _openSockets = '';
    _replySub?.cancel();
    _replySub = null;
    _replyStream?.close();
    _replyStream = null;
    _stopOrders();
    _stopFiber();
    _stopCatalog();
  }

  void _stopOrders() {
    _orderSub?.cancel();
    _orderSub = null;
    _orderReplay?.close();
    _orderReplay = null;
    _orderStream?.close();
    _orderStream = null;
  }

  void _stopFiber() {
    _fiberSub?.cancel();
    _fiberSub = null;
    _fiberStream?.close();
    _fiberStream = null;
  }

  void _stopCatalog() {
    _catalogSub?.cancel();
    _catalogSub = null;
    _catalogStream?.close();
    _catalogStream = null;
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
    _armRelayWatch();
    return open;
  }

  /// Asks again when a relay socket is replaced. A reconnect does not replay
  /// the previous subscription, so a public order published into that gap
  /// would never reach the book.
  void _armRelayWatch() {
    _relayWatch?.cancel();
    _openSockets = _socketKey();
    _relayWatch = Timer.periodic(const Duration(seconds: 1), (_) {
      final next = _socketKey();
      if (next == _openSockets) return;
      _openSockets = next;
      if (next.isEmpty || account == null || daemon == null) return;
      try {
        watchReplies();
        watchFiberNode();
        watchOrders();
        watchCatalog();
      } catch (_) {}
    });
  }

  String _socketKey() {
    final entries = nostr.relays.relaysWebSocketsRegistry.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    return [
      for (final entry in entries)
        '${entry.key}@${identityHashCode(entry.value)}',
    ].join(' ');
  }
}
