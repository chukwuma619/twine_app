import 'dart:async';

import 'package:twine_app/src/rust/api/nostr.dart' as rust_nostr;
import 'package:twine_app/src/rust/api/push.dart' as rust_push;

import 'account.dart';
import 'chat.dart';
import 'envelope.dart';
import 'fiber_node.dart';
import 'nip44.dart';
import 'order.dart';
import 'reply.dart';
import 'twine_nostr.dart';

abstract class TwineRelayBackend {
  Stream<DaemonReplyEvent> get replies;
  Stream<TwineOrder> get orders;
  Stream<FiberAnnouncement> get fiberNodes;
  Stream<ChatEvent> get chats;

  Future<List<String>> connect({
    required String nsec,
    required String daemonHex,
    required List<String> relays,
  });

  Future<List<String>> resync();

  Future<void> sendAction(String envelopeJson);

  Future<ChatEvent> sendChat({required String peerHex, required String bodyJson});

  void watchTradeChat({
    required String accountPubkey,
    required List<String> authors,
    required List<String> tradeIds,
  });

  Future<String?> conversationKey(String peerHex);

  Future<void> setPushToken({required String url, required String token});
}

/// In-memory backend for widget and book tests. No sockets.
class FakeRelayBackend implements TwineRelayBackend {
  final _replies = StreamController<DaemonReplyEvent>.broadcast();
  final _orders = StreamController<TwineOrder>.broadcast();
  final _fiber = StreamController<FiberAnnouncement>.broadcast();
  final _chats = StreamController<ChatEvent>.broadcast();
  String? _nsec;
  List<String> _relays = const [];

  @override
  Stream<DaemonReplyEvent> get replies => _replies.stream;

  @override
  Stream<TwineOrder> get orders => _orders.stream;

  @override
  Stream<FiberAnnouncement> get fiberNodes => _fiber.stream;

  @override
  Stream<ChatEvent> get chats => _chats.stream;

  @override
  Future<List<String>> connect({
    required String nsec,
    required String daemonHex,
    required List<String> relays,
  }) async {
    for (final relay in relays) {
      final uri = Uri.tryParse(relay);
      if (uri == null || (uri.scheme != 'ws' && uri.scheme != 'wss')) {
        throw TwineRelayException('no nostr relay connected');
      }
    }
    _nsec = nsec;
    _relays = [...relays]..sort();
    return _relays;
  }

  @override
  Future<List<String>> resync() async {
    if (_relays.isEmpty) throw TwineRelayException('no nostr relay connected');
    return _relays;
  }

  @override
  Future<void> sendAction(String envelopeJson) async {
    TwineEnvelope.tryDecode(envelopeJson);
  }

  @override
  Future<ChatEvent> sendChat({
    required String peerHex,
    required String bodyJson,
  }) async {
    final body = ChatBody.tryDecode(bodyJson);
    if (body == null) {
      throw TwineRelayException('Could not sign the message.');
    }
    return ChatEvent(
      id: 'local-${DateTime.now().microsecondsSinceEpoch}',
      author: '',
      createdAt: DateTime.now().toUtc(),
      body: body,
    );
  }

  @override
  void watchTradeChat({
    required String accountPubkey,
    required List<String> authors,
    required List<String> tradeIds,
  }) {}

  @override
  Future<String?> conversationKey(String peerHex) async {
    final secret = _nsec;
    if (secret == null) return null;
    final account = TwineAccount.tryParse(secret);
    if (account == null) return null;
    try {
      return nip44ConversationKeyHex(account.privateKey, peerHex);
    } on Nip44Exception {
      return null;
    }
  }

  @override
  Future<void> setPushToken({required String url, required String token}) async {}
}

class FrbRelayBackend implements TwineRelayBackend {
  final _replies = StreamController<DaemonReplyEvent>.broadcast();
  final _orders = StreamController<TwineOrder>.broadcast();
  final _fiber = StreamController<FiberAnnouncement>.broadcast();
  final _chats = StreamController<ChatEvent>.broadcast();
  var _pumping = false;
  List<String>? _chatAuthors;
  List<String>? _chatTrades;
  String? _pushUrl;
  String? _pushToken;

  @override
  Stream<DaemonReplyEvent> get replies => _replies.stream;

  @override
  Stream<TwineOrder> get orders => _orders.stream;

  @override
  Stream<FiberAnnouncement> get fiberNodes => _fiber.stream;

  @override
  Stream<ChatEvent> get chats => _chats.stream;

