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
import 'relay_work.dart';

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
    nostr.onRelayDropped = () {
      unawaited(catchUp(force: true));
    };
    _bindMarket();
    unawaited(_boot());
  }

  Future<void> _boot() async {
    await _restoreBackupFlag();
    await _restoreFiberGuide();
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

  Future<void> _restoreFiberGuide() async {
    try {
      showFiberGuide = !await store.fiberGuideSeen();
    } catch (_) {
      showFiberGuide = false;
    }
    if (_disposed) return;
    _notify();
  }

  Future<void> dismissFiberGuide() async {
    showFiberGuide = false;
    _notify();
    try {
      await store.setFiberGuideSeen(true);
    } catch (_) {}
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
  bool showFiberGuide = false;
  bool editingDaemon = false;
  bool viewingAccount = false;
  bool busy = false;
  String? error;
  String? logoutError;
  String? daemonError;
  List<String> relays = const [];
  String? fiberNode;
  List<String> fiberAddresses = const [];
  bool? solverAvailable;
  String? relayError;
  bool connecting = false;

  StreamSubscription<FiberAnnouncement>? _fiberSub;
  bool _disposed = false;
  final _work = RelayWork();
  Timer? _catchUpTimer;
  Timer? _retryTimer;
  DateTime? _relaysReplacedAt;
  int _retrySeconds = 2;

  /// How often a quiet phone checks that a relay still answers.
  /// The live subscription still delivers an update the moment it arrives.
  static const _catchUpEvery = Duration(seconds: 10);

  /// After a successful dial, leave the new sockets alone this long.
  /// Long enough for the first EOSE. Short enough that a zombie dial is
  /// replaced on the next probe instead of sitting deaf for a quarter minute.
  static const _replaceCooldown = Duration(seconds: 4);

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> connect(List<String> relays) {
    return _work.run(
      replace: true,
      body: (_) => _recover(replace: true, relays: relays),
    );
  }

  bool get _relaysCooledDown {
    final replaced = _relaysReplacedAt;
    if (replaced == null) return true;
    return DateTime.now().difference(replaced) >= _replaceCooldown;
  }

  /// Reloads the book. [force] dials again: coming back to the app, a socket
  /// that closed, or a pull to refresh. A quiet probe dials after one miss.
  Future<void> catchUp({bool force = false}) {
    return _work.run(
      replace: force,
      body: (replace) => _recover(replace: replace),
    );
  }

  /// The process is frozen in the background. Stop the probe so it does not
  /// run on the same wake as the resume dial and hold that dial behind a
  /// five-second timeout into a dead socket.
  void sleep() {
    _stopCatchUp();
  }

  Future<void> _recover({required bool replace, List<String>? relays}) async {
    final current = daemon;
    final book = market;
    if (!connectRelays || account == null || current == null || book == null) {
      return;
    }
    if (showBackup || editingDaemon) return;
    if (!_disposed) _armCatchUp();
    if (!replace && book.sending) return;

    var answered = false;
    if (!replace) {
      if (_work.replaceQueued) return;
      try {
        answered = await nostr.reconcile();
      } catch (_) {
        answered = false;
      }
      if (_work.replaceQueued) return;
    }
    final dial = shouldReplaceRelay(
      force: replace,
      probeAnswered: answered,
      cooledDown: _relaysCooledDown,
    );
    if (dial) {
      await _openRelays(relays ?? current.relays);
      if (_disposed) return;
      if (relayError == null) {
        _relaysReplacedAt = DateTime.now();
        _retrySeconds = 2;
      } else {
        _relaysReplacedAt = null;
        _retrySoon();
      }
    }
    if (_disposed || !book.ready) return;
    await book.refreshTrades();
  }

  Future<void> _openRelays(List<String> relays) async {
    await _fiberSub?.cancel();
    final alreadyLinked = this.relays.isNotEmpty;
    connecting = !alreadyLinked;
    relayError = null;
    if (!alreadyLinked) _notify();
    try {
      final open = await nostr.connect(relays);
      if (_disposed) return;
      nostr.watchReplies();
      nostr.watchFiberNode();
      nostr.watchOrders();
      _fiberSub = nostr.fiberNodes.listen((announcement) {
        if (_disposed) return;
        fiberNode = announcement.pubkey;
        fiberAddresses = announcement.addresses;
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
      this.relays = const [];
      relayError = error is TwineRelayException
          ? error.message
          : 'no nostr relay connected';
      connecting = false;
      _notify();
    }
  }

  void _armCatchUp() {
    _catchUpTimer ??= Timer.periodic(_catchUpEvery, (_) {
      unawaited(catchUp());
    });
  }

  void _retrySoon() {
    _retryTimer?.cancel();
    final wait = Duration(seconds: _retrySeconds);
    _retrySeconds = (_retrySeconds * 2).clamp(2, 10).toInt();
    _retryTimer = Timer(wait, () {
      _retryTimer = null;
      unawaited(catchUp(force: true));
    });
  }

  void _stopCatchUp() {
    _catchUpTimer?.cancel();
    _catchUpTimer = null;
    _retryTimer?.cancel();
    _retryTimer = null;
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
    fiberAddresses = const [];
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
    _stopCatchUp();
    await _fiberSub?.cancel();
    _fiberSub = null;
    account = null;
    viewingAccount = false;
    fiberNode = null;
    fiberAddresses = const [];
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
    nostr.onRelayDropped = null;
    _stopCatchUp();
    market?.stop();
    _fiberSub?.cancel();
    super.dispose();
  }
}