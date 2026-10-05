import 'package:dart_nostr/dart_nostr.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twine_app/constant.dart';
import 'package:twine_app/nostr/account.dart';
import 'package:twine_app/nostr/action.dart';
import 'package:twine_app/nostr/daemon.dart';
import 'package:twine_app/nostr/envelope.dart';
import 'package:twine_app/nostr/twine_nostr.dart';

void main() {
  final nostr = Nostr();

  test('an action sealed to the daemon opens only for that daemon', () {
    final user = TwineAccount.generate(nostr);
    final daemonKey = TwineAccount.generate(nostr);
    final stranger = TwineAccount.generate(nostr);
    final client = TwineNostr(nostr: nostr);
    client.account = user;
    client.daemon = _daemon(nostr, daemonKey);

    final event = client.seal(
      const TwineEnvelope(action: 'new-order', payload: {'side': 'sell'}),
    );

    expect(event.kind, kindAction);
    expect(event.pubkey, user.publicKey);
    expect(event.tags, [
      ['p', daemonKey.publicKey],
    ]);
    expect(event.isVerified(), isTrue);

    final daemon = TwineNostr();
    daemon.account = daemonKey;
    daemon.daemon = _daemon(nostr, user);
    final opened = daemon.open(event);
    expect(opened?.action, 'new-order');
    expect(opened?.payload, {'side': 'sell'});

    daemon.daemon = _daemon(nostr, stranger);
    expect(daemon.open(event), isNull);
  });

  test('a reply opens for the user and a tampered copy is dropped', () {
    final user = TwineAccount.generate(nostr);
    final daemonKey = TwineAccount.generate(nostr);
    final reply = sealAction(
      sender: daemonKey,
      recipientPublicKey: user.publicKey,
      envelope: const TwineEnvelope(action: 'pay-invoice', tradeId: 'trade-1'),
      createdAt: DateTime.utc(2026, 10, 5),
    );

    final opened = openReply(
      recipient: user,
      senderPublicKey: daemonKey.publicKey,
      event: reply,
    );
    expect(opened?.action, 'pay-invoice');
    expect(opened?.tradeId, 'trade-1');

    final tampered = NostrEvent(
      content: reply.content,
      createdAt: reply.createdAt,
      id: reply.id,
      kind: reply.kind,
      pubkey: user.publicKey,
      sig: reply.sig,
      tags: reply.tags,
    );
    expect(
      openReply(
        recipient: user,
        senderPublicKey: daemonKey.publicKey,
        event: tampered,
      ),
      isNull,
    );

    final rewritten = NostrEvent(
      content: 'not-ciphertext',
      createdAt: reply.createdAt,
      id: reply.id,
      kind: reply.kind,
      pubkey: reply.pubkey,
      sig: reply.sig,
      tags: reply.tags,
    );
    expect(
      openReply(
        recipient: user,
        senderPublicKey: daemonKey.publicKey,
        event: rewritten,
      ),
      isNull,
    );
  });
}

TwineDaemon _daemon(Nostr nostr, TwineAccount account) {
  return TwineDaemon(
    publicKey: account.publicKey,
    npub: nostr.bech32.encodePublicKeyToNpub(account.publicKey),
    relays: const ['wss://relay.example.com'],
  );
}
