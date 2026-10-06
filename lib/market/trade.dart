/// One trade, as far as this device has heard from the daemon.
library;

import 'phase.dart';

class TwineTrade {
  const TwineTrade({
    required this.id,
    required this.orderId,
    required this.phase,
    required this.updatedAt,
    this.holdInvoice,
    this.amountShannons,
    this.fiatAmount,
    this.fiatCurrency,
    this.paymentKind,
    this.paymentLabel,
    this.paymentCurrency,
    this.reference,
    this.payoutFailure,
    this.notice,
    this.releaseFrom,
  });

  final String id;
  final String orderId;
  final TradePhase phase;
  final DateTime updatedAt;
  final String? holdInvoice;
  final String? amountShannons;
  final String? fiatAmount;
  final String? fiatCurrency;
  final String? paymentKind;
  final String? paymentLabel;
  final String? paymentCurrency;
  final String? reference;
  final String? payoutFailure;
  final String? notice;

  /// Phase to restore when a release is refused.
  final TradePhase? releaseFrom;

  TwineTrade copyWith({
    String? orderId,
    TradePhase? phase,
    DateTime? updatedAt,
    String? holdInvoice,
    String? amountShannons,
    String? fiatAmount,
    String? fiatCurrency,
    String? paymentKind,
    String? paymentLabel,
    String? paymentCurrency,
    String? reference,
    String? payoutFailure,
    bool keepPayoutFailure = true,
    String? notice,
    bool keepNotice = true,
    TradePhase? releaseFrom,
    bool keepReleaseFrom = true,
  }) {
    return TwineTrade(
      id: id,
      orderId: orderId ?? this.orderId,
      phase: phase ?? this.phase,
      updatedAt: updatedAt ?? this.updatedAt,
      holdInvoice: holdInvoice ?? this.holdInvoice,
      amountShannons: amountShannons ?? this.amountShannons,
      fiatAmount: fiatAmount ?? this.fiatAmount,
      fiatCurrency: fiatCurrency ?? this.fiatCurrency,
      paymentKind: paymentKind ?? this.paymentKind,
      paymentLabel: paymentLabel ?? this.paymentLabel,
      paymentCurrency: paymentCurrency ?? this.paymentCurrency,
      reference: reference ?? this.reference,
      payoutFailure: keepPayoutFailure
          ? (payoutFailure ?? this.payoutFailure)
          : payoutFailure,
      notice: keepNotice ? (notice ?? this.notice) : notice,
      releaseFrom: keepReleaseFrom
          ? (releaseFrom ?? this.releaseFrom)
          : releaseFrom,
    );
  }

  Map<String, Object?> toJson() {
    return {
      'id': id,
      'order_id': orderId,
      'phase': phase.wire,
      'updated_at': updatedAt.toIso8601String(),
      'hold_invoice': holdInvoice,
      'amount_shannons': amountShannons,
      'fiat_amount': fiatAmount,
      'fiat_currency': fiatCurrency,
      'payment_kind': paymentKind,
      'payment_label': paymentLabel,
      'payment_currency': paymentCurrency,
      'reference': reference,
      'payout_failure': payoutFailure,
      'notice': notice,
      'release_from': releaseFrom?.wire,
    };
  }

  static TwineTrade? fromJson(Object? value) {
    if (value is! Map) return null;
    final map = value.map((key, item) => MapEntry('$key', item));
    final id = _text(map, 'id');
    final orderId = _text(map, 'order_id') ?? '';
    final phase = TradePhase.parse(_text(map, 'phase') ?? '');
    final updatedAt = DateTime.tryParse(_text(map, 'updated_at') ?? '');
    if (id == null || phase == null || updatedAt == null) return null;
    return TwineTrade(
      id: id,
      orderId: orderId,
      phase: phase,
      updatedAt: updatedAt,
      holdInvoice: _optional(map, 'hold_invoice'),
      amountShannons: _optional(map, 'amount_shannons'),
      fiatAmount: _optional(map, 'fiat_amount'),
      fiatCurrency: _optional(map, 'fiat_currency'),
      paymentKind: _optional(map, 'payment_kind'),
      paymentLabel: _optional(map, 'payment_label'),
      paymentCurrency: _optional(map, 'payment_currency'),
      reference: _optional(map, 'reference'),
      payoutFailure: _optional(map, 'payout_failure'),
      notice: _optional(map, 'notice'),
      releaseFrom: TradePhase.parse(_text(map, 'release_from') ?? ''),
    );
  }
}

String? _text(Map<String, Object?> map, String key) {
  final value = map[key];
  if (value is! String) return null;
  final trimmed = value.trim();
  if (trimmed.isEmpty) return null;
  return trimmed;
}

String? _optional(Map<String, Object?> map, String key) {
  if (!map.containsKey(key) || map[key] == null) return null;
  return _text(map, key);
}
