import 'dart:convert';

import 'package:dart_nostr/dart_nostr.dart';

import '../constant.dart';
import '../market/chat.dart';
import 'account.dart';
import 'nip44.dart';
import 'verify.dart';

class ChatBody {
  const ChatBody({
    required this.tradeId,
    required this.kind,
    this.text,
    this.accountName,
    this.accountNumber,
    this.note,
    this.amount,
    this.bankReference,
    this.image,
  });

  final String tradeId;
  final TradeNoteKind kind;
  final String? text;
  final String? accountName;
  final String? accountNumber;
  final String? note;
  final String? amount;
  final String? bankReference;
  final String? image;

  String encode() {
    return jsonEncode({
      'v': 1,
      'trade_id': tradeId,
      'type': kind.wire,
      'text': text,
      'account_name': accountName,
      'account_number': accountNumber,
      'note': note,
      'amount': amount,
      'bank_reference': bankReference,
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
      accountName: _optional(map, 'account_name'),
      accountNumber: _optional(map, 'account_number'),
      note: _optional(map, 'note'),
      amount: _optional(map, 'amount'),
      bankReference: _optional(map, 'bank_reference'),
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
      accountName: accountName,
      accountNumber: accountNumber,
      note: note,
      amount: amount,
      bankReference: bankReference,
      image: image,
    );
  }
}

NostrEvent sealChat({
  required TwineAccount sender,
  required String peer,
  required ChatBody body,
  DateTime? createdAt,
}) {
  final ciphertext = nip44Encrypt(
    secretKey: sender.privateKey,
    publicKey: peer,
    plaintext: body.encode(),
  );
  return NostrEvent.fromPartialData(
    kind: kindChat,
    content: ciphertext,
    keyPairs: NostrKeyPairs(private: sender.privateKey),
    tags: [
      ['p', peer],
      ['t', body.tradeId],
    ],
    createdAt: createdAt,
  );
}

ChatBody? openChat({
  required TwineAccount recipient,
  required String senderPublicKey,
  required NostrEvent event,
}) {
  final kind = event.kind;
  final content = event.content;
  final id = event.id;
  final createdAt = event.createdAt;
  final tags = event.tags;
  if (kind != kindChat || content == null || id == null || createdAt == null) {
    return null;
  }
  if (!_tagged(tags, 'p', recipient.publicKey)) return null;
  if (!signedBy(event, senderPublicKey)) return null;

  final String plaintext;
  try {
    plaintext = nip44Decrypt(
      secretKey: recipient.privateKey,
      publicKey: senderPublicKey,
      payload: content,
    );
  } on Nip44Exception {
    return null;
  }
  final body = ChatBody.tryDecode(plaintext);
  if (body == null) return null;
  if (!_tagged(tags, 't', body.tradeId)) return null;
  return body;
}

bool _tagged(List<List<String>>? tags, String name, String value) {
  if (tags == null) return false;
  final wanted = value.toLowerCase();
  for (final tag in tags) {
    if (tag.length >= 2 && tag[0] == name && tag[1].toLowerCase() == wanted) {
      return true;
    }
  }
  return false;
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
