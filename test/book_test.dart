import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_secure_storage/test/test_flutter_secure_storage_platform.dart';
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twine_app/market/amount.dart';
import 'package:twine_app/market/book.dart';
import 'package:twine_app/market/phase.dart';
import 'package:twine_app/market/role.dart';
import 'package:twine_app/nostr/envelope.dart';
import 'package:twine_app/nostr/order.dart';
import 'package:twine_app/store/book_store.dart';

void main() {
  test('shannons become a CKB string', () {
    expect(shannonsToCkb('100000000'), '1');
    expect(shannonsToCkb('150000000'), '1.5');
    expect(shannonsToCkb('1'), '0.00000001');
  });

  test('a sell post makes the poster the seller and the taker the buyer', () {
    final order = _order(side: OrderSide.sell);
    expect(tradeSide(order, 'maker'), TradeSide.seller);
    expect(tradeSide(order, 'taker'), TradeSide.buyer);
    expect(isMaker(order, 'MAKER'), isTrue);
    expect(tradeSide(_order(side: OrderSide.buy), 'maker'), TradeSide.buyer);
  });

  test(
    'replies walk a trade forward and an older reply cannot walk it back',
    () {
      final book = TwineBook();
      book.applyOrder(_order());
      book.applyReply(_pay(), DateTime.utc(2026, 10, 6, 1));
      book.applyReply(_waiting(), DateTime.utc(2026, 10, 6, 2));

      final waiting = book.trade('trade-1');
      expect(waiting?.phase, TradePhase.waitingFiat);
      expect(waiting?.holdInvoice, 'hold-invoice');
      expect(waiting?.fiatAmount, '2500');
      expect(waiting?.paymentLabel, 'GTBank');
      expect(waiting?.amountShannons, '100000000');

      book.applyReply(_pay(), DateTime.utc(2026, 10, 6, 1));
      expect(book.trade('trade-1')?.phase, TradePhase.waitingFiat);

      book.applyReply(
        const TwineEnvelope(action: 'fiat-sent-ok', tradeId: 'trade-1'),
        DateTime.utc(2026, 10, 6, 3),
      );
      expect(book.beginRelease('trade-1'), isNull);
      expect(book.trade('trade-1')?.phase, TradePhase.releasing);

      book.applyReply(
        const TwineEnvelope(action: 'settled', tradeId: 'trade-1'),
        DateTime.utc(2026, 10, 6, 4),
      );
      book.applyReply(_waiting(), DateTime.utc(2026, 10, 6, 5));
      expect(book.trade('trade-1')?.phase, TradePhase.settled);
      expect(book.trade('trade-1')?.holdInvoice, 'hold-invoice');
    },
  );

  test('a refused release returns the trade to the phase it left', () {
    final book = TwineBook();
    book.applyReply(_pay(), DateTime.utc(2026, 10, 6, 1));
    book.applyReply(_waiting(), DateTime.utc(2026, 10, 6, 2));
    book.applyReply(
      const TwineEnvelope(action: 'fiat-sent-ok', tradeId: 'trade-1'),
      DateTime.utc(2026, 10, 6, 3),
    );
    book.beginRelease('trade-1');
    book.applyReply(
      const TwineEnvelope(
        action: 'cant-do',
        tradeId: 'trade-1',
        payload: {'reason': 'only the seller can release'},
      ),
      DateTime.utc(2026, 10, 6, 4),
    );

    expect(book.trade('trade-1')?.phase, TradePhase.fiatSent);
    expect(book.trade('trade-1')?.notice, 'only the seller can release');
    expect(book.notice, 'only the seller can release');
  });

  test('a settled reply still keeps the hold invoice if it arrives first', () {
    final book = TwineBook();
    book.applyReply(
      const TwineEnvelope(action: 'settled', tradeId: 'trade-1'),
      DateTime.utc(2026, 10, 6, 4),
    );
    book.applyReply(_pay(), DateTime.utc(2026, 10, 6, 1));
    expect(book.trade('trade-1')?.phase, TradePhase.settled);
    expect(book.trade('trade-1')?.holdInvoice, 'hold-invoice');
    expect(book.trade('trade-1')?.orderId, 'order-1');
  });

  test('an older copy of a post does not replace the newer amount', () {
    final book = TwineBook();
    book.applyOrder(_order(available: '4', at: DateTime.utc(2026, 10, 6, 2)));
    book.applyOrder(_order(available: '10', at: DateTime.utc(2026, 10, 6, 1)));
    expect(book.orders.single.availableCkb, '4');
  });

  test('canceling a post has no trade id', () {
    final book = TwineBook();
    book.applyReply(
      const TwineEnvelope(action: 'canceled'),
      DateTime.utc(2026, 10, 6),
    );
    expect(book.notice, 'Canceled.');
    expect(book.trades, isEmpty);
  });

  test('a failed payout asks for a new invoice', () {
    final book = TwineBook();
    book.applyReply(_pay(), DateTime.utc(2026, 10, 6, 1));
    book.applyReply(_waiting(), DateTime.utc(2026, 10, 6, 2));
    book.applyReply(
      const TwineEnvelope(action: 'fiat-sent-ok', tradeId: 'trade-1'),
      DateTime.utc(2026, 10, 6, 3),
    );
    book.beginRelease('trade-1');
    book.applyReply(
      const TwineEnvelope(
        action: 'new-invoice',
        tradeId: 'trade-1',
        payload: {'reason': 'buyer payout failed'},
      ),
      DateTime.utc(2026, 10, 6, 4),
    );
    expect(book.trade('trade-1')?.phase, TradePhase.awaitingInvoice);
    expect(book.trade('trade-1')?.payoutFailure, 'buyer payout failed');
  });

  test('the book round-trips through the device store', () async {
    final data = <String, String>{};
    FlutterSecureStoragePlatform.instance = TestFlutterSecureStoragePlatform(
      data,
    );
    final store = SecureBookStore(storage: const FlutterSecureStorage());
    final book = TwineBook(orders: [_order()], fiberPubkey: '02abc');
    book.applyReply(_pay(), DateTime.utc(2026, 10, 6, 1));

    await store.write('account', 'daemon', book);
    final restored = await store.read('account', 'daemon');
    expect(restored?.fiberPubkey, '02abc');
    expect(restored?.orders.single.orderId, 'order-1');
    expect(restored?.trade('trade-1')?.holdInvoice, 'hold-invoice');

    data[data.keys.single] = jsonEncode({'orders': 'nope'});
    expect((await store.read('account', 'daemon'))?.orders, isEmpty);

    data[data.keys.single] = '{';
    expect(await store.read('account', 'daemon'), isNull);
    expect(data, isEmpty);
  });
}

