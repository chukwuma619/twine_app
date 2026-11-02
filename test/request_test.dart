import 'package:flutter_test/flutter_test.dart';
import 'package:twine_app/constant.dart';
import 'package:twine_app/nostr/order.dart';
import 'package:twine_app/nostr/request.dart';

void main() {
  test('a post names the side and the amounts', () {
    const draft = NewOrderDraft(
      side: OrderSide.sell,
      availableCkb: '100',
      fiatCurrency: 'NGN',
      pricePerCkb: '1500',
      min: '150000',
      max: '300000',
    );

    expect(draft.validate(), isNull);
    final envelope = draft.envelope();
    expect(envelope.action, actionNewOrder);
    expect(envelope.payload, {
      'side': 'sell',
      'available_ckb': '100',
      'fiat_currency': 'NGN',
      'price_per_ckb': '1500',
      'min': '150000',
      'max': '300000',
    });
  });

  test('a post accepts any currency in the picker', () {
    const euro = NewOrderDraft(
      side: OrderSide.sell,
      availableCkb: '100',
      fiatCurrency: 'EUR',
      pricePerCkb: '1500',
      min: '150000',
      max: '300000',
    );
    expect(euro.validate(), isNull);
    final payload = euro.envelope().payload as Map;
    expect(payload['fiat_currency'], 'EUR');

    const unknown = NewOrderDraft(
      side: OrderSide.sell,
      availableCkb: '100',
      fiatCurrency: 'NOTACOIN',
      pricePerCkb: '1500',
      min: '150000',
      max: '300000',
    );
    expect(unknown.validate(), 'Pick a currency.');
  });

  test('a post whose smallest trade is under 100 CKB is refused', () {
    const draft = NewOrderDraft(
      side: OrderSide.sell,
      availableCkb: '120',
      fiatCurrency: 'NGN',
      pricePerCkb: '1500',
      min: '3000',
      max: '180000',
    );
    expect(draft.validate(), 'The minimum trade is 100 CKB.');
  });

  test('a post with the minimum above the maximum is refused', () {
    const draft = NewOrderDraft(
      side: OrderSide.buy,
      availableCkb: '1',
      fiatCurrency: 'USD',
      pricePerCkb: '1',
      min: '20',
      max: '10',
    );
    expect(draft.validate(), 'The minimum is above the maximum.');
  });

  test('a take names the post and the amount', () {
    const draft = TakeDraft(orderId: 'order-1', fiatAmount: '2500');
    expect(draft.validate(), isNull);
    expect(draft.envelope().action, actionTake);
    expect(draft.envelope().payload, {
      'order_id': 'order-1',
      'fiat_amount': '2500',
    });
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
