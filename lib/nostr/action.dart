import 'package:dart_nostr/dart_nostr.dart';

import '../constant.dart';
import 'account.dart';
import 'envelope.dart';
import 'nip44.dart';
import 'verify.dart';

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
  if (!_addressedTo(tags, recipient.publicKey)) return null;
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
