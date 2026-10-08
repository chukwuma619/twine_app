import 'dart:convert';

import 'package:dart_nostr/dart_nostr.dart';

import '../constant.dart';
import 'verify.dart';

enum PostStatus {
  open,
  canceled;

  String get wire {
    switch (this) {
      case PostStatus.open:
        return 'open';
      case PostStatus.canceled:
        return 'canceled';
    }
  }

  static PostStatus? parse(String value) {
    switch (value) {
      case 'open':
        return PostStatus.open;
      case 'canceled':
        return PostStatus.canceled;
      default:
        return null;
    }
  }
}

enum OrderSide {
  sell,
  buy;

  String get wire {
    switch (this) {
      case OrderSide.sell:
        return 'sell';
      case OrderSide.buy:
        return 'buy';
    }
  }

  String get label {
    switch (this) {
      case OrderSide.sell:
        return 'Sell';
      case OrderSide.buy:
        return 'Buy';
    }
  }

  static OrderSide? parse(String value) {
    switch (value) {
      case 'sell':
        return OrderSide.sell;
      case 'buy':
        return OrderSide.buy;
      default:
        return null;
    }
  }
}

class TwinePaymentMethod {
  const TwinePaymentMethod({
    required this.id,
    required this.kind,
    required this.label,
    required this.currency,
  });

  final String id;
  final String kind;
  final String label;
  final String currency;

  static TwinePaymentMethod? tryParse(Object? value) {
    final map = _map(value);
    if (map == null) return null;
    final id = _text(map, 'id');
    final kind = _text(map, 'kind');
    final label = _text(map, 'label');
    final currency = _text(map, 'currency');
    if (id == null || kind == null || label == null || currency == null) {
      return null;
    }
    return TwinePaymentMethod(
      id: id,
      kind: kind,
      label: label,
      currency: currency,
    );
  }
}

class TwineOrder {
  const TwineOrder({
    required this.orderId,
    required this.side,
    required this.makerNostrPubkey,
    required this.makerFiberPubkey,
    required this.availableCkb,
    required this.fiatCurrency,
    required this.pricePerCkb,
    required this.min,
    required this.max,
    required this.paymentMethods,
    required this.holdHours,
    required this.updatedAt,
    this.status = PostStatus.open,
    this.reservedCkb,
  });

  final String orderId;
  final OrderSide side;
  final String makerNostrPubkey;
  final String makerFiberPubkey;
  final String availableCkb;
  final String fiatCurrency;
  final String pricePerCkb;
  final String min;
  final String max;
  final List<TwinePaymentMethod> paymentMethods;
  final int holdHours;
  final DateTime updatedAt;
  final PostStatus status;
  final String? reservedCkb;

  bool get hasReserved {
    final value = double.tryParse(reservedCkb ?? '');
    if (value == null) return false;
    return value > 0;
  }

  TwineOrder copyWith({PostStatus? status, String? reservedCkb}) {
    return TwineOrder(
      orderId: orderId,
      side: side,
      makerNostrPubkey: makerNostrPubkey,
      makerFiberPubkey: makerFiberPubkey,
      availableCkb: availableCkb,
      fiatCurrency: fiatCurrency,
      pricePerCkb: pricePerCkb,
      min: min,
      max: max,
      paymentMethods: paymentMethods,
      holdHours: holdHours,
      updatedAt: updatedAt,
      status: status ?? this.status,
      reservedCkb: reservedCkb ?? this.reservedCkb,
    );
  }

  bool get hasCkb {
    final value = double.tryParse(availableCkb);
    if (value == null) return true;
    return value > 0;
  }

  static TwineOrder? open({
    required String daemonPublicKey,
    required NostrEvent event,
  }) {
    if (event.kind != kindOrder) return null;
    if (!signedBy(event, daemonPublicKey)) return null;
    final createdAt = event.createdAt;
    final content = event.content;
    if (createdAt == null || content == null) return null;
    final identifier = _identifier(event.tags);
    if (identifier == null) return null;

    final Object? decoded;
    try {
      decoded = jsonDecode(content);
    } catch (_) {
      return null;
    }
    final order = tryParse(decoded, updatedAt: createdAt);
    if (order == null || order.orderId != identifier) return null;
    return order;
  }

