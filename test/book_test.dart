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

  test('a post makes the poster the seller and the taker the buyer', () {
    final order = _order();
    expect(tradeSide(order, 'maker'), TradeSide.seller);
    expect(tradeSide(order, 'taker'), TradeSide.buyer);
    expect(isMaker(order, 'MAKER'), isTrue);
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

  test('fiat sent during a dispute keeps the dispute and starts the clock', () {
    final book = TwineBook();
    book.applyReply(_pay(), DateTime.utc(2026, 10, 6, 1));
    book.applyReply(_waiting(), DateTime.utc(2026, 10, 6, 2));
    book.applyReply(
      const TwineEnvelope(action: 'disputed', tradeId: 'trade-1'),
      DateTime.utc(2026, 10, 6, 3),
    );
    book.applyReply(
      const TwineEnvelope(
        action: 'fiat-sent-ok',
        tradeId: 'trade-1',
        payload: {'release_by': 1700008100, 'solver_window_secs': 14400},
      ),
      DateTime.utc(2026, 10, 6, 4),
    );

    final trade = book.trade('trade-1');
    expect(trade?.phase, TradePhase.disputed);
    expect(
      trade?.releaseBy,
      DateTime.fromMillisecondsSinceEpoch(1700008100 * 1000, isUtc: true),
    );
    expect(trade?.solverWindowSecs, 14400);
  });

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

  test(
    'a cancel reply names the post and an older open copy cannot reopen it',
    () {
      final book = TwineBook();
      final posted = DateTime.utc(2026, 10, 6, 1);
      book.applyOrder(_order(at: posted));
      book.applyReply(
        const TwineEnvelope(
          action: 'canceled',
          payload: {'order_id': 'order-1'},
        ),
        DateTime.utc(2026, 10, 6, 2),
      );
      expect(book.order('order-1')?.status, PostStatus.canceled);
      expect(book.notice, isNull);

      book.applyOrder(_order(at: posted));
      expect(book.order('order-1')?.status, PostStatus.canceled);

      book.applyOrder(
        _order(at: DateTime.utc(2026, 10, 6, 3), status: PostStatus.canceled),
      );
      expect(book.order('order-1')?.status, PostStatus.canceled);
    },
  );

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

  test('an expired payout refund says why', () {
    final book = TwineBook();
    book.applyReply(_pay(), DateTime.utc(2026, 10, 6, 1));
    book.applyReply(
      const TwineEnvelope(
        action: 'refunding',
        tradeId: 'trade-1',
        payload: {'reason': 'the payout invoice expired'},
      ),
      DateTime.utc(2026, 10, 6, 2),
    );
    expect(book.trade('trade-1')?.phase, TradePhase.refunding);
    expect(book.trade('trade-1')?.notice, 'the payout invoice expired');
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

  test('waiting for fiat names both traders', () {
    final book = TwineBook();
    book.applyReply(
      const TwineEnvelope(
        action: 'pay-invoice',
        tradeId: 'trade-1',
        payload: {
          'invoice': 'hold-invoice',
          'amount_shannons': '100000000',
          'order_id': 'order-1',
          'seller_nostr': 'seller',
          'buyer_nostr': 'buyer',
        },
      ),
      DateTime.utc(2026, 10, 6, 1),
    );
    book.applyReply(
      const TwineEnvelope(
        action: 'waiting-fiat',
        tradeId: 'trade-1',
        payload: {
          'fiat_amount': '2500',
          'fiat_currency': 'NGN',
          'reference': 'trade-1',
          'seller_nostr': 'seller',
          'buyer_nostr': 'buyer',
        },
      ),
      DateTime.utc(2026, 10, 6, 2),
    );

    final trade = book.trade('trade-1');
    expect(trade?.sellerNostr, 'seller');
    expect(trade?.buyerNostr, 'buyer');
    expect(trade?.phase, TradePhase.waitingFiat);
    expect(book.thread('trade-1').single.text, 'The CKB is locked.');
    expect(
      TwineBook.fromJson(book.toJson())?.trade('trade-1')?.buyerNostr,
      'buyer',
    );
  });

  test('pay-invoice and waiting-fiat store the daemon clocks', () {
    final book = TwineBook();
    book.applyReply(
      const TwineEnvelope(
        action: 'pay-invoice',
        tradeId: 'trade-1',
        payload: {
          'invoice': 'hold-invoice',
          'amount_shannons': '100000000',
          'order_id': 'order-1',
          'lock_by': 1700003600,
          'hold_ends_at': 1700132400,
        },
      ),
      DateTime.utc(2026, 10, 6, 1),
    );
    book.applyReply(
      const TwineEnvelope(
        action: 'waiting-fiat',
        tradeId: 'trade-1',
        payload: {
          'fiat_amount': '2500',
          'fiat_currency': 'NGN',
          'reference': 'trade-1',
          'pay_by': 1700000900,
          'release_by': 1700130600,
        },
      ),
      DateTime.utc(2026, 10, 6, 2),
    );

    final trade = book.trade('trade-1');
    expect(
      trade?.lockBy,
      DateTime.fromMillisecondsSinceEpoch(1700003600 * 1000, isUtc: true),
    );
    expect(
      trade?.holdEndsAt,
      DateTime.fromMillisecondsSinceEpoch(1700132400 * 1000, isUtc: true),
    );
    expect(
      trade?.payBy,
      DateTime.fromMillisecondsSinceEpoch(1700000900 * 1000, isUtc: true),
    );
    expect(
      trade?.releaseBy,
      DateTime.fromMillisecondsSinceEpoch(1700130600 * 1000, isUtc: true),
    );
    expect(
      TwineBook.fromJson(book.toJson())?.trade('trade-1')?.payBy,
      trade?.payBy,
    );
  });

  test(
    'fiat-sent stores the release grace and release-due keeps the phase',
    () {
      final book = TwineBook();
      book.applyReply(
        const TwineEnvelope(
          action: 'pay-invoice',
          tradeId: 'trade-1',
          payload: {
            'invoice': 'hold-invoice',
            'amount_shannons': '100000000',
            'order_id': 'order-1',
          },
        ),
        DateTime.utc(2026, 10, 6, 1),
      );
      book.applyReply(
        const TwineEnvelope(
          action: 'waiting-fiat',
          tradeId: 'trade-1',
          payload: {
            'fiat_amount': '2500',
            'fiat_currency': 'NGN',
            'reference': 'trade-1',
            'pay_by': 1700000900,
          },
        ),
        DateTime.utc(2026, 10, 6, 2),
      );
      book.applyReply(
        const TwineEnvelope(
          action: 'fiat-sent-ok',
          tradeId: 'trade-1',
          payload: {'release_by': 1700008100, 'solver_window_secs': 14400},
        ),
        DateTime.utc(2026, 10, 6, 3),
      );
      final sent = book.trade('trade-1');
      expect(sent?.phase, TradePhase.fiatSent);
      expect(
        sent?.releaseBy,
        DateTime.fromMillisecondsSinceEpoch(1700008100 * 1000, isUtc: true),
      );
      expect(sent?.solverWindowSecs, 14400);

      book.applyReply(
        const TwineEnvelope(
          action: 'release-due',
          tradeId: 'trade-1',
          payload: {'release_by': 1700008100, 'solver_window_secs': 14400},
        ),
        DateTime.utc(2026, 10, 6, 4),
      );
      expect(book.trade('trade-1')?.phase, TradePhase.fiatSent);
      expect(
        TwineBook.fromJson(book.toJson())?.trade('trade-1')?.solverWindowSecs,
        14400,
      );
    },
  );

  test('a trades reply merges only the caller snapshots', () {
    final book = TwineBook();
    book.applyReply(
      const TwineEnvelope(
        action: 'trades',
        payload: {
          'trades': [
            {
              'trade_id': 'trade-1',
              'order_id': 'order-1',
              'state': 'waiting-fiat',
              'seller_nostr': 'seller',
              'buyer_nostr': 'buyer',
              'fiat_amount': '2500',
              'fiat_currency': 'NGN',
              'amount_shannons': '100000000',
              'reference': 'tw-1',
              'hold_invoice': 'hold-invoice',
              'lock_by': 1700003600,
              'hold_ends_at': 1700132400,
              'pay_by': 1700000900,
              'release_by': 1700130600,
            },
          ],
        },
      ),
      DateTime.utc(2026, 10, 6, 3),
    );

    final trade = book.trade('trade-1');
    expect(trade?.phase, TradePhase.waitingFiat);
    expect(trade?.sellerNostr, 'seller');
    expect(trade?.buyerNostr, 'buyer');
    expect(trade?.holdInvoice, 'hold-invoice');
    expect(
      trade?.payBy,
      DateTime.fromMillisecondsSinceEpoch(1700000900 * 1000, isUtc: true),
    );
  });

  test('waiting-fiat can return to awaiting-route', () {
    final book = TwineBook();
    book.applyReply(_pay(), DateTime.utc(2026, 10, 6, 1));
    book.applyReply(_waiting(), DateTime.utc(2026, 10, 6, 2));
    book.applyReply(
      const TwineEnvelope(
        action: 'need-route',
        tradeId: 'trade-1',
        payload: {'reason': 'no route to the payout invoice'},
      ),
      DateTime.utc(2026, 10, 6, 3),
    );
    final trade = book.trade('trade-1');
    expect(trade?.phase, TradePhase.awaitingRoute);
    expect(trade?.payoutFailure, 'no route to the payout invoice');
  });

  test('unresolved sits with the other trade records', () {
    final book = TwineBook();
    book.applyReply(_pay(), DateTime.utc(2026, 10, 6, 1));
    book.applyReply(_waiting(), DateTime.utc(2026, 10, 6, 2));
    book.applyReply(
      const TwineEnvelope(
        action: 'fiat-sent-ok',
        tradeId: 'trade-1',
        payload: {'release_by': 1700008100, 'solver_window_secs': 14400},
      ),
      DateTime.utc(2026, 10, 6, 3),
    );
    book.applyReply(
      const TwineEnvelope(
        action: 'trade-record',
        tradeId: 'trade-1',
        payload: {'outcome': 'unresolved'},
      ),
      DateTime.utc(2026, 10, 6, 4),
    );
    final trade = book.trade('trade-1');
    expect(trade?.phase, TradePhase.fiatSent);
    expect(trade?.record, 'unresolved');
    final lines = book.thread('trade-1').map((note) => note.text).toList();
    expect(lines, contains('The buyer marked the payment as sent.'));
    expect(
      lines,
      contains(
        'Unresolved. The solver window ended with no decision. The CKB still returns to the seller.',
      ),
    );
    expect(
      TwineBook.fromJson(book.toJson())?.trade('trade-1')?.record,
      'unresolved',
    );
  });
}

TwineOrder _order({
  String available = '10',
  DateTime? at,
  PostStatus status = PostStatus.open,
}) {
  return TwineOrder(
    orderId: 'order-1',
    makerNostrPubkey: 'maker',
    makerFiberPubkey: 'fiber',
    availableCkb: available,
    fiatCurrency: 'NGN',
    pricePerCkb: '1500',
    min: '1000',
    max: '5000',
    holdHours: 36,
    updatedAt: at ?? DateTime.utc(2026, 10, 6),
    status: status,
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
    },
  );
}
