import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:twine_app/nostr/order.dart';

void main() {
  test('a public order opens when the id matches', () {
    final order = TwineOrder.fromVerified(
      content: _body('order-1'),
      identifier: 'order-1',
      updatedAt: DateTime.utc(2026, 10, 6),
    );
    expect(order?.orderId, 'order-1');
    expect(order?.availableCkb, '10');
    expect(order?.fiatCurrency, 'NGN');
    expect(order?.holdHours, 36);
    expect(order?.status, PostStatus.open);
    expect(order?.reservedCkb, '1');
    expect(order?.updatedAt, DateTime.utc(2026, 10, 6));
  });

  test('a canceled post stays canceled and an unknown status is dropped', () {
    expect(
      TwineOrder.fromVerified(
        content: _body('order-1', status: 'canceled'),
        identifier: 'order-1',
        updatedAt: DateTime.utc(2026, 10, 6),
      )?.status,
      PostStatus.canceled,
    );
    expect(
      TwineOrder.fromVerified(
        content: _body('order-1', status: 'filled'),
        identifier: 'order-1',
        updatedAt: DateTime.utc(2026, 10, 6),
      ),
      isNull,
    );
  });

  test('a public order with the wrong id tag is dropped', () {
    expect(
      TwineOrder.fromVerified(
        content: _body('order-1'),
        identifier: 'other',
        updatedAt: DateTime.utc(2026, 10, 6),
      ),
      isNull,
    );
    expect(
      TwineOrder.fromVerified(
        content: _body('order-1', side: 'buy'),
        identifier: 'order-1',
        updatedAt: DateTime.utc(2026, 10, 6),
      ),
      isNull,
    );
  });
}

String _body(
  String orderId, {
  String? status,
  String side = 'sell',
}) {
  return jsonEncode({
    'order_id': orderId,
    'status': ?status,
    'side': side,
    'maker_nostr_pubkey': 'maker',
    'maker_fiber_pubkey': 'fiber',
    'available_ckb': '10',
    'fiat_currency': 'NGN',
    'price_per_ckb': '1500',
    'min': '1000',
    'max': '5000',
    'hold_hours': 36,
    'reserved_ckb': '1',
  });
}
