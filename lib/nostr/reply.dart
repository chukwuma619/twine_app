import '../constant.dart';
import '../market/clocks.dart';
import '../market/phase.dart';
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
  cantDo,
  trades;

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
      case replyTrades:
        return DaemonReply.trades;
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
    this.lockBy,
    this.holdEndsAt,
  });

  final String invoice;
  final String amountShannons;
  final String orderId;
  final String? sellerNostr;
  final String? buyerNostr;
  final DateTime? lockBy;
  final DateTime? holdEndsAt;

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
      lockBy: unixSeconds(map['lock_by']),
      holdEndsAt: unixSeconds(map['hold_ends_at']),
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
    this.payBy,
    this.releaseBy,
  });

  final String fiatAmount;
  final String fiatCurrency;
  final String reference;
  final String kind;
  final String label;
  final String currency;
  final String? sellerNostr;
  final String? buyerNostr;
  final DateTime? payBy;
  final DateTime? releaseBy;

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
      payBy: unixSeconds(map['pay_by']),
      releaseBy: unixSeconds(map['release_by']),
    );
  }
}

class Disputed {
  const Disputed({this.solver});

  final String? solver;

  static Disputed tryParse(Object? payload) {
    final map = _map(payload);
    if (map == null) return const Disputed();
    return Disputed(solver: _text(map, 'solver'));
  }
}

class TradeSnapshot {
  const TradeSnapshot({
    required this.tradeId,
    required this.orderId,
    required this.phase,
    required this.sellerNostr,
    required this.buyerNostr,
    required this.fiatAmount,
    required this.fiatCurrency,
    required this.amountShannons,
    this.paymentKind,
    this.paymentLabel,
    this.paymentCurrency,
    this.reference,
    this.holdInvoice,
    this.payoutInvoice,
    this.lockBy,
    this.holdEndsAt,
    this.payBy,
    this.releaseBy,
  });

  final String tradeId;
  final String orderId;
  final TradePhase phase;
  final String sellerNostr;
  final String buyerNostr;
  final String fiatAmount;
  final String fiatCurrency;
  final String amountShannons;
  final String? paymentKind;
  final String? paymentLabel;
  final String? paymentCurrency;
  final String? reference;
  final String? holdInvoice;
  final String? payoutInvoice;
  final DateTime? lockBy;
  final DateTime? holdEndsAt;
  final DateTime? payBy;
  final DateTime? releaseBy;

  static TradeSnapshot? tryParse(Object? value) {
    final map = _map(value);
    if (map == null) return null;
    final tradeId = _text(map, 'trade_id');
    final orderId = _text(map, 'order_id');
    final phase = TradePhase.parse(_text(map, 'state') ?? '');
    final seller = _text(map, 'seller_nostr');
    final buyer = _text(map, 'buyer_nostr');
    final fiatAmount = _text(map, 'fiat_amount');
    final fiatCurrency = _text(map, 'fiat_currency');
    final amount = _text(map, 'amount_shannons');
    if (tradeId == null ||
        orderId == null ||
        phase == null ||
        seller == null ||
        buyer == null ||
        fiatAmount == null ||
        fiatCurrency == null ||
        amount == null) {
      return null;
    }
    return TradeSnapshot(
      tradeId: tradeId,
      orderId: orderId,
      phase: phase,
      sellerNostr: seller,
      buyerNostr: buyer,
      fiatAmount: fiatAmount,
      fiatCurrency: fiatCurrency,
      amountShannons: amount,
      paymentKind: _text(map, 'payment_kind'),
      paymentLabel: _text(map, 'payment_label'),
      paymentCurrency: _text(map, 'payment_currency'),
      reference: _text(map, 'reference'),
      holdInvoice: _text(map, 'hold_invoice'),
      payoutInvoice: _text(map, 'payout_invoice'),
      lockBy: unixSeconds(map['lock_by']),
      holdEndsAt: unixSeconds(map['hold_ends_at']),
      payBy: unixSeconds(map['pay_by']),
      releaseBy: unixSeconds(map['release_by']),
    );
  }
}

class TradesReply {
  const TradesReply(this.trades);

  final List<TradeSnapshot> trades;

  static TradesReply? tryParse(Object? payload) {
    final map = _map(payload);
    if (map == null) return null;
    final raw = map['trades'];
    if (raw is! List) return null;
    final trades = <TradeSnapshot>[];
    for (final item in raw) {
      final snapshot = TradeSnapshot.tryParse(item);
      if (snapshot == null) return null;
      trades.add(snapshot);
    }
    return TradesReply(trades);
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
