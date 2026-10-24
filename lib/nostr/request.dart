import '../constant.dart';
import 'catalog.dart';
import 'envelope.dart';
import 'order.dart';

/// Smallest trade a sell post can allow, in CKB.
const minPostCkb = 100;

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
    final offered = double.parse(availableCkb.trim());
    final pricePerCkbValue = double.parse(pricePerCkb.trim());
    if (offered < minPostCkb) return 'Offer at least $minPostCkb CKB.';
    final minimumCkb = low / pricePerCkbValue;
    if (minimumCkb < minPostCkb) {
      return 'The minimum trade is $minPostCkb CKB.';
    }
    if (offered < minimumCkb) {
      return 'Offer enough CKB to cover the minimum trade.';
    }
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
    this.invoice,
    this.fiberAddr,
    this.requireInvoice = false,
  });

  final String orderId;
  final String fiatAmount;
  final String fiberPubkey;
  final String paymentMethodId;
  final String? invoice;
  final String? fiberAddr;
  final bool requireInvoice;

  String? validate() {
    if (orderId.trim().isEmpty) return 'That post is missing an id.';
    if (fiberPubkey.trim().isEmpty) return 'Enter your Fiber pubkey.';
    final amount = _amount(fiatAmount, 'the fiat amount');
    if (amount != null) return amount;
    if (paymentMethodId.trim().isEmpty) return 'Pick a payment method.';
    if (requireInvoice) {
      final payout = invoiceError(invoice ?? '');
      if (payout != null) return payout;
    }
    return fiberAddrError(fiberAddr);
  }

  TwineEnvelope envelope() {
    final payload = {
      'order_id': orderId.trim(),
      'fiat_amount': fiatAmount.trim(),
      'fiber_pubkey': fiberPubkey.trim(),
      'payment_method_id': paymentMethodId.trim(),
    };
    final payout = invoice?.trim();
    if (payout != null && payout.isNotEmpty) payload['invoice'] = payout;
    final addr = fiberAddr?.trim();
    if (addr != null && addr.isNotEmpty) payload['fiber_addr'] = addr;
    return TwineEnvelope(action: actionTake, payload: payload);
  }
}

TwineEnvelope payoutInvoiceRequest({
  required String tradeId,
  required String invoice,
  String? fiberAddr,
}) {
  return TwineEnvelope(
    action: actionPayoutInvoice,
    tradeId: tradeId,
    payload: {'invoice': invoice.trim(), ..._fiberAddr(fiberAddr)},
  );
}

TwineEnvelope fiatSentRequest({
  required String tradeId,
  required String invoice,
  String? fiberAddr,
}) {
  return TwineEnvelope(
    action: actionFiatSent,
    tradeId: tradeId,
    payload: {'invoice': invoice.trim(), ..._fiberAddr(fiberAddr)},
  );
}

Map<String, String> _fiberAddr(String? addr) {
  final trimmed = addr?.trim() ?? '';
  if (trimmed.isEmpty) return const {};
  return {'fiber_addr': trimmed};
}

String? fiberAddrError(String? addr) {
  final trimmed = addr?.trim() ?? '';
  if (trimmed.isEmpty) return null;
  if (!trimmed.startsWith('/')) {
    return 'Fiber listen address must be a multiaddr, like /ip4/1.2.3.4/tcp/8228.';
  }
  final lower = trimmed.toLowerCase();
  if (lower.contains('/ip4/127.') ||
      lower.contains('/ip4/10.') ||
      lower.contains('/ip4/192.168.') ||
      lower.contains('/ip4/0.0.0.0') ||
      lower.contains('/ip6/::1') ||
      lower.contains('/dns4/localhost') ||
      lower.contains('/dns/localhost') ||
      RegExp(r'/ip4/172\.(1[6-9]|2[0-9]|3[0-1])\.').hasMatch(lower)) {
    return 'That address is not reachable from Twine. Connect to this hub in Fiber Studio instead.';
  }
  return null;
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

TwineEnvelope myTradesRequest() {
  return const TwineEnvelope(action: actionMyTrades);
}

String? invoiceError(
  String invoice, {
  String? holdInvoice,
  bool allowEmpty = false,
}) {
  if (invoice.trim().isEmpty) {
    return allowEmpty ? null : 'Paste the payout invoice.';
  }
  final hold = holdInvoice?.trim();
  if (hold != null && hold.isNotEmpty && invoice.trim() == hold) {
    return 'That is the hold invoice. Paste the invoice that should receive the CKB.';
  }
  return null;
}

String? _amount(String raw, String label) {
  final value = raw.trim();
  if (!RegExp(r'^\d+(\.\d+)?$').hasMatch(value)) return 'Enter $label.';
  if (double.parse(value) == 0) return 'Enter $label.';
  return null;
}