TwineOrder _order({
  OrderSide side = OrderSide.sell,
  String available = '10',
  DateTime? at,
}) {
  return TwineOrder(
    orderId: 'order-1',
    side: side,
    makerNostrPubkey: 'maker',
    makerFiberPubkey: 'fiber',
    availableCkb: available,
    fiatCurrency: 'NGN',
    pricePerCkb: '1500',
    min: '1000',
    max: '5000',
    paymentMethods: const [
      TwinePaymentMethod(
        id: 'gtbank',
        kind: 'bank',
        label: 'GTBank',
        currency: 'NGN',
      ),
    ],
    holdHours: 36,
    updatedAt: at ?? DateTime.utc(2026, 10, 6),
  );
}

TwineEnvelope _pay() {
  return const TwineEnvelope(
    action: 'pay-invoice',
    tradeId: 'trade-1',
    payload: {
      'invoice': 'hold-invoice',
      'amount_shannons': '100000000',
      'order_id': 'order-1',
    },
  );
}

TwineEnvelope _waiting() {
  return const TwineEnvelope(
    action: 'waiting-fiat',
    tradeId: 'trade-1',
    payload: {
      'fiat_amount': '2500',
      'fiat_currency': 'NGN',
      'reference': 'trade-1',
      'kind': 'bank',
      'label': 'GTBank',
      'currency': 'NGN',
    },
  );
}
