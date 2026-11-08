import 'package:currency_picker/currency_picker.dart';

import '../constant.dart';
import 'envelope.dart';
import 'order.dart';

/// Smallest trade a post can allow, in CKB.
const minPostCkb = 100;

class NewOrderDraft {
  const NewOrderDraft({
    required this.availableCkb,
    required this.fiatCurrency,
    required this.pricePerCkb,
    required this.min,
    required this.max,
  });

  final String availableCkb;
  final String fiatCurrency;
  final String pricePerCkb;
  final String min;
  final String max;

  String? validate() {
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
    final maximumCkb = high / pricePerCkbValue;
    if (maximumCkb > offered + 1e-9) {
      return 'The maximum exceeds the CKB available.';
    }
    final currency = fiatCurrency.trim();
    if (CurrencyService().findByCode(currency) == null) {
      return 'Pick a currency.';
    }
    return null;
  }

  TwineEnvelope envelope() {
    return TwineEnvelope(
      action: actionNewOrder,
      payload: {
        'side': 'sell',
        'available_ckb': availableCkb.trim(),
        'fiat_currency': fiatCurrency.trim(),
        'price_per_ckb': pricePerCkb.trim(),
        'min': min.trim(),
        'max': max.trim(),
      },
    );
  }
}

class TakeDraft {
  const TakeDraft({
    required this.orderId,
    required this.fiatAmount,
    this.invoice,
    this.requireInvoice = false,
  });

  final String orderId;
  final String fiatAmount;
  final String? invoice;
  final bool requireInvoice;

  String? validate({TwineOrder? order}) {
    if (orderId.trim().isEmpty) return 'That post is missing an id.';
    final amount = _amount(fiatAmount, 'the fiat amount');
    if (amount != null) return amount;
    if (order != null) {
      final fiat = double.tryParse(fiatAmount.trim());
      final min = double.tryParse(order.min.trim());
      final max = double.tryParse(order.max.trim());
      final price = double.tryParse(order.pricePerCkb.trim());
      final available = double.tryParse(order.availableCkb.trim());
      if (fiat != null && min != null && max != null) {
        if (fiat < min || fiat > max) {
          return 'Enter between ${order.min} and ${order.max} ${order.fiatCurrency}.';
        }
      }
      if (fiat != null &&
          price != null &&
          price > 0 &&
          available != null &&
          (fiat / price) > available + 1e-9) {
        return 'Only ${order.availableCkb} CKB is available on this post.';
      }
    }
    if (requireInvoice) {
      final payout = invoiceError(invoice ?? '');
      if (payout != null) return payout;
    }
    return null;
  }

  TwineEnvelope envelope() {
    final payload = {
      'order_id': orderId.trim(),
      'fiat_amount': fiatAmount.trim(),
    };
    final payout = invoice?.trim();
    if (payout != null && payout.isNotEmpty) payload['invoice'] = payout;
    return TwineEnvelope(action: actionTake, payload: payload);
  }
}

TwineEnvelope payoutInvoiceRequest({
  required String tradeId,
  required String invoice,
}) {
  return TwineEnvelope(
    action: actionPayoutInvoice,
    tradeId: tradeId,
    payload: {'invoice': invoice.trim()},
  );
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
  List<String> solverEvidence = const [],
}) {
  final payload = <String, Object>{};
  final payout = invoice?.trim();
  if (payout != null && payout.isNotEmpty) payload['invoice'] = payout;
  if (solverEvidence.isNotEmpty) payload['solver_evidence'] = solverEvidence;
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
