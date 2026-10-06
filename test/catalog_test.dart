import 'dart:convert';

import 'package:dart_nostr/dart_nostr.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twine_app/constant.dart';
import 'package:twine_app/nostr/account.dart';
import 'package:twine_app/nostr/catalog.dart';

void main() {
  final nostr = Nostr();

  test('a payment catalog opens only for the daemon that signed it', () {
    final daemon = TwineAccount.generate(nostr);
    final stranger = TwineAccount.generate(nostr);
    final content = jsonEncode({
      'methods': [
        {'id': 'gtbank', 'kind': 'bank', 'label': 'GTBank', 'currency': 'NGN'},
      ],
    });
    final event = NostrEvent.fromPartialData(
      kind: kindCatalog,
      content: content,
      keyPairs: NostrKeyPairs(private: daemon.privateKey),
      tags: const [
        ['d', paymentCatalogTag],
      ],
      createdAt: DateTime.utc(2026, 10, 6),
    );

    final opened = openCatalog(daemonPublicKey: daemon.publicKey, event: event);
    expect(opened?.methods.single.id, 'gtbank');
    expect(opened?.updatedAt, DateTime.utc(2026, 10, 6));
    expect(
      openCatalog(daemonPublicKey: stranger.publicKey, event: event),
      isNull,
    );

    final other = NostrEvent.fromPartialData(
      kind: kindCatalog,
      content: content,
      keyPairs: NostrKeyPairs(private: daemon.privateKey),
      tags: const [
        ['d', 'something-else'],
      ],
      createdAt: DateTime.utc(2026, 10, 6),
    );
    expect(
      openCatalog(daemonPublicKey: daemon.publicKey, event: other),
      isNull,
    );
  });
}
