import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twine_app/nostr/account.dart';
import 'package:twine_app/nostr/daemon.dart';
import 'package:twine_app/nostr/twine_nostr.dart';
import 'package:twine_app/store/account_store.dart';
import 'package:twine_app/store/daemon_store.dart';
import 'package:twine_app/session/signed_in_page.dart';
import 'package:twine_app/session/twine_app.dart';

void main() {
  TwineApp app({
    required TwineNostr nostr,
    required MemoryAccountStore store,
    MemoryDaemonStore? daemonStore,
    TwineAccount? initialAccount,
    TwineDaemon? initialDaemon,
  }) {
    return TwineApp(
      nostr: nostr,
      store: store,
      daemonStore: daemonStore ?? MemoryDaemonStore(),
      initialAccount: initialAccount,
      initialDaemon: initialDaemon,
    );
  }

  testWidgets('creating a key asks which daemon to use', (tester) async {
    final store = MemoryAccountStore();
    final nostr = TwineNostr();

    await tester.pumpWidget(app(nostr: nostr, store: store));
    await tester.tap(find.text('Create a key'));
    await tester.pumpAndSettle();

    expect(find.text('Save this key'), findsOneWidget);
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    expect(find.text('Connect to a daemon'), findsOneWidget);
    expect(find.text('Signed in'), findsNothing);
    expect(nostr.account?.publicKey, store.account!.publicKey);
  });

  testWidgets('importing an nsec asks which daemon to use', (tester) async {
    final nostr = TwineNostr();
    final existing = TwineAccount.generate(nostr.nostr);
    final store = MemoryAccountStore();

    await tester.pumpWidget(app(nostr: nostr, store: store));
    await tester.enterText(find.byType(TextField), existing.nsec);
    await tester.tap(find.text('Import'));
    await tester.pumpAndSettle();

    expect(find.text('Connect to a daemon'), findsOneWidget);
    expect(store.account?.publicKey, existing.publicKey);
  });

  testWidgets('pasting an npub stays on the login screen', (tester) async {
    final nostr = TwineNostr();
    final existing = TwineAccount.generate(nostr.nostr);

    await tester.pumpWidget(app(nostr: nostr, store: MemoryAccountStore()));
    await tester.enterText(find.byType(TextField), existing.npub);
    await tester.tap(find.text('Import'));
    await tester.pump();

    expect(
      find.text('That is the public key. Paste the nsec.'),
      findsOneWidget,
    );
    expect(find.text('Signed in'), findsNothing);
  });

  testWidgets('a bad import stays on the login screen', (tester) async {
    await tester.pumpWidget(
      app(nostr: TwineNostr(), store: MemoryAccountStore()),
    );
    await tester.enterText(find.byType(TextField), 'not-a-key');
    await tester.tap(find.text('Import'));
    await tester.pump();

    expect(
      find.text('Enter an nsec or a 64-character hex key.'),
      findsOneWidget,
    );
    expect(find.text('Signed in'), findsNothing);
  });

  testWidgets('a stored key without a daemon asks for one', (tester) async {
    final nostr = TwineNostr();
    final account = TwineAccount.generate(nostr.nostr);

    await tester.pumpWidget(
      app(
        nostr: nostr,
        store: MemoryAccountStore()..account = account,
        initialAccount: account,
      ),
    );

    expect(find.text('Connect to a daemon'), findsOneWidget);
    expect(find.text('Signed in'), findsNothing);
  });

  testWidgets('saving a daemon points the app at it', (tester) async {
    final nostr = TwineNostr();
    final account = TwineAccount.generate(nostr.nostr);
    final daemonKey = TwineAccount.generate(nostr.nostr);
    final daemons = MemoryDaemonStore();

    await tester.pumpWidget(
      app(
        nostr: nostr,
        store: MemoryAccountStore()..account = account,
        daemonStore: daemons,
        initialAccount: account,
      ),
    );
    await tester.enterText(find.byType(TextField).at(0), daemonKey.npub);
    await tester.enterText(
      find.byType(TextField).at(1),
      'wss://relay.example.com',
    );
    await tester.tap(find.text('Connect'));
    await tester.pumpAndSettle();

    expect(find.text('Posts'), findsOneWidget);
    expect(find.text('No posts yet.'), findsOneWidget);
    await tester.tap(find.text('Account'));
    await tester.pumpAndSettle();

    expect(find.text('Signed in'), findsOneWidget);
    expect(find.text(daemonKey.npub), findsOneWidget);
    expect(find.text('wss://relay.example.com'), findsOneWidget);
    expect(daemons.daemon?.publicKey, daemonKey.publicKey);
    expect(nostr.daemon?.publicKey, daemonKey.publicKey);
  });

  testWidgets('a daemon secret is refused', (tester) async {
    final nostr = TwineNostr();
    final account = TwineAccount.generate(nostr.nostr);

    await tester.pumpWidget(
      app(
        nostr: nostr,
        store: MemoryAccountStore()..account = account,
        initialAccount: account,
      ),
    );
    await tester.enterText(find.byType(TextField).at(0), account.nsec);
    await tester.enterText(
      find.byType(TextField).at(1),
      'wss://relay.example.com',
    );
    await tester.tap(find.text('Connect'));
    await tester.pump();

    expect(
      find.text("That is a secret key. Paste the daemon's public key."),
      findsOneWidget,
    );
    expect(find.text('Signed in'), findsNothing);
  });

  testWidgets('log out removes the key and keeps the daemon', (tester) async {
    final nostr = TwineNostr();
    final account = TwineAccount.generate(nostr.nostr);
    final daemonKey = TwineAccount.generate(nostr.nostr);
    final daemon = TwineDaemon.tryParse(
      nostr.nostr,
      pubkey: daemonKey.npub,
      relays: 'wss://relay.example.com',
    )!;
    final daemons = MemoryDaemonStore()..daemon = daemon;

    await tester.pumpWidget(
      app(
        nostr: nostr,
        store: MemoryAccountStore()..account = account,
        daemonStore: daemons,
        initialAccount: account,
        initialDaemon: daemon,
      ),
    );
    await tester.tap(find.text('Account'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Log out'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.widgetWithText(TextButton, 'Log out'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Your Nostr key is your account.'), findsOneWidget);
    expect(nostr.account, isNull);
    expect(daemons.daemon?.publicKey, daemon.publicKey);
  });

  testWidgets('the signed-in screen shows the fiber node to open', (
    tester,
  ) async {
    final nostr = TwineNostr();
    final account = TwineAccount.generate(nostr.nostr);
    final daemonKey = TwineAccount.generate(nostr.nostr);
    final daemon = TwineDaemon.tryParse(
      nostr.nostr,
      pubkey: daemonKey.npub,
      relays: 'wss://relay.example.com',
    )!;

    await tester.pumpWidget(
      MaterialApp(
        home: SignedInPage(
          account: account,
          daemon: daemon,
          fiberNode: '02abc',
          onChangeDaemon: () {},
          onLogOut: () {},
        ),
      ),
    );

    expect(find.text('Fiber node'), findsOneWidget);
    expect(find.text('02abc'), findsOneWidget);
    expect(
      find.text('Open a channel to this node in your Fiber wallet.'),
      findsOneWidget,
    );
  });
}
