/// Chooses the screen from the session.
library;

import 'package:cupertino_native_better/cupertino_native_better.dart';
import 'package:flutter/material.dart';
import 'package:twine_app/nostr/account.dart';
import 'package:twine_app/nostr/daemon.dart';
import 'package:twine_app/nostr/twine_nostr.dart';
import 'package:twine_app/store/account_store.dart';
import 'package:twine_app/store/book_store.dart';
import 'package:twine_app/store/daemon_store.dart';

import 'backup_page.dart';
import 'daemon_page.dart';
import 'login_page.dart';
import 'market_page.dart';
import 'session.dart';
import 'signed_in_page.dart';

class TwineApp extends StatefulWidget {
  const TwineApp({
    super.key,
    required this.nostr,
    required this.store,
    required this.daemonStore,
    this.bookStore,
    this.initialAccount,
    this.initialDaemon,
    this.connectRelays = false,
  });

  final TwineNostr nostr;
  final AccountStore store;
  final DaemonStore daemonStore;
  final BookStore? bookStore;
  final TwineAccount? initialAccount;
  final TwineDaemon? initialDaemon;
  final bool connectRelays;

  @override
  State<TwineApp> createState() => _TwineAppState();
}

class _TwineAppState extends State<TwineApp> {
  late final TwineSession _session;
  late final BookStore _books;

  @override
  void initState() {
    super.initState();
    _books = widget.bookStore ?? MemoryBookStore();
    _session = TwineSession(
      nostr: widget.nostr,
      store: widget.store,
      daemonStore: widget.daemonStore,
      bookStore: _books,
      account: widget.initialAccount,
      daemon: widget.initialDaemon,
      connectRelays: widget.connectRelays,
    );
  }

  @override
  void dispose() {
    _session.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Twine',
      navigatorObservers: [CNTabBarRouteObserver()],
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
      ),
      home: ListenableBuilder(
        listenable: _session,
        builder: (context, _) => _home(_session),
      ),
    );
  }

  Widget _home(TwineSession session) {
    final account = session.account;
    final daemon = session.daemon;
    if (account == null) {
      return LoginPage(
        onCreate: session.create,
        onImport: session.import,
        busy: session.busy,
        error: session.error,
      );
    }
    if (session.showBackup) {
      return BackupPage(
        nsec: account.nsec,
        onContinue: session.continueFromBackup,
      );
    }
    if (daemon == null || session.editingDaemon) {
      return DaemonPage(
        current: session.editingDaemon ? daemon : null,
        busy: session.busy,
        error: session.daemonError,
        onSave: session.saveDaemon,
        onCancel: session.editingDaemon && daemon != null
            ? session.cancelDaemonEdit
            : null,
      );
    }
    if (session.viewingAccount) {
      return SignedInPage(
        account: account,
        daemon: daemon,
        connecting: session.connecting,
        connectedRelays: session.relays,
        fiberNode: session.fiberNode,
        relayError: session.relayError,
        onChangeDaemon: session.editDaemon,
        onLogOut: session.logOut,
        onClose: session.closeAccount,
        error: session.logoutError,
      );
    }
    final market = session.market;
    if (market == null) {
      return const Scaffold(body: Center(child: Text('Opening the book…')));
    }
    return MarketPage(
      market: market,
      fiberNode: session.fiberNode,
      connecting: session.connecting,
      linked: session.relays.isNotEmpty,
      relayError: session.relayError,
      onAccount: session.openAccount,
    );
  }
}