  static TwineOrder? tryParse(Object? value, {required DateTime updatedAt}) {
    final map = _map(value);
    if (map == null) return null;
    final orderId = _text(map, 'order_id');
    final side = OrderSide.parse(_text(map, 'side') ?? '');
    final makerNostr = _text(map, 'maker_nostr_pubkey');
    final makerFiber = _text(map, 'maker_fiber_pubkey');
    final available = _text(map, 'available_ckb');
    final currency = _text(map, 'fiat_currency');
    final price = _text(map, 'price_per_ckb');
    final min = _text(map, 'min');
    final max = _text(map, 'max');
    final holdHours = _hours(map['hold_hours']);
    final methods = _methods(map['payment_methods']);
    final status = map.containsKey('status')
        ? PostStatus.parse(_text(map, 'status') ?? '')
        : PostStatus.open;
    if (orderId == null ||
        side == null ||
        makerNostr == null ||
        makerFiber == null ||
        available == null ||
        currency == null ||
        price == null ||
        min == null ||
        max == null ||
        holdHours == null ||
        methods == null ||
        status == null) {
      return null;
    }
    return TwineOrder(
      orderId: orderId,
      side: side,
      makerNostrPubkey: makerNostr,
      makerFiberPubkey: makerFiber,
      availableCkb: available,
      fiatCurrency: currency,
      pricePerCkb: price,
      min: min,
      max: max,
      paymentMethods: methods,
      holdHours: holdHours,
      updatedAt: updatedAt,
      status: status,
      reservedCkb: _text(map, 'reserved_ckb'),
    );
  }

  Map<String, Object?> toJson() {
    return {
      'order_id': orderId,
      'side': side.wire,
      'maker_nostr_pubkey': makerNostrPubkey,
      'maker_fiber_pubkey': makerFiberPubkey,
      'available_ckb': availableCkb,
      'fiat_currency': fiatCurrency,
      'price_per_ckb': pricePerCkb,
      'min': min,
      'max': max,
      'payment_methods': [
        for (final method in paymentMethods)
          {
            'id': method.id,
            'kind': method.kind,
            'label': method.label,
            'currency': method.currency,
          },
      ],
      'hold_hours': holdHours,
      'status': status.wire,
      'updated_at': updatedAt.toIso8601String(),
      'reserved_ckb': reservedCkb,
    };
  }

  static TwineOrder? fromJson(Object? value) {
    final map = _map(value);
    if (map == null) return null;
    final updatedAt = DateTime.tryParse(_text(map, 'updated_at') ?? '');
    if (updatedAt == null) return null;
    return tryParse(value, updatedAt: updatedAt);
  }
}

Map<String, Object?>? _map(Object? value) {
  if (value is! Map) return null;
  return value.map((key, item) => MapEntry('$key', item));
}

String? _text(Map<String, Object?> map, String key) {
  final value = map[key];
  if (value is! String) return null;
  final trimmed = value.trim();
  if (trimmed.isEmpty) return null;
  return trimmed;
}

int? _hours(Object? value) {
  if (value is int && value > 0) return value;
  if (value is num && value > 0 && value == value.roundToDouble()) {
    return value.toInt();
  }
  return null;
}

List<TwinePaymentMethod>? _methods(Object? value) {
  if (value is! List || value.isEmpty) return null;
  final methods = <TwinePaymentMethod>[];
  for (final item in value) {
    final method = TwinePaymentMethod.tryParse(item);
    if (method == null) return null;
    methods.add(method);
  }
  return methods;
}

String? _identifier(List<List<String>>? tags) {
  if (tags == null) return null;
  for (final tag in tags) {
    if (tag.length >= 2 && tag[0] == 'd' && tag[1].isNotEmpty) return tag[1];
  }
  return null;
}
