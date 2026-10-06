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

  TwineAccount? account;

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
  final _chats = StreamController<NostrEvent>.broadcast();
  StreamSubscription<NostrEvent>? _chatSub;
  NostrEventsStream? _chatStream;
  String? _chatAccount;
  List<String> _chatAuthors = const [];
  List<String> _chatTrades = const [];
  Timer? _relayWatch;
  String _openSockets = '';

  Stream<DaemonReplyEvent> get replies => _replies.stream;

  Stream<TwineOrder> get orders => _orders.stream;

  Stream<String> get fiberNodes => _fiberNodes.stream;

  Stream<OpenedCatalog> get catalogs => _catalogs.stream;

  Stream<NostrEvent> get chats => _chats.stream;

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

  Future<void> send(TwineEnvelope envelope) async {
    await publish(seal(envelope));
  }

  Future<void> publish(NostrEvent event) async {
    final result = await nostr.publish(event);
    if (result.isFailure) {
      throw TwineRelayException(result.failureOrNull!.message);
    }
  }

  void watchTradeChat({
    required String accountPubkey,
    required List<String> authors,
    required List<String> tradeIds,
  }) {
    _chatAccount = accountPubkey;
    _chatAuthors = [...authors]..sort();
    _chatTrades = [...tradeIds]..sort();
    _subscribeChat();
  }

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
    _stopChat();
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

  void _stopChat() {
    _chatSub?.cancel();
    _chatSub = null;
    _chatStream?.close();
    _chatStream = null;
  }

  void _subscribeChat() {
    _stopChat();
    final account = _chatAccount;
    if (account == null || _chatAuthors.isEmpty || _chatTrades.isEmpty) return;
    final result = nostr.subscribe(
      NostrFilter(
        kinds: const [kindChat],
        authors: _chatAuthors,
        p: [account],
        additionalFilters: {'#t': _chatTrades},
      ),
    );
    if (result.isFailure) return;
    final events = result.valueOrNull!;
    _chatStream = events;
    _chatSub = events.stream.listen((event) {
      if (!_chats.isClosed) _chats.add(event);
    }, onError: (_) {});
  }

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
    _subscribeChat();
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
        _subscribeChat();
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
