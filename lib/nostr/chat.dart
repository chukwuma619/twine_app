import 'dart:convert';

import '../market/chat.dart';
import 'package:twine_app/src/rust/events.dart';

class ChatBody {
  const ChatBody({
    required this.tradeId,
    required this.kind,
    this.text,
    this.amount,
    this.image,
  });

  final String tradeId;
  final TradeNoteKind kind;
  final String? text;
  final String? amount;
  final String? image;

  String encode() {
    return jsonEncode({
      'v': 1,
      'trade_id': tradeId,
      'type': kind.wire,
      'text': text,
      'amount': amount,
      'image': image,
    });
  }

  static ChatBody? tryDecode(String plaintext) {
    final Object? decoded;
    try {
      decoded = jsonDecode(plaintext);
    } catch (_) {
      return null;
    }
    if (decoded is! Map) return null;
    final map = decoded.map((key, item) => MapEntry('$key', item));
    final tradeId = _text(map, 'trade_id');
    final kind = TradeNoteKind.parse(_text(map, 'type') ?? '');
    if (tradeId == null || kind == null || kind == TradeNoteKind.status) {
      return null;
    }
    return ChatBody(
      tradeId: tradeId,
      kind: kind,
      text: _optional(map, 'text'),
      amount: _optional(map, 'amount'),
      image: _optional(map, 'image'),
    );
  }

  TradeNote noteFor({
    required String id,
    required String author,
    required DateTime at,
  }) {
    return TradeNote(
      id: id,
      tradeId: tradeId,
      at: at,
      kind: kind,
      author: author,
      text: text,
      amount: amount,
      image: image,
    );
  }
}

class ChatEvent {
  const ChatEvent({
    required this.id,
    required this.author,
    required this.createdAt,
    required this.body,
  });

  final String id;
  final String author;
  final DateTime createdAt;
  final ChatBody body;

  static ChatEvent? fromDto(ChatDto dto) {
    final body = ChatBody.tryDecode(dto.bodyJson);
    if (body == null) return null;
    return ChatEvent(
      id: dto.id,
      author: dto.author,
      createdAt: DateTime.fromMillisecondsSinceEpoch(
        dto.createdAtSecs.toInt() * 1000,
        isUtc: true,
      ),
      body: body,
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
