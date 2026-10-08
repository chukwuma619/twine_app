import 'package:flutter/material.dart';
import 'package:twine_app/nostr/twine_nostr.dart';
import 'package:twine_app/session/twine_app.dart';
import 'package:twine_app/store/account_store.dart';
import 'package:twine_app/store/book_store.dart';
import 'package:twine_app/store/daemon_store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final nostr = TwineNostr();
  await startTwine(
    nostr: nostr,
    store: SecureAccountStore(nostr.nostr),
    daemonStore: SecureDaemonStore(nostr.nostr),
    bookStore: SecureBookStore(),
  );
}

Future<void> startTwine({
  required TwineNostr nostr,
  required AccountStore store,
  required DaemonStore daemonStore,
  required BookStore bookStore,
}) async {
  try {
    final account = await store.read();
    final daemon = await daemonStore.read();
    nostr.account = account;
    nostr.daemon = daemon;
    runApp(
      TwineApp(
        nostr: nostr,
        store: store,
        daemonStore: daemonStore,
        bookStore: bookStore,
        initialAccount: account,
        initialDaemon: daemon,
        connectRelays: true,
      ),
    );
  } catch (_) {
    runApp(
      _StorageFailureApp(
        onRetry: () => startTwine(
          nostr: nostr,
          store: store,
          daemonStore: daemonStore,
          bookStore: bookStore,
        ),
        onImport: () {
          nostr.account = null;
          runApp(
            TwineApp(
              nostr: nostr,
              store: store,
              daemonStore: daemonStore,
              bookStore: bookStore,
              connectRelays: true,
            ),
          );
        },
      ),
    );
  }
}

class _StorageFailureApp extends StatelessWidget {
  const _StorageFailureApp({required this.onRetry, required this.onImport});

  final VoidCallback onRetry;
  final VoidCallback onImport;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Could not read the saved account.'),
                  const SizedBox(height: 16),
                  FilledButton(onPressed: onRetry, child: const Text('Try again')),
                  const SizedBox(height: 12),
                  OutlinedButton(onPressed: onImport, child: const Text('Import')),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
