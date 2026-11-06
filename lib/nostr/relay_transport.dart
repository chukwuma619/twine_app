import 'dart:async';

import 'package:dart_nostr/dart_nostr.dart';
import 'package:dart_nostr/nostr/instance/relays/relays.dart';
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// Dials relays ourselves.
///
/// `dart_nostr` reconnects on close, and it treats `closeCode == null` as a
/// live socket. A phone keeps that null after the OS drops the TCP connection,
/// so the library skips the next dial and never sends the subscriptions again.
/// This transport does not retry on its own. The app dials, and a websocket
/// ping closes the socket when a pong does not come back.
class OwnedRelayTransport implements NostrRelayTransport {
  OwnedRelayTransport(this.relays) : _legacy = LegacyNostrRelayTransport(relays);

  final NostrRelays relays;
  final LegacyNostrRelayTransport _legacy;

  /// Called with the dial generation that opened the socket.
  /// A close from an older dial is ignored by the caller.
  void Function(int epoch)? onClosed;

  /// Generation of the dial in progress. Listeners capture it.
  int epoch = 0;

  /// How long a missing pong may take before the socket is closed.
  static const _pingEvery = Duration(seconds: 25);

  static const _dropBudget = Duration(seconds: 2);

  @override
  Future<void> connect({
    required List<String> relays,
    required Duration connectionTimeout,
  }) async {
    this.relays.relaysList = List<String>.of(relays);
    await Future.wait(
      relays.map((url) => _dial(url, connectionTimeout)),
      eagerError: false,
    );
  }

  Future<void> _dial(String url, Duration connectionTimeout) async {
    final registry = relays.relaysWebSocketsRegistry;
    final previous = registry.remove(url);
    if (previous != null) _drop(previous);

    final channel = IOWebSocketChannel.connect(
      url,
      pingInterval: _pingEvery,
      connectTimeout: connectionTimeout,
    );
    try {
      await channel.ready.timeout(connectionTimeout);
    } catch (_) {
      _drop(channel);
      return;
    }

    registry[url] = channel;
    final born = epoch;
    relays.startListeningToRelay(
      relay: url,
      onRelayListening: null,
      onRelayConnectionError: (_, _, _) => onClosed?.call(born),
      onRelayConnectionDone: (_, _) => onClosed?.call(born),
      onNoticeMessageFromRelay: null,
      retryOnError: false,
      retryOnClose: false,
      shouldReconnectToRelayOnNotice: false,
      connectionTimeout: connectionTimeout,
      ignoreConnectionException: true,
      lazyListeningToRelays: false,
    );
  }

  void _drop(WebSocketChannel socket) {
    unawaited(
      socket.sink
          .close()
          .timeout(_dropBudget)
          .then<void>((_) {}, onError: (Object _) {}),
    );
  }

  @override
  Future<NostrEventOkCommand> publish(
    NostrEvent event, {
    required Duration timeout,
    List<String>? relays,
  }) {
    return _legacy.publish(event, timeout: timeout, relays: relays);
  }

  @override
  Future<NostrCountResponse> count(
    NostrCountEvent countEvent, {
    required Duration timeout,
    List<String>? relays,
  }) {
    return _legacy.count(countEvent, timeout: timeout, relays: relays);
  }

  @override
  NostrEventsStream subscribe({
    required NostrRequest request,
    List<String>? relays,
  }) {
    return _legacy.subscribe(request: request, relays: relays);
  }

  @override
  void closeSubscription(String subscriptionId, [String? relay]) {
    _legacy.closeSubscription(subscriptionId, relay);
  }

  @override
  Future<bool> disconnect() {
    return _legacy.disconnect();
  }
}
