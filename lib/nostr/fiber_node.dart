import 'dart:convert';

import 'package:dart_nostr/dart_nostr.dart';

import '../constant.dart';
import 'verify.dart';

class FiberAnnouncement {
  const FiberAnnouncement({
    required this.pubkey,
    required this.hasSolverField,
    this.solver,
  });

  final String pubkey;
  final bool hasSolverField;
  final String? solver;

  bool get solverConfigured => solver != null && solver!.isNotEmpty;
}

FiberAnnouncement? openFiberAnnouncement({
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
  final map = decoded.map((key, item) => MapEntry('$key', item));
  final pubkey = map['pubkey'];
  if (pubkey is! String || pubkey.trim().isEmpty) return null;
  final hasSolverField = map.containsKey('solver');
  final rawSolver = map['solver'];
  final String? solver;
  if (rawSolver is String && rawSolver.trim().isNotEmpty) {
    solver = rawSolver.trim();
  } else {
    solver = null;
  }
  return FiberAnnouncement(
    pubkey: pubkey.trim(),
    hasSolverField: hasSolverField,
    solver: solver,
  );
}

String? openFiberNode({
  required String daemonPublicKey,
  required NostrEvent event,
}) {
  return openFiberAnnouncement(
    daemonPublicKey: daemonPublicKey,
    event: event,
  )?.pubkey;
}

bool _tagged(List<List<String>>? tags, String identifier) {
  if (tags == null) return false;
  for (final tag in tags) {
    if (tag.length >= 2 && tag[0] == 'd' && tag[1] == identifier) return true;
  }
  return false;
}
