import 'dart:convert';

import '../market/chat.dart';
import 'nip44.dart';

/// Largest plaintext sealed into one NIP-44 message for the solver.
const evidencePlaintextLimit = 60000;

const _nip44PlaintextMax = 65535;
const _maxBlobs = 32;

/// Status lines written on this device are left out. An empty thread is still sealed.
List<String> sealTradeEvidence({
  required String secretKey,
  required String solverPubkey,
  required String tradeId,
  required List<TradeNote> notes,
}) {
  final chat = notes.where((note) => note.kind != TradeNoteKind.status).toList()
    ..sort((a, b) => a.at.compareTo(b.at));
  final chunks = <List<TradeNote>>[];
  var current = <TradeNote>[];
  for (final note in chat) {
    final trial = [...current, note];
    if (_size(tradeId, trial) > evidencePlaintextLimit && current.isNotEmpty) {
      chunks.add(current);
      current = [note];
    } else {
      current = trial;
    }
  }
  chunks.add(current);
  if (chunks.length > _maxBlobs) {
    throw Nip44Exception('too many messages to seal');
  }
  return [
    for (final chunk in chunks)
      nip44Encrypt(
        secretKey: secretKey,
        publicKey: solverPubkey,
        plaintext: _plaintext(tradeId, chunk),
      ),
  ];
}

int _size(String tradeId, List<TradeNote> notes) {
  return utf8.encode(_encode(tradeId, notes)).length;
}

String _plaintext(String tradeId, List<TradeNote> notes) {
  final plain = _encode(tradeId, notes);
  if (utf8.encode(plain).length > _nip44PlaintextMax) {
    throw Nip44Exception('one message is too large to seal');
  }
  return plain;
}

String _encode(String tradeId, List<TradeNote> notes) {
  return jsonEncode({
    'v': 1,
    'trade_id': tradeId,
    'notes': [for (final note in notes) _note(note)],
  });
}

Map<String, Object> _note(TradeNote note) {
  return {
    'id': note.id,
    'at': note.at.toUtc().toIso8601String(),
    'kind': note.kind.wire,
    if (note.author != null) 'author': note.author!,
    if (note.text != null) 'text': note.text!,
    if (note.amount != null) 'amount': note.amount!,
    if (note.image != null) 'image': note.image!,
  };
}
