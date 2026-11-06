import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twine_app/nostr/account.dart';
import 'package:twine_app/nostr/daemon.dart';
import 'package:twine_app/nostr/relay_backend.dart';
import 'package:twine_app/nostr/twine_nostr.dart';
import 'package:twine_app/session/push_service.dart';
import 'package:twine_app/session/push_wake.dart';
import 'package:twine_app/session/resume_latch.dart';
import 'package:twine_app/session/session.dart';
import 'package:twine_app/store/account_store.dart';
import 'package:twine_app/store/book_store.dart';
import 'package:twine_app/store/daemon_store.dart';

void main() {
  test('a doorbell after suspend asks the pool to resync', () async {
    final backend = _CountLinks();
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
      if (session.relays.isNotEmpty && !session.connecting) break;
      await Future<void>.delayed(Duration.zero);
    }
    expect(session.relays, isNotEmpty);
    final afterBoot = backend.links;

    final latch = ResumeLatch();
    expect(latch.observe(AppLifecycleState.paused), isFalse);
    pushWake.note();
    final woke = pushWake.consume();
    expect(latch.observe(AppLifecycleState.resumed) || woke, isTrue);
    await session.catchUp();
    expect(backend.links, greaterThan(afterBoot));
    session.dispose();
  });

  test('a foreground doorbell asks the pool to resync', () async {
    final backend = _CountLinks();
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
      if (session.relays.isNotEmpty && !session.connecting) break;
      await Future<void>.delayed(Duration.zero);
    }
    expect(session.relays, isNotEmpty);
    final afterBoot = backend.links;
    PushService.onForegroundWake = () {
      unawaited(session.catchUp());
    };
    addTearDown(() => PushService.onForegroundWake = null);
    PushService.onForegroundWake?.call();
    for (var i = 0; i < 20; i++) {
      if (backend.links > afterBoot) break;
      await Future<void>.delayed(Duration.zero);
    }
    expect(backend.links, greaterThan(afterBoot));
    session.dispose();
  });
}

class _CountLinks extends FakeRelayBackend {
  var links = 0;

  @override
  Future<List<String>> connect({
    required String nsec,
    required String daemonHex,
    required List<String> relays,
  }) async {
    links++;
    return super.connect(nsec: nsec, daemonHex: daemonHex, relays: relays);
  }

  @override
  Future<List<String>> resync() async {
    links++;
    return super.resync();
  }
}
