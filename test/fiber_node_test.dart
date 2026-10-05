import 'package:dart_nostr/dart_nostr.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twine_app/constant.dart';
import 'package:twine_app/nostr/account.dart';
import 'package:twine_app/nostr/fiber_node.dart';

void main() {
  final nostr = Nostr();

  test('a fiber node announcement opens only for that daemon', () {
    final daemon = TwineAccount.generate(nostr);
    final stranger = TwineAccount.generate(nostr);
    final event = NostrEvent.fromPartialData(
      kind: kindFiberNode,
      content: '{"pubkey":"02abc"}',
      keyPairs: NostrKeyPairs(private: daemon.privateKey),
      tags: const [
        ['d', fiberNodeTag],
      ],
      createdAt: DateTime.utc(2026, 10, 5),
    );

    expect(
      openFiberNode(daemonPublicKey: daemon.publicKey, event: event),
      '02abc',
    );
    expect(
      openFiberNode(daemonPublicKey: stranger.publicKey, event: event),
      isNull,
    );

    final other = NostrEvent.fromPartialData(
      kind: kindFiberNode,
      content: '{"pubkey":"02abc"}',
      keyPairs: NostrKeyPairs(private: daemon.privateKey),
      tags: const [
        ['d', 'something-else'],
      ],
      createdAt: DateTime.utc(2026, 10, 5),
    );
    expect(
      openFiberNode(daemonPublicKey: daemon.publicKey, event: other),
      isNull,
    );
  });
}