  @override
  Future<List<String>> connect({
    required String nsec,
    required String daemonHex,
    required List<String> relays,
  }) async {
    try {
      final urls = await rust_nostr.initialize(
        nsec: nsec,
        daemonHex: daemonHex,
        relays: relays,
      );
      _startPumps();
      await _replayAfterLink();
      return urls;
    } catch (error) {
      throw TwineRelayException(error.toString());
    }
  }

  @override
  Future<List<String>> resync() async {
    try {
      return await rust_nostr.resync();
    } catch (error) {
      throw TwineRelayException(error.toString());
    }
  }

  @override
  Future<void> sendAction(String envelopeJson) async {
    try {
      await rust_nostr.sendAction(envelopeJson: envelopeJson);
    } catch (error) {
      throw TwineRelayException(error.toString());
    }
  }

  @override
  Future<ChatEvent> sendChat({
    required String peerHex,
    required String bodyJson,
  }) async {
    try {
      final dto = await rust_nostr.sendChat(
        peerHex: peerHex,
        bodyJson: bodyJson,
      );
      final event = ChatEvent.fromDto(dto);
      if (event == null) {
        throw TwineRelayException('Could not sign the message.');
      }
      return event;
    } catch (error) {
      if (error is TwineRelayException) rethrow;
      throw TwineRelayException(error.toString());
    }
  }

  @override
  void watchTradeChat({
    required String accountPubkey,
    required List<String> authors,
    required List<String> tradeIds,
  }) {
    _chatAuthors = authors;
    _chatTrades = tradeIds;
    unawaited(_applyWatch());
  }

  @override
  Future<String?> conversationKey(String peerHex) async {
    try {
      return await rust_nostr.conversationKey(peerHex: peerHex);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> setPushToken({required String url, required String token}) {
    _pushUrl = url;
    _pushToken = token;
    return _applyPush();
  }

  Future<void> _replayAfterLink() async {
    await _applyWatch();
    await _applyPush();
  }

  Future<void> _applyWatch() async {
    final authors = _chatAuthors;
    final trades = _chatTrades;
    if (authors == null || trades == null) return;
    try {
      await rust_nostr.watchTradeChat(authors: authors, tradeIds: trades);
    } catch (_) {}
  }

  Future<void> _applyPush() async {
    final url = _pushUrl;
    if (url == null || url.isEmpty) return;
    try {
      await rust_push.setPushToken(url: url, token: _pushToken ?? '');
    } catch (_) {}
  }

  void _startPumps() {
    if (_pumping) return;
    _pumping = true;
    unawaited(_pumpReplies());
    unawaited(_pumpOrders());
    unawaited(_pumpFiber());
    unawaited(_pumpChats());
  }

  Future<void> _pumpReplies() async {
    await _pump(() async {
      final stream = await rust_nostr.listenReplies();
      while (true) {
        final next = await stream.next();
        if (next == null) return;
        final envelope = TwineEnvelope.tryDecode(next.envelopeJson);
        if (envelope == null) continue;
        _replies.add(
          DaemonReplyEvent(
            envelope: envelope,
            createdAt: DateTime.fromMillisecondsSinceEpoch(
              next.createdAtSecs.toInt() * 1000,
              isUtc: true,
            ),
          ),
        );
      }
    });
  }

  Future<void> _pumpOrders() async {
    await _pump(() async {
      final stream = await rust_nostr.listenOrders();
      while (true) {
        final next = await stream.next();
        if (next == null) return;
        final order = TwineOrder.fromVerified(
          content: next.contentJson,
          identifier: next.identifier,
          updatedAt: DateTime.fromMillisecondsSinceEpoch(
            next.createdAtSecs.toInt() * 1000,
            isUtc: true,
          ),
        );
        if (order != null) _orders.add(order);
      }
    });
  }

  Future<void> _pumpFiber() async {
    await _pump(() async {
      final stream = await rust_nostr.listenFiber();
      while (true) {
        final next = await stream.next();
        if (next == null) return;
        final announcement = FiberAnnouncement.fromContent(next.contentJson);
        if (announcement != null) _fiber.add(announcement);
      }
    });
  }

  Future<void> _pumpChats() async {
    await _pump(() async {
      final stream = await rust_nostr.listenChats();
      while (true) {
        final next = await stream.next();
        if (next == null) return;
        final event = ChatEvent.fromDto(next);
        if (event != null) _chats.add(event);
      }
    });
  }

  Future<void> _pump(Future<void> Function() once) async {
    while (_pumping) {
      try {
        await once();
      } catch (_) {}
      if (!_pumping) return;
      await Future<void>.delayed(const Duration(seconds: 1));
    }
  }
}
