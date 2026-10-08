import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:twine_app/nostr/account.dart';
import 'package:twine_app/nostr/daemon.dart';
import 'package:twine_app/nostr/fiber_node.dart';
import 'package:twine_app/nostr/twine_nostr.dart';
import 'package:twine_app/store/account_store.dart';
import 'package:twine_app/store/book_store.dart';
import 'package:twine_app/store/daemon_store.dart';

import 'market.dart';

class TwineSession extends ChangeNotifier {
  TwineSession({
    required this.nostr,
    required this.store,
    required this.daemonStore,
    required this.bookStore,
    this.account,
    this.daemon,
    this.connectRelays = false,
  }) {
    nostr.account = account;
    nostr.daemon = daemon;
    _bindMarket();
    if (account != null) {
      unawaited(_boot());
    }
  }

  Future<void> _boot() async {
    await _restoreBackupFlag();
    if (_disposed) return;
    final current = daemon;
    if (connectRelays && account != null && current != null && !showBackup) {
      connecting = true;
      _notify();
      unawaited(_openAndConnect(current));
    }
  }

  Future<void> _restoreBackupFlag() async {
    try {
      showBackup = !await store.backupConfirmed();
    } catch (_) {
      showBackup = false;
    }
    if (_disposed) return;
    _notify();
  }

  static const _invalidKey = 'Enter an nsec or a 64-character hex key.';
  static const _publicKeyPasted = 'That is the public key. Paste the nsec.';
  static const _saveFailed = 'Could not save the key on this device.';
  static const _removeFailed = 'Could not remove the key from this device.';
  static const _daemonSecret =
      "That is a secret key. Paste the daemon's public key.";
  static const _daemonPubkey = "Enter the daemon's npub or public key.";
  static const _daemonRelays = 'Enter at least one relay starting with wss://.';
  static const _daemonSaveFailed = 'Could not save this daemon on the device.';

  final TwineNostr nostr;
  final AccountStore store;
  final DaemonStore daemonStore;
  final BookStore bookStore;
  final bool connectRelays;

  TwineAccount? account;
  TwineDaemon? daemon;
  TwineMarket? market;
  bool showBackup = false;
  bool editingDaemon = false;
  bool viewingAccount = false;
  bool busy = false;
  String? error;
  String? logoutError;
  String? daemonError;
  List<String> relays = const [];
  String? fiberNode;
  bool? solverAvailable;
  String? relayError;
  bool connecting = false;

  StreamSubscription<FiberAnnouncement>? _fiberSub;
  bool _disposed = false;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> connect(List<String> relays) async {
    await _fiberSub?.cancel();
    fiberNode = null;
    solverAvailable = null;
    _notify();
    try {
      final open = await nostr.connect(relays);
      if (_disposed) return;
      nostr.watchReplies();
      nostr.watchFiberNode();
      nostr.watchOrders();
      nostr.watchCatalog();
      _fiberSub = nostr.fiberNodes.listen((announcement) {
        if (_disposed) return;
        fiberNode = announcement.pubkey;
        solverAvailable = announcement.hasSolverField
            ? announcement.solverConfigured
            : null;
        _notify();
      });
      this.relays = open;
      relayError = null;
      connecting = false;
      _notify();
    } catch (error) {
      if (_disposed) return;
      relayError = error is TwineRelayException
          ? error.message
          : 'no nostr relay connected';
      connecting = false;
      _notify();
    }
  }

  Future<void> create() async {
    if (busy) return;
    busy = true;
    error = null;
    _notify();
    try {
      final created = TwineAccount.generate(nostr.nostr);
      await store.write(created);
      await store.setBackupConfirmed(false);
      if (_disposed) return;
      nostr.account = created;
      account = created;
      showBackup = true;
      busy = false;
      _bindMarket();
      _notify();
    } catch (_) {
      if (_disposed) return;
      busy = false;
      error = _saveFailed;
      _notify();
    }
  }

