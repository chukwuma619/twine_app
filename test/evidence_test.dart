import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:twine_app/market/chat.dart';
import 'package:twine_app/nostr/evidence.dart';
import 'package:twine_app/nostr/keys.dart';
import 'package:twine_app/nostr/nip44.dart';

void main() {
  test('a dispute seals this trade and not the conversation key', () {
    final sender = TwineKeys.generate();
    final solver = TwineKeys.generate();
    final peer = TwineKeys.generate();
    final at = DateTime.utc(2026, 11, 8, 12);
    final blobs = sealTradeEvidence(
      secretKey: sender.privateKey,
      solverPubkey: solver.publicKey,
      tradeId: 'trade-1',
      notes: [
        TradeNote(
          id: 'status-1',
          tradeId: 'trade-1',
          at: at,
          kind: TradeNoteKind.status,
          text: 'local only',
        ),
        TradeNote(
          id: 'note-1',
          tradeId: 'trade-1',
          at: at,
          kind: TradeNoteKind.text,
          author: sender.publicKey,
          text: 'paid',
        ),
        TradeNote(
          id: 'proof-1',
          tradeId: 'trade-1',
          at: at.add(const Duration(minutes: 1)),
          kind: TradeNoteKind.paymentProof,
          author: sender.publicKey,
          image: 'aW1hZ2U=',
        ),
      ],
    );
    expect(blobs, hasLength(1));
    final conversation = nip44ConversationKeyHex(
      sender.privateKey,
      peer.publicKey,
    );
    expect(blobs.single.contains(conversation), isFalse);
    final opened = nip44Decrypt(
      secretKey: solver.privateKey,
      publicKey: sender.publicKey,
      payload: blobs.single,
    );
    final decoded = jsonDecode(opened) as Map<String, Object?>;
    expect(decoded['trade_id'], 'trade-1');
    final notes = decoded['notes'] as List<Object?>;
    expect(notes, hasLength(2));
    expect((notes[0] as Map)['text'], 'paid');
    expect((notes[1] as Map)['image'], 'aW1hZ2U=');
    expect(opened.contains('local only'), isFalse);
  });

  test('a long thread is split and a huge message is refused', () {
    final sender = TwineKeys.generate();
    final solver = TwineKeys.generate();
    final at = DateTime.utc(2026, 11, 8);
    final blobs = sealTradeEvidence(
      secretKey: sender.privateKey,
      solverPubkey: solver.publicKey,
      tradeId: 'trade-1',
      notes: [
        for (var i = 0; i < 3; i++)
          TradeNote(
            id: 'note-$i',
            tradeId: 'trade-1',
            at: at.add(Duration(minutes: i)),
            kind: TradeNoteKind.text,
            text: 'a' * 30000,
          ),
      ],
    );
    expect(blobs.length, greaterThan(1));
    final opened = [
      for (final blob in blobs)
        jsonDecode(
              nip44Decrypt(
                secretKey: solver.privateKey,
                publicKey: sender.publicKey,
                payload: blob,
              ),
            )
            as Map<String, Object?>,
    ];
    final count = opened.fold<int>(
      0,
      (sum, item) => sum + (item['notes'] as List).length,
    );
    expect(count, 3);

    expect(
      () => sealTradeEvidence(
        secretKey: sender.privateKey,
        solverPubkey: solver.publicKey,
        tradeId: 'trade-1',
        notes: [
          TradeNote(
            id: 'huge',
            tradeId: 'trade-1',
            at: at,
            kind: TradeNoteKind.text,
            text: 'b' * 70000,
          ),
        ],
      ),
      throwsA(isA<Nip44Exception>()),
    );
  });
}
