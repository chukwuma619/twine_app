import 'dart:async';

import 'package:flutter/material.dart';
import 'package:twine_app/nostr/account.dart';
import 'package:twine_app/nostr/account_store.dart';
import 'package:twine_app/nostr/daemon.dart';
import 'package:twine_app/nostr/daemon_store.dart';
import 'package:twine_app/nostr/twine_nostr.dart';
import 'package:twine_app/session/daemon_page.dart';
import 'package:twine_app/session/login_page.dart';
import 'package:twine_app/session/signed_in_page.dart';

class TwineApp extends StatefulWidget {
  const TwineApp({
    super.key,
    required this.nostr,
    required this.store,
    required this.daemonStore,
    this.initialAccount,
    this.initialDaemon,
    this.connectRelays = false,
  });

  final TwineNostr nostr;
  final AccountStore store;
  final DaemonStore daemonStore;
  final TwineAccount? initialAccount;
  final TwineDaemon? initialDaemon;
  final bool connectRelays;

  @override
  State<TwineApp> createState() => _TwineAppState();
}

class _TwineAppState extends State<TwineApp> {
  static const _invalidKey = 'Enter an nsec or a 64-character hex key.';
  static const _publicKeyPasted = 'That is the public key. Paste the nsec.';
  static const _saveFailed = 'Could not save the key on this device.';
  static const _removeFailed = 'Could not remove the key from this device.';
  static const _daemonSecret =
      "That is a secret key. Paste the daemon's public key.";
  static const _daemonPubkey = "Enter the daemon's npub or public key.";
  static const _daemonRelays = 'Enter at least one relay starting with wss://.';
  static const _daemonSaveFailed = 'Could not save this daemon on the device.';

  TwineAccount? _account;
  TwineDaemon? _daemon;
  bool _showBackup = false;
  bool _editingDaemon = false;
  bool _busy = false;
  String? _error;
  String? _logoutError;
  String? _daemonError;
  List<String> _relays = const [];
  String? _relayError;
  bool _connecting = false;

  @override
  void initState() {
    super.initState();
    _account = widget.initialAccount;
    _daemon = widget.initialDaemon;
    widget.nostr.account = _account;
    widget.nostr.daemon = _daemon;
    final daemon = _daemon;
    if (widget.connectRelays && _account != null && daemon != null) {
      _connecting = true;
      unawaited(_connect(daemon.relays));
    }
  }

  Future<void> _connect(List<String> relays) async {
    try {
      final open = await widget.nostr.connect(relays);
      if (!mounted) return;
      widget.nostr.watchReplies();
      setState(() {
        _relays = open;
        _relayError = null;
        _connecting = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _relayError = error is TwineRelayException
            ? error.message
            : 'no nostr relay connected';
        _connecting = false;
      });
    }
  }

  Future<void> _create() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final account = TwineAccount.generate(widget.nostr.nostr);
      await widget.store.write(account);
      if (!mounted) return;
      widget.nostr.account = account;
      setState(() {
        _account = account;
        _showBackup = true;
        _busy = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = _saveFailed;
      });
    }
  }

  Future<void> _import(String secret) async {
    if (_busy) return;
    final trimmed = secret.trim().toLowerCase();
    if (trimmed.startsWith('npub1')) {
      setState(() => _error = _publicKeyPasted);
      return;
    }
    final account = TwineAccount.tryParse(widget.nostr.nostr, secret);
    if (account == null) {
      setState(() => _error = _invalidKey);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.store.write(account);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = _saveFailed;
      });
      return;
    }
    if (!mounted) return;
    widget.nostr.account = account;
    final daemon = _daemon;
    setState(() {
      _account = account;
      _showBackup = false;
      _busy = false;
      _connecting = widget.connectRelays && daemon != null;
    });
    if (widget.connectRelays && daemon != null) {
      unawaited(_connect(daemon.relays));
    }
  }

  Future<void> _saveDaemon(String pubkey, String relays) async {
    if (_busy) return;
    final trimmed = pubkey.trim().toLowerCase();
    if (trimmed.startsWith('nsec1')) {
      setState(() => _daemonError = _daemonSecret);
      return;
    }
    final parsedKey = TwineDaemon.parsePublicKey(widget.nostr.nostr, pubkey);
    if (parsedKey == null) {
      setState(() => _daemonError = _daemonPubkey);
      return;
    }
    final parsedRelays = TwineDaemon.parseRelays(relays);
    if (parsedRelays == null) {
      setState(() => _daemonError = _daemonRelays);
      return;
    }
    final daemon = TwineDaemon(
      publicKey: parsedKey,
      npub: widget.nostr.nostr.bech32.encodePublicKeyToNpub(parsedKey),
      relays: parsedRelays,
    );
    setState(() {
      _busy = true;
      _daemonError = null;
    });
    try {
      await widget.daemonStore.write(daemon);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _daemonError = _daemonSaveFailed;
      });
      return;
    }
    if (!mounted) return;
    widget.nostr.daemon = daemon;
    setState(() {
      _daemon = daemon;
      _editingDaemon = false;
      _busy = false;
      _relays = const [];
      _relayError = null;
      _connecting = widget.connectRelays;
    });
    if (widget.connectRelays) unawaited(_connect(daemon.relays));
  }

  Future<void> _logOut() async {
    try {
      await widget.store.clear();
    } catch (_) {
      if (!mounted) return;
      setState(() => _logoutError = _removeFailed);
      return;
    }
    if (!mounted) return;
    widget.nostr.account = null;
    widget.nostr.stopWatching();
    setState(() {
      _account = null;
      _showBackup = false;
      _editingDaemon = false;
      _error = null;
      _logoutError = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final account = _account;
    final daemon = _daemon;
    final Widget home;
    if (account == null) {
      home = LoginPage(
        onCreate: _create,
        onImport: _import,
        busy: _busy,
        error: _error,
      );
    } else if (_showBackup) {
      home = BackupPage(
        nsec: account.nsec,
        onContinue: () {
          setState(() => _showBackup = false);
          final daemon = _daemon;
          if (widget.connectRelays && daemon != null) {
            setState(() => _connecting = true);
            unawaited(_connect(daemon.relays));
          }
        },
      );
    } else if (daemon == null || _editingDaemon) {
      home = DaemonPage(
        current: _editingDaemon ? daemon : null,
        busy: _busy,
        error: _daemonError,
        onSave: _saveDaemon,
        onCancel: _editingDaemon && daemon != null
            ? () => setState(() {
                _editingDaemon = false;
                _daemonError = null;
              })
            : null,
      );
    } else {
      home = SignedInPage(
        account: account,
        daemon: daemon,
        connecting: _connecting,
        connectedRelays: _relays,
        relayError: _relayError,
        onChangeDaemon: () => setState(() => _editingDaemon = true),
        onLogOut: _logOut,
        error: _logoutError,
      );
    }

    return MaterialApp(
      title: 'Twine',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
      ),
      home: home,
    );
  }
}