  Future<void> import(String secret) async {
    if (busy) return;
    final trimmed = secret.trim().toLowerCase();
    if (trimmed.startsWith('npub1')) {
      error = _publicKeyPasted;
      _notify();
      return;
    }
    final parsed = TwineAccount.tryParse(nostr.nostr, secret);
    if (parsed == null) {
      error = _invalidKey;
      _notify();
      return;
    }
    busy = true;
    error = null;
    _notify();
    try {
      await store.write(parsed);
    } catch (_) {
      if (_disposed) return;
      busy = false;
      error = _saveFailed;
      _notify();
      return;
    }
    if (_disposed) return;
    nostr.account = parsed;
    final current = daemon;
    account = parsed;
    showBackup = true;
    busy = false;
    _bindMarket();
    _notify();
    try {
      await store.setBackupConfirmed(false);
    } catch (_) {}
  }

  Future<void> saveDaemon(String pubkey, String relays) async {
    if (busy) return;
    final trimmed = pubkey.trim().toLowerCase();
    if (trimmed.startsWith('nsec1')) {
      daemonError = _daemonSecret;
      _notify();
      return;
    }
    final parsedKey = TwineDaemon.parsePublicKey(nostr.nostr, pubkey);
    if (parsedKey == null) {
      daemonError = _daemonPubkey;
      _notify();
      return;
    }
    final parsedRelays = TwineDaemon.parseRelays(relays);
    if (parsedRelays == null) {
      daemonError = _daemonRelays;
      _notify();
      return;
    }
    final parsed = TwineDaemon(
      publicKey: parsedKey,
      npub: nostr.nostr.bech32.encodePublicKeyToNpub(parsedKey),
      relays: parsedRelays,
    );
    busy = true;
    daemonError = null;
    _notify();
    try {
      await daemonStore.write(parsed);
    } catch (_) {
      if (_disposed) return;
      busy = false;
      daemonError = _daemonSaveFailed;
      _notify();
      return;
    }
    if (_disposed) return;
    nostr.daemon = parsed;
    daemon = parsed;
    editingDaemon = false;
    busy = false;
    this.relays = const [];
    fiberNode = null;
    solverAvailable = null;
    relayError = null;
    _bindMarket();
    connecting = connectRelays;
    _notify();
    if (connectRelays) unawaited(_openAndConnect(parsed));
  }

  Future<void> continueFromBackup() async {
    showBackup = false;
    try {
      await store.setBackupConfirmed(true);
    } catch (_) {}
    if (_disposed) return;
    final current = daemon;
    if (connectRelays && current != null) {
      connecting = true;
      _notify();
      unawaited(_openAndConnect(current));
      return;
    }
    _notify();
  }

  void openAccount() {
    viewingAccount = true;
    _notify();
  }

  void closeAccount() {
    viewingAccount = false;
    _notify();
  }

  void editDaemon() {
    viewingAccount = false;
    editingDaemon = true;
    _notify();
  }

  void cancelDaemonEdit() {
    editingDaemon = false;
    daemonError = null;
    _notify();
  }

  Future<void> logOut() async {
    try {
      await store.clear();
    } catch (_) {
      if (_disposed) return;
      logoutError = _removeFailed;
      _notify();
      return;
    }
    if (_disposed) return;
    nostr.account = null;
    nostr.stopWatching();
    await _fiberSub?.cancel();
    _fiberSub = null;
    account = null;
    viewingAccount = false;
    fiberNode = null;
    solverAvailable = null;
    showBackup = false;
    editingDaemon = false;
    error = null;
    logoutError = null;
    _bindMarket();
    _notify();
  }

  void _bindMarket() {
    final currentAccount = account;
    final currentDaemon = daemon;
    if (currentAccount == null || currentDaemon == null) {
      market?.stop();
      market = null;
      return;
    }
    final current = market;
    if (current != null &&
        current.accountPubkey == currentAccount.publicKey &&
        current.daemonPubkey == currentDaemon.publicKey) {
      return;
    }
    current?.stop();
    final next = TwineMarket(
      nostr: nostr,
      store: bookStore,
      accountPubkey: currentAccount.publicKey,
      daemonPubkey: currentDaemon.publicKey,
    );
    market = next;
    unawaited(next.open());
  }

  Future<void> _openAndConnect(TwineDaemon current) async {
    await market?.open();
    if (_disposed) return;
    await connect(current.relays);
  }

  @override
  void dispose() {
    _disposed = true;
    market?.stop();
    _fiberSub?.cancel();
    super.dispose();
  }
}
