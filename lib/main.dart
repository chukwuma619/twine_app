import 'package:flutter/material.dart';
import 'package:twine_app/nostr/account_store.dart';
import 'package:twine_app/nostr/twine_nostr.dart';
import 'package:twine_app/session/twine_app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final nostr = TwineNostr();
  final store = SecureAccountStore(nostr.nostr);
  try {
    final account = await store.read();
    nostr.account = account;
    runApp(
      TwineApp(
        nostr: nostr,
        store: store,
        initialAccount: account,
        connectRelays: true,
      ),
    );
  } catch (_) {
    runApp(const _StorageFailureApp());
  }
}

class _StorageFailureApp extends StatelessWidget {
  const _StorageFailureApp();

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      home: Scaffold(
        body: Center(child: Text('Could not read the saved key.')),
      ),
    );
  }
}
