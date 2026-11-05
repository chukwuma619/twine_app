import 'package:flutter_test/flutter_test.dart';
import 'package:twine_app/constant.dart';
import 'package:twine_app/nostr/order.dart';
import 'package:twine_app/nostr/request.dart';

void main() {
  test('a post names the side and the amounts', () {
    const draft = NewOrderDraft(
      side: OrderSide.sell,
      availableCkb: '200',
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
      'available_ckb': '200',
      'fiat_currency': 'NGN',
      'price_per_ckb': '1500',
      'min': '150000',
      'max': '300000',
    });
  });

  test('a post accepts any currency in the picker', () {
    const euro = NewOrderDraft(
      side: OrderSide.sell,
      availableCkb: '200',
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
      availableCkb: '200',
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

  test('a post whose maximum exceeds the offered CKB is refused', () {
    const draft = NewOrderDraft(
      side: OrderSide.sell,
      availableCkb: '100',
      fiatCurrency: 'NGN',
      pricePerCkb: '1500',
      min: '150000',
      max: '300000',
    );
    expect(draft.validate(), 'The maximum exceeds the CKB available.');
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

  test('a take checks the order min, max, and remaining CKB', () {
    final order = TwineOrder(
      orderId: 'order-1',
      makerNostrPubkey: 'a' * 64,
      side: OrderSide.sell,
      availableCkb: '150',
      fiatCurrency: 'NGN',
      pricePerCkb: '1500',
      min: '150000',
      max: '300000',
      holdHours: 24,
      updatedAt: DateTime.utc(2026),
    );

    const belowMin = TakeDraft(orderId: 'order-1', fiatAmount: '100000');
    expect(
      belowMin.validate(order: order),
      'Enter between 150000 and 300000 NGN.',
    );

    const aboveMax = TakeDraft(orderId: 'order-1', fiatAmount: '350000');
    expect(
      aboveMax.validate(order: order),
      'Enter between 150000 and 300000 NGN.',
    );

    const exceedsAvailable = TakeDraft(
      orderId: 'order-1',
      fiatAmount: '250000',
    );
    expect(
      exceedsAvailable.validate(order: order),
      'Only 150 CKB is available on this post.',
    );

    const withinBounds = TakeDraft(orderId: 'order-1', fiatAmount: '200000');
    expect(withinBounds.validate(order: order), isNull);
  });
}
