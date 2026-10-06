/// One line on a trade thread, kept on this device.
library;

import 'phase.dart';

/// A receipt image, after compression, has to fit in one relay event.
const maxReceiptBytes = 48000;

const maxChatText = 1000;

enum TradeNoteKind {
  text,
  paymentDetails,
  paymentProof,
  status;

  String get wire {
    switch (this) {
      case TradeNoteKind.text:
        return 'text';
      case TradeNoteKind.paymentDetails:
        return 'payment-details';
      case TradeNoteKind.paymentProof:
        return 'payment-proof';
      case TradeNoteKind.status:
        return 'status';
    }
  }

  static TradeNoteKind? parse(String value) {
    for (final kind in TradeNoteKind.values) {
      if (kind.wire == value) return kind;
    }
    return null;
  }
}

class TradeNote {
  const TradeNote({
    required this.id,
    required this.tradeId,
    required this.at,
    required this.kind,
    this.author,
    this.text,
    this.accountName,
    this.accountNumber,
    this.note,
    this.amount,
    this.bankReference,
    this.image,
  });

  final String id;
  final String tradeId;
  final DateTime at;
  final TradeNoteKind kind;
  final String? author;
  final String? text;
  final String? accountName;
  final String? accountNumber;
  final String? note;
  final String? amount;
  final String? bankReference;

  /// Compressed receipt, base64.
  final String? image;

  Map<String, Object?> toJson() {
    return {
      'id': id,
      'trade_id': tradeId,
      'at': at.toIso8601String(),
      'kind': kind.wire,
      'author': author,
      'text': text,
      'account_name': accountName,
      'account_number': accountNumber,
      'note': note,
      'amount': amount,
      'bank_reference': bankReference,
      'image': image,
    };
  }

  static TradeNote? fromJson(Object? value) {
    if (value is! Map) return null;
    final map = value.map((key, item) => MapEntry('$key', item));
    final id = _text(map, 'id');
    final tradeId = _text(map, 'trade_id');
    final at = DateTime.tryParse(_text(map, 'at') ?? '');
    final kind = TradeNoteKind.parse(_text(map, 'kind') ?? '');
    if (id == null || tradeId == null || at == null || kind == null) {
      return null;
    }
    return TradeNote(
      id: id,
      tradeId: tradeId,
      at: at,
      kind: kind,
      author: _optional(map, 'author'),
      text: _optional(map, 'text'),
      accountName: _optional(map, 'account_name'),
      accountNumber: _optional(map, 'account_number'),
      note: _optional(map, 'note'),
      amount: _optional(map, 'amount'),
      bankReference: _optional(map, 'bank_reference'),
      image: _optional(map, 'image'),
    );
  }
}

String? statusLine(TradePhase phase) {
  switch (phase) {
    case TradePhase.waitingFiat:
      return 'The hold is locked.';
    case TradePhase.fiatSent:
      return 'The buyer marked the fiat as sent.';
    case TradePhase.disputed:
      return 'A dispute is open.';
    case TradePhase.settled:
      return 'The seller released the hold.';
    case TradePhase.canceled:
      return 'The trade was canceled.';
    case TradePhase.expired:
      return 'The trade expired.';
    case TradePhase.refunding:
      return 'The hold is being refunded.';
    case TradePhase.waitingHold:
    case TradePhase.releasing:
    case TradePhase.awaitingInvoice:
      return null;
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
