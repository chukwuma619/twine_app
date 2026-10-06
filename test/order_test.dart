import 'dart:convert';

import 'package:dart_nostr/dart_nostr.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twine_app/constant.dart';
import 'package:twine_app/nostr/account.dart';
import 'package:twine_app/nostr/order.dart';

void main() {
  final nostr = Nostr();

  test('a public order opens only for the daemon that signed it', () {
    final daemon = TwineAccount.generate(nostr);
    final stranger = TwineAccount.generate(nostr);
    final event = _orderEvent(daemon, 'order-1');

    final order = TwineOrder.open(
      daemonPublicKey: daemon.publicKey,
      event: event,
    );
    expect(order?.orderId, 'order-1');
    expect(order?.side, OrderSide.sell);
    expect(order?.availableCkb, '10');
    expect(order?.paymentMethods.single.label, 'GTBank');
    expect(order?.holdHours, 36);
    expect(order?.updatedAt, DateTime.utc(2026, 10, 6));

    expect(
      TwineOrder.open(daemonPublicKey: stranger.publicKey, event: event),
      isNull,
    );
  });

  test('a public order with the wrong id tag is dropped', () {
    final daemon = TwineAccount.generate(nostr);
    final event = _orderEvent(daemon, 'order-1', tag: 'other');
    expect(
      TwineOrder.open(daemonPublicKey: daemon.publicKey, event: event),
      isNull,
    );
  });
}

NostrEvent _orderEvent(TwineAccount daemon, String orderId, {String? tag}) {
  return NostrEvent.fromPartialData(
    kind: kindOrder,
    content: jsonEncode({
      'order_id': orderId,
      'side': 'sell',
      'maker_nostr_pubkey': 'maker',
      'maker_fiber_pubkey': 'fiber',
      'available_ckb': '10',
      'fiat_currency': 'NGN',
      'price_per_ckb': '1500',
      'min': '1000',
      'max': '5000',
      'payment_methods': [
        {'id': 'gtbank', 'kind': 'bank', 'label': 'GTBank', 'currency': 'NGN'},
      ],
      'hold_hours': 36,
    }),
    keyPairs: NostrKeyPairs(private: daemon.privateKey),
    tags: [
      ['d', tag ?? orderId],
    ],
    createdAt: DateTime.utc(2026, 10, 6),
  );
}
