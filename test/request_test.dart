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
      availableCkb: '10',
      fiatCurrency: 'NGN',
      pricePerCkb: '1500',
      min: '1000',
      max: '5000',
      methodIds: ['gtbank'],
    );

    expect(draft.validate(_catalog), isNull);
    final envelope = draft.envelope();
    expect(envelope.action, actionNewOrder);
    expect(envelope.payload, {
      'side': 'sell',
      'fiber_pubkey': '02abc',
      'available_ckb': '10',
      'fiat_currency': 'NGN',
      'price_per_ckb': '1500',
      'min': '1000',
      'max': '5000',
      'payment_methods': [
        {'method_id': 'gtbank'},
      ],
    });
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
    expect(
      fiatSentRequest(tradeId: 'trade-1', invoice: 'inv').tradeId,
      'trade-1',
    );
    expect(releaseRequest('trade-1').action, actionRelease);
    expect(cancelTradeRequest('trade-1').tradeId, 'trade-1');
    expect(cancelOrderRequest('order-1').payload, {'order_id': 'order-1'});
    expect(disputeRequest(tradeId: 'trade-1').payload, isNull);
  });
}
