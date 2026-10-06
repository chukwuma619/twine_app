/// A decrypted reply from the daemon, and the payloads those replies carry.
library;

import '../constant.dart';
import 'envelope.dart';

class DaemonReplyEvent {
  const DaemonReplyEvent({required this.envelope, required this.createdAt});

  final TwineEnvelope envelope;
  final DateTime createdAt;
}

enum DaemonReply {
  payInvoice,
  waitingFiat,
  fiatSentOk,
  newInvoice,
  disputed,
  refunding,
  settled,
  canceled,
  expired,
  cantDo;

  static DaemonReply? parse(String action) {
    switch (action) {
      case replyPayInvoice:
        return DaemonReply.payInvoice;
      case replyWaitingFiat:
        return DaemonReply.waitingFiat;
      case replyFiatSentOk:
        return DaemonReply.fiatSentOk;
      case replyNewInvoice:
        return DaemonReply.newInvoice;
      case replyDisputed:
        return DaemonReply.disputed;
      case replyRefunding:
        return DaemonReply.refunding;
      case replySettled:
        return DaemonReply.settled;
      case replyCanceled:
        return DaemonReply.canceled;
      case replyExpired:
        return DaemonReply.expired;
      case replyCantDo:
        return DaemonReply.cantDo;
      default:
        return null;
    }
  }
}

class PayInvoice {
  const PayInvoice({
    required this.invoice,
    required this.amountShannons,
    required this.orderId,
    this.sellerNostr,
    this.buyerNostr,
  });

  final String invoice;
  final String amountShannons;
  final String orderId;
  final String? sellerNostr;
  final String? buyerNostr;

  static PayInvoice? tryParse(Object? payload) {
    final map = _map(payload);
    if (map == null) return null;
    final invoice = _text(map, 'invoice');
    final amount = _text(map, 'amount_shannons');
    final orderId = _text(map, 'order_id');
    if (invoice == null || amount == null || orderId == null) return null;
    final parties = _parties(map);
    return PayInvoice(
      invoice: invoice,
      amountShannons: amount,
      orderId: orderId,
      sellerNostr: parties?.$1,
      buyerNostr: parties?.$2,
    );
  }
}

class WaitingFiat {
  const WaitingFiat({
    required this.fiatAmount,
    required this.fiatCurrency,
    required this.reference,
    required this.kind,
    required this.label,
    required this.currency,
    this.sellerNostr,
    this.buyerNostr,
  });

  final String fiatAmount;
  final String fiatCurrency;
  final String reference;
  final String kind;
  final String label;
  final String currency;
  final String? sellerNostr;
  final String? buyerNostr;

  static WaitingFiat? tryParse(Object? payload) {
    final map = _map(payload);
    if (map == null) return null;
    final fiatAmount = _text(map, 'fiat_amount');
    final fiatCurrency = _text(map, 'fiat_currency');
    final reference = _text(map, 'reference');
    final kind = _text(map, 'kind');
    final label = _text(map, 'label');
    final currency = _text(map, 'currency');
    if (fiatAmount == null ||
        fiatCurrency == null ||
        reference == null ||
        kind == null ||
        label == null ||
        currency == null) {
      return null;
    }
    final parties = _parties(map);
    return WaitingFiat(
      fiatAmount: fiatAmount,
      fiatCurrency: fiatCurrency,
      reference: reference,
      kind: kind,
      label: label,
      currency: currency,
      sellerNostr: parties?.$1,
      buyerNostr: parties?.$2,
    );
  }
}

class ReasonPayload {
  const ReasonPayload(this.reason);

  final String reason;

  static ReasonPayload? tryParse(Object? payload) {
    final map = _map(payload);
    if (map == null) return null;
    final reason = _text(map, 'reason');
    if (reason == null) return null;
    return ReasonPayload(reason);
  }
}

Map<String, Object?>? _map(Object? value) {
  if (value is! Map) return null;
  return value.map((key, item) => MapEntry('$key', item));
}

(String, String)? _parties(Map<String, Object?> map) {
  final seller = _text(map, 'seller_nostr');
  final buyer = _text(map, 'buyer_nostr');
  if (seller == null || buyer == null) return null;
  return (seller, buyer);
}

String? _text(Map<String, Object?> map, String key) {
  final value = map[key];
  if (value is! String) return null;
  final trimmed = value.trim();
  if (trimmed.isEmpty) return null;
  return trimmed;
}
