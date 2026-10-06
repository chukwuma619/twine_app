/// Actions the app seals and sends to the daemon.
library;

import '../constant.dart';
import 'catalog.dart';
import 'envelope.dart';
import 'order.dart';

class NewOrderDraft {
  const NewOrderDraft({
    required this.side,
    required this.fiberPubkey,
    required this.availableCkb,
    required this.fiatCurrency,
    required this.pricePerCkb,
    required this.min,
    required this.max,
    required this.methodIds,
  });

  final OrderSide side;
  final String fiberPubkey;
  final String availableCkb;
  final String fiatCurrency;
  final String pricePerCkb;
  final String min;
  final String max;
  final List<String> methodIds;

  String? validate(List<CatalogMethod> catalog) {
    if (fiberPubkey.trim().isEmpty) return 'Enter your Fiber pubkey.';
    final available = _amount(availableCkb, 'how much CKB this post covers');
    if (available != null) return available;
    final price = _amount(pricePerCkb, 'a price per CKB');
    if (price != null) return price;
    final minimum = _amount(min, 'a minimum');
    if (minimum != null) return minimum;
    final maximum = _amount(max, 'a maximum');
    if (maximum != null) return maximum;
    final low = double.parse(min.trim());
    final high = double.parse(max.trim());
    if (low > high) return 'The minimum is above the maximum.';
    final known = methodsForCurrency(catalog, fiatCurrency.trim());
    if (known.isEmpty) return 'Pick a currency this daemon accepts.';
    if (methodIds.isEmpty ||
        methodIds.any((id) => !known.any((method) => method.id == id))) {
      return 'Pick a payment method.';
    }
    return null;
  }

  TwineEnvelope envelope() {
    return TwineEnvelope(
      action: actionNewOrder,
      payload: {
        'side': side.wire,
        'fiber_pubkey': fiberPubkey.trim(),
        'available_ckb': availableCkb.trim(),
        'fiat_currency': fiatCurrency.trim(),
        'price_per_ckb': pricePerCkb.trim(),
        'min': min.trim(),
        'max': max.trim(),
        'payment_methods': [
          for (final id in methodIds) {'method_id': id},
        ],
      },
    );
  }
}

class TakeDraft {
  const TakeDraft({
    required this.orderId,
    required this.fiatAmount,
    required this.fiberPubkey,
    required this.paymentMethodId,
  });

  final String orderId;
  final String fiatAmount;
  final String fiberPubkey;
  final String paymentMethodId;

  String? validate() {
    if (orderId.trim().isEmpty) return 'That post is missing an id.';
    if (fiberPubkey.trim().isEmpty) return 'Enter your Fiber pubkey.';
    final amount = _amount(fiatAmount, 'the fiat amount');
    if (amount != null) return amount;
    if (paymentMethodId.trim().isEmpty) return 'Pick a payment method.';
    return null;
  }

  TwineEnvelope envelope() {
    return TwineEnvelope(
      action: actionTake,
      payload: {
        'order_id': orderId.trim(),
        'fiat_amount': fiatAmount.trim(),
        'fiber_pubkey': fiberPubkey.trim(),
        'payment_method_id': paymentMethodId.trim(),
      },
    );
  }
}

TwineEnvelope fiatSentRequest({
  required String tradeId,
  required String invoice,
}) {
  return TwineEnvelope(
    action: actionFiatSent,
    tradeId: tradeId,
    payload: {'invoice': invoice.trim()},
  );
}

TwineEnvelope releaseRequest(String tradeId) {
  return TwineEnvelope(action: actionRelease, tradeId: tradeId);
}

TwineEnvelope cancelTradeRequest(String tradeId) {
  return TwineEnvelope(action: actionCancel, tradeId: tradeId);
}

TwineEnvelope cancelOrderRequest(String orderId) {
  return TwineEnvelope(action: actionCancel, payload: {'order_id': orderId});
}

TwineEnvelope disputeRequest({
  required String tradeId,
  String? invoice,
  String? conversationKey,
}) {
  final payload = <String, String>{};
  final payout = invoice?.trim();
  if (payout != null && payout.isNotEmpty) payload['invoice'] = payout;
  final key = conversationKey?.trim();
  if (key != null && key.isNotEmpty) payload['conversation_key'] = key;
  return TwineEnvelope(
    action: actionDispute,
    tradeId: tradeId,
    payload: payload.isEmpty ? null : payload,
  );
}

String? invoiceError(String invoice) {
  if (invoice.trim().isEmpty) return 'Paste the payout invoice.';
  return null;
}

String? _amount(String raw, String label) {
  final value = raw.trim();
  if (!RegExp(r'^\d+(\.\d+)?$').hasMatch(value)) return 'Enter $label.';
  if (double.parse(value) == 0) return 'Enter $label.';
  return null;
}
