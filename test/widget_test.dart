import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twine_app/nostr/account.dart';
import 'package:twine_app/nostr/account_store.dart';
import 'package:twine_app/nostr/twine_nostr.dart';
import 'package:twine_app/session/twine_app.dart';

void main() {
  testWidgets('creating a key signs in after the backup step', (tester) async {
    final store = MemoryAccountStore();
    final nostr = TwineNostr();

    await tester.pumpWidget(TwineApp(nostr: nostr, store: store));
    await tester.tap(find.text('Create a key'));
    await tester.pumpAndSettle();

    expect(find.text('Save this key'), findsOneWidget);
    expect(store.account, isNotNull);
    expect(find.text(store.account!.nsec), findsOneWidget);

    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    expect(find.text('Signed in'), findsOneWidget);
    expect(find.text(store.account!.npub), findsOneWidget);
    expect(nostr.account?.publicKey, store.account!.publicKey);
  });

  testWidgets('importing an nsec signs in', (tester) async {
    final nostr = TwineNostr();
    final existing = TwineAccount.generate(nostr.nostr);
    final store = MemoryAccountStore();

    await tester.pumpWidget(TwineApp(nostr: nostr, store: store));
    await tester.enterText(find.byType(TextField), existing.nsec);
    await tester.tap(find.text('Import'));
    await tester.pumpAndSettle();

    expect(find.text('Signed in'), findsOneWidget);
    expect(find.text(existing.npub), findsOneWidget);
    expect(store.account?.publicKey, existing.publicKey);
  });

  testWidgets('pasting an npub stays on the login screen', (tester) async {
    final nostr = TwineNostr();
    final existing = TwineAccount.generate(nostr.nostr);

    await tester.pumpWidget(
      TwineApp(nostr: nostr, store: MemoryAccountStore()),
    );
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
      TwineApp(nostr: TwineNostr(), store: MemoryAccountStore()),
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

  testWidgets('a stored key opens signed in', (tester) async {
    final nostr = TwineNostr();
    final account = TwineAccount.generate(nostr.nostr);
    final store = MemoryAccountStore()..account = account;

    await tester.pumpWidget(
      TwineApp(nostr: nostr, store: store, initialAccount: account),
    );

    expect(find.text(account.npub), findsOneWidget);
    expect(find.text('Save this key'), findsNothing);
  });

  testWidgets('log out removes the key', (tester) async {
    final nostr = TwineNostr();
    final account = TwineAccount.generate(nostr.nostr);
    final store = MemoryAccountStore()..account = account;

    await tester.pumpWidget(
      TwineApp(nostr: nostr, store: store, initialAccount: account),
    );
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
    expect(store.account, isNull);
    expect(nostr.account, isNull);
  });
}
