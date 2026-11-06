import 'dart:async';

import 'account.dart';
import 'chat.dart';
import 'daemon.dart';
import 'envelope.dart';
import 'fiber_node.dart';
import 'order.dart';
import 'relay_backend.dart';
import 'reply.dart';

class TwineRelayException implements Exception {
  TwineRelayException(this.message);

  final String message;

  @override
  String toString() => message;
}

class TwineNostr {
  factory TwineNostr({TwineRelayBackend? backend}) {
    return TwineNostr._(backend ?? FakeRelayBackend());
  }

  factory TwineNostr.native() => TwineNostr._(FrbRelayBackend());

  TwineNostr._(this._backend) {
    current = this;
    _repliesSub = _backend.replies.listen(_replies.add, onError: (_) {});
    _ordersSub = _backend.orders.listen(_orders.add, onError: (_) {});
    _fiberSub = _backend.fiberNodes.listen(_fiberNodes.add, onError: (_) {});
    _chatsSub = _backend.chats.listen(_chats.add, onError: (_) {});
  }

  static TwineNostr? current;

  final TwineRelayBackend _backend;
  TwineAccount? account;
  TwineDaemon? daemon;
  void Function()? onRelayDropped;
  void Function()? onSocketsReplaced;

  final _replies = StreamController<DaemonReplyEvent>.broadcast();
  final _orders = StreamController<TwineOrder>.broadcast();
  final _fiberNodes = StreamController<FiberAnnouncement>.broadcast();
  final _chats = StreamController<ChatEvent>.broadcast();
  StreamSubscription<DaemonReplyEvent>? _repliesSub;
  StreamSubscription<TwineOrder>? _ordersSub;
  StreamSubscription<FiberAnnouncement>? _fiberSub;
  StreamSubscription<ChatEvent>? _chatsSub;

  Stream<DaemonReplyEvent> get replies => _replies.stream;
  Stream<TwineOrder> get orders => _orders.stream;
  Stream<FiberAnnouncement> get fiberNodes => _fiberNodes.stream;
  Stream<ChatEvent> get chats => _chats.stream;

  Future<void> send(TwineEnvelope envelope) async {
    await _backend.sendAction(envelope.encode());
  }

  Future<ChatEvent> sendChat({
    required String peer,
    required ChatBody body,
  }) {
    return _backend.sendChat(peerHex: peer, bodyJson: body.encode());
  }

  Future<String?> conversationKey(String peerHex) {
    return _backend.conversationKey(peerHex);
  }

  void watchTradeChat({
    required String accountPubkey,
    required List<String> authors,
    required List<String> tradeIds,
  }) {
    _backend.watchTradeChat(
      accountPubkey: accountPubkey,
      authors: authors,
      tradeIds: tradeIds,
    );
  }

  void watchReplies() {}

  void watchOrders() {}

  void watchFiberNode() {}

  void stopWatching() {
    _backend.watchTradeChat(
      accountPubkey: '',
      authors: const [],
      tradeIds: const [],
    );
  }

  Future<bool> reconcile() async {
    try {
      await resync();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<List<String>> connect(List<String> relays) {
    final signer = account;
    final target = daemon;
    if (signer == null || target == null) {
      throw StateError('sign in and choose a daemon first');
    }
    return _backend.connect(
      nsec: signer.nsec,
      daemonHex: target.publicKey,
      relays: relays,
    );
  }

  Future<List<String>> resync() {
    return _backend.resync();
  }

  Future<void> setPushToken({required String url, required String token}) {
    return _backend.setPushToken(url: url, token: token);
  }

  void dispose() {
    _repliesSub?.cancel();
    _ordersSub?.cancel();
    _fiberSub?.cancel();
    _chatsSub?.cancel();
    unawaited(_replies.close());
    unawaited(_orders.close());
    unawaited(_fiberNodes.close());
    unawaited(_chats.close());
  }
}
