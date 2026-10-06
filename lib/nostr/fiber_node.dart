import 'dart:convert';

import 'package:dart_nostr/dart_nostr.dart';

import '../constant.dart';
import 'verify.dart';

String? openFiberNode({
  required String daemonPublicKey,
  required NostrEvent event,
}) {
  if (event.kind != kindFiberNode) return null;
  if (!_tagged(event.tags, fiberNodeTag)) return null;
  if (!signedBy(event, daemonPublicKey)) return null;
  final content = event.content;
  if (content == null) return null;

  final Object? decoded;
  try {
    decoded = jsonDecode(content);
  } catch (_) {
    return null;
  }
  if (decoded is! Map) return null;
  final pubkey = decoded['pubkey'];
  if (pubkey is! String || pubkey.trim().isEmpty) return null;
  return pubkey.trim();
}

bool _tagged(List<List<String>>? tags, String identifier) {
  if (tags == null) return false;
  for (final tag in tags) {
    if (tag.length >= 2 && tag[0] == 'd' && tag[1] == identifier) return true;
  }
  return false;
}
