/// Checks that a Nostr event was signed by the key it claims.
library;

import 'package:dart_nostr/dart_nostr.dart';

/// True when [event] was signed by [publicKey] and its id matches the body.
bool signedBy(NostrEvent event, String publicKey) {
  final kind = event.kind;
  final content = event.content;
  final id = event.id;
  final createdAt = event.createdAt;
  if (kind == null || content == null || id == null || createdAt == null) {
    return false;
  }
  if (event.pubkey.toLowerCase() != publicKey.toLowerCase()) return false;
  final expectedId = NostrEvent.getEventId(
    kind: kind,
    content: content,
    createdAt: createdAt,
    tags: event.tags ?? const [],
    pubkey: event.pubkey,
  );
  return expectedId == id && event.isVerified();
}
