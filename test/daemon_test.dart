import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_secure_storage/test/test_flutter_secure_storage_platform.dart';
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twine_app/nostr/account.dart';
import 'package:twine_app/nostr/daemon.dart';
import 'package:twine_app/nostr/twine_nostr.dart';
import 'package:twine_app/store/daemon_store.dart';

void main() {
  test('accepts an npub and a relay list', () {
    final source = TwineAccount.generate();
    final daemon = TwineDaemon.tryParse(
      pubkey: source.npub.toUpperCase(),
      relays: 'WSS://Relay.Example.com, wss://relay.example.com',
    );

    expect(daemon?.publicKey, source.publicKey);
    expect(daemon?.npub, source.npub);
    expect(daemon?.relays, ['wss://relay.example.com']);
  });

  test('rejects a daemon secret and a non-websocket relay', () {
    final source = TwineAccount.generate();
    expect(TwineDaemon.parsePublicKey(source.nsec), isNull);
    expect(TwineDaemon.parseRelays('https://example.com'), isNull);
    expect(TwineDaemon.parseRelays(''), isNull);
  });

  test('connect rejects a relay that is not a websocket', () {
    final client = TwineNostr();
    client.account = TwineAccount.generate();
    client.daemon = TwineDaemon(
      publicKey: client.account!.publicKey,
      npub: client.account!.npub,
      relays: const ['wss://relay.example.com'],
    );
    expect(
      () => client.connect(['https://example.com']),
      throwsA(isA<TwineRelayException>()),
    );
  });

  test('secure store restores a daemon and drops a corrupt one', () async {
    final data = <String, String>{};
    FlutterSecureStoragePlatform.instance = TestFlutterSecureStoragePlatform(
      data,
    );
    final store = SecureDaemonStore(storage: const FlutterSecureStorage());
    final source = TwineAccount.generate();
    final daemon = TwineDaemon.tryParse(
      pubkey: source.npub,
      relays: 'wss://relay.example.com',
    );

    await store.write(daemon!);
    expect((await store.read())?.publicKey, source.publicKey);

    data[data.keys.single] = jsonEncode({'publicKey': 'nope'});
    expect(await store.read(), isNull);
    expect(data, isEmpty);
  });
}
