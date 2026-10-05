import 'dart:convert';

import 'package:dart_nostr/dart_nostr.dart';

import 'account.dart';
import 'nip44.dart';

/// Kind of an encrypted action or reply. The `p` tag is the recipient.
const kindAction = 4242;

/// JSON envelope the daemon already parses: `{ action, trade_id?, payload? }`.
class TwineEnvelope {
  const TwineEnvelope({required this.action, this.tradeId, this.payload});

  final String action;
  final String? tradeId;
  final Object? payload;

  String encode() {
    final body = <String, Object>{'action': action};
    final trade = tradeId;
    if (trade != null) body['trade_id'] = trade;
    final extra = payload;
    if (extra != null) body['payload'] = extra;
    return jsonEncode(body);
  }

  static TwineEnvelope? tryDecode(String json) {
    final Object? decoded;
    try {
      decoded = jsonDecode(json);
    } catch (_) {
      return null;
    }
    if (decoded is! Map) return null;
    final action = decoded['action'];
    if (action is! String || action.isEmpty) return null;
    final tradeId = decoded['trade_id'];
    if (tradeId != null && tradeId is! String) return null;
    return TwineEnvelope(
      action: action,
      tradeId: tradeId as String?,
      payload: decoded['payload'],
    );
  }
}

/// Signs a kind-4242 event encrypted to [recipientPublicKey].
NostrEvent sealAction({
  required TwineAccount sender,
  required String recipientPublicKey,
  required TwineEnvelope envelope,
  DateTime? createdAt,
}) {
  final ciphertext = nip44Encrypt(
    secretKey: sender.privateKey,
    publicKey: recipientPublicKey,
    plaintext: envelope.encode(),
  );
  return NostrEvent.fromPartialData(
    kind: kindAction,
    content: ciphertext,
    keyPairs: NostrKeyPairs(private: sender.privateKey),
    tags: [
      ['p', recipientPublicKey],
    ],
    createdAt: createdAt,
  );
}

/// Decrypts a reply from [senderPublicKey]. Returns null when the author,
/// signature, address, or ciphertext is not that sender writing to [recipient].
TwineEnvelope? openReply({
  required TwineAccount recipient,
  required String senderPublicKey,
  required NostrEvent event,
}) {
  final kind = event.kind;
  final content = event.content;
  final id = event.id;
  final createdAt = event.createdAt;
  final tags = event.tags;
  if (kind != kindAction ||
      content == null ||
      id == null ||
      createdAt == null) {
    return null;
  }
  if (event.pubkey.toLowerCase() != senderPublicKey.toLowerCase()) return null;
  if (!_addressedTo(tags, recipient.publicKey)) return null;

  final expectedId = NostrEvent.getEventId(
    kind: kind!,
    content: content,
    createdAt: createdAt,
    tags: tags ?? const [],
    pubkey: event.pubkey,
  );
  if (expectedId != id || !event.isVerified()) return null;

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
  return TwineEnvelope.tryDecode(plaintext);
}

bool _addressedTo(List<List<String>>? tags, String publicKey) {
  if (tags == null) return false;
  final wanted = publicKey.toLowerCase();
  for (final tag in tags) {
    if (tag.length >= 2 && tag[0] == 'p' && tag[1].toLowerCase() == wanted) {
      return true;
    }
  }
  return false;
}
