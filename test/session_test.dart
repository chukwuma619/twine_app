import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:twine_app/nostr/account.dart';
import 'package:twine_app/nostr/daemon.dart';
import 'package:twine_app/nostr/relay_backend.dart';
import 'package:twine_app/nostr/twine_nostr.dart';
import 'package:twine_app/session/session.dart';
import 'package:twine_app/store/account_store.dart';
import 'package:twine_app/store/book_store.dart';
import 'package:twine_app/store/daemon_store.dart';

void main() {
  test('catchUp joins an in-flight recover instead of stacking another', () async {
    final hold = Completer<void>();
    final backend = _HoldResync(hold);
    final account = TwineAccount.generate();
    final daemon = TwineDaemon.tryParse(
      pubkey: TwineAccount.generate().npub,
      relays: 'wss://relay.example.com',
    )!;
    final session = TwineSession(
      nostr: TwineNostr(backend: backend),
      store: MemoryAccountStore()..account = account,
      daemonStore: MemoryDaemonStore()..daemon = daemon,
      bookStore: MemoryBookStore(),
      account: account,
      daemon: daemon,
      connectRelays: true,
    );
    for (var i = 0; i < 20; i++) {
      if (session.relays.isNotEmpty && !session.connecting) {
        break;
      }
      await Future<void>.delayed(Duration.zero);
    }
    expect(session.relays, isNotEmpty);

    final first = session.catchUp();
    final second = session.catchUp();
    await Future<void>.delayed(Duration.zero);
    expect(backend.resyncs, 1);

    hold.complete();
    await Future.wait([first, second]);
    expect(backend.resyncs, 1);
    session.dispose();
  });

  test('a slow resync keeps the last linked relays', () async {
    final backend = _EmptyResync();
    final session = await _linked(backend);
    final before = session.relays;
    await session.catchUp();
    expect(session.relays, before);
    expect(session.relayError, isNull);
    session.dispose();
  });

  test('log out unregisters the doorbell token', () async {
    final backend = _PushBackend();
    final session = await _linked(backend);
    await session.logOut();
    expect(backend.url, officialPushUrl);
    expect(backend.token, isEmpty);
    session.dispose();
  });
}

Future<TwineSession> _linked(TwineRelayBackend backend) async {
  final account = TwineAccount.generate();
  final daemon = TwineDaemon.tryParse(
    pubkey: TwineAccount.generate().npub,
    relays: 'wss://relay.example.com',
  )!;
  final session = TwineSession(
    nostr: TwineNostr(backend: backend),
    store: MemoryAccountStore()..account = account,
    daemonStore: MemoryDaemonStore()..daemon = daemon,
    bookStore: MemoryBookStore(),
    account: account,
    daemon: daemon,
    connectRelays: true,
  );
  for (var i = 0; i < 20; i++) {
    if (session.relays.isNotEmpty && !session.connecting) {
      break;
    }
    await Future<void>.delayed(Duration.zero);
  }
  expect(session.relays, isNotEmpty);
  return session;
}

class _EmptyResync extends FakeRelayBackend {
  @override
  Future<List<String>> resync() async => const [];
}

class _PushBackend extends FakeRelayBackend {
  String? url;
  String? token;

  @override
  Future<void> setPushToken({required String url, required String token}) async {
    this.url = url;
    this.token = token;
  }
}

class _HoldResync extends FakeRelayBackend {
  _HoldResync(this.hold);

  final Completer<void> hold;
  var resyncs = 0;

  @override
  Future<List<String>> resync() async {
    resyncs++;
    await hold.future;
    return super.resync();
  }
}
