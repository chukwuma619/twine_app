import 'package:flutter_test/flutter_test.dart';
import 'package:twine_app/constant.dart';
import 'package:twine_app/nostr/catalog.dart';
import 'package:twine_app/nostr/order.dart';
import 'package:twine_app/nostr/request.dart';

const _catalog = [
  CatalogMethod(id: 'gtbank', kind: 'bank', label: 'GTBank', currency: 'NGN'),
  CatalogMethod(id: 'zelle', kind: 'wallet', label: 'Zelle', currency: 'USD'),
];

void main() {
  test('a post names the side, the amounts, and catalog method ids', () {
    const draft = NewOrderDraft(
      side: OrderSide.sell,
      fiberPubkey: ' 02abc ',
      availableCkb: '100',
      fiatCurrency: 'NGN',
      pricePerCkb: '1500',
      min: '150000',
      max: '300000',
      methodIds: ['gtbank'],
    );

    expect(draft.validate(_catalog), isNull);
    final envelope = draft.envelope();
    expect(envelope.action, actionNewOrder);
    expect(envelope.payload, {
      'side': 'sell',
      'fiber_pubkey': '02abc',
      'available_ckb': '100',
      'fiat_currency': 'NGN',
      'price_per_ckb': '1500',
      'min': '150000',
      'max': '300000',
      'payment_methods': [
        {'method_id': 'gtbank'},
      ],
    });
  });

  test('a post whose smallest trade is under 100 CKB is refused', () {
    const draft = NewOrderDraft(
      side: OrderSide.sell,
      fiberPubkey: '02abc',
      availableCkb: '120',
      fiatCurrency: 'NGN',
      pricePerCkb: '1500',
      min: '3000',
      max: '180000',
      methodIds: ['gtbank'],
    );
    expect(draft.validate(_catalog), 'The minimum trade is 100 CKB.');
  });

  test('a post with the minimum above the maximum is refused', () {
    const draft = NewOrderDraft(
      side: OrderSide.buy,
      fiberPubkey: '02abc',
      availableCkb: '1',
      fiatCurrency: 'USD',
      pricePerCkb: '1',
      min: '20',
      max: '10',
      methodIds: ['zelle'],
    );
    expect(draft.validate(_catalog), 'The minimum is above the maximum.');
  });

  test('a take names the post, the amount, and one method', () {
    const draft = TakeDraft(
      orderId: 'order-1',
      fiatAmount: '2500',
      fiberPubkey: '02taker',
      paymentMethodId: 'gtbank',
    );
    expect(draft.validate(), isNull);
    expect(draft.envelope().action, actionTake);
    expect(draft.envelope().payload, {
      'order_id': 'order-1',
      'fiat_amount': '2500',
      'fiber_pubkey': '02taker',
      'payment_method_id': 'gtbank',
    });
    const withAddr = TakeDraft(
      orderId: 'order-1',
      fiatAmount: '2500',
      fiberPubkey: '02taker',
      paymentMethodId: 'gtbank',
      fiberAddr: '/ip4/1.2.3.4/tcp/8228',
    );
    expect(
      withAddr.envelope().payload,
      containsPair('fiber_addr', '/ip4/1.2.3.4/tcp/8228'),
    );
    expect(fiberAddrError('1.2.3.4:8228'), contains('multiaddr'));
    expect(fiberAddrError('/ip4/1.2.3.4/tcp/8228'), isNull);
    expect(fiberAddrError('/ip4/127.0.0.1/tcp/8228'), contains('reachable'));
    expect(
      fiatSentRequest(tradeId: 'trade-1', invoice: 'inv').tradeId,
      'trade-1',
    );
    expect(releaseRequest('trade-1').action, actionRelease);
    expect(cancelTradeRequest('trade-1').tradeId, 'trade-1');
    expect(cancelOrderRequest('order-1').payload, {'order_id': 'order-1'});
    expect(disputeRequest(tradeId: 'trade-1').payload, isNull);
  });

  test('a payout invoice cannot be the hold invoice', () {
    expect(invoiceError(''), 'Paste the payout invoice.');
    expect(
      invoiceError('hold-invoice', holdInvoice: 'hold-invoice'),
      'That is the hold invoice. Paste the invoice that should receive the CKB.',
    );
    expect(invoiceError('payout', holdInvoice: 'hold-invoice'), isNull);
    expect(myTradesRequest().action, actionMyTrades);
  });
}
