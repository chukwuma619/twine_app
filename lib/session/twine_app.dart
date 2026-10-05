import 'dart:async';

import 'package:flutter/material.dart';
import 'package:twine_app/nostr/account.dart';
import 'package:twine_app/nostr/account_store.dart';
import 'package:twine_app/nostr/twine_nostr.dart';
import 'package:twine_app/session/login_page.dart';
import 'package:twine_app/session/relay_status.dart';
import 'package:twine_app/session/signed_in_page.dart';

class TwineApp extends StatefulWidget {
  const TwineApp({
    super.key,
    required this.nostr,
    required this.store,
    this.initialAccount,
    this.connectRelays = false,
  });

  final TwineNostr nostr;
  final AccountStore store;
  final TwineAccount? initialAccount;
  final bool connectRelays;

  @override
  State<TwineApp> createState() => _TwineAppState();
}

class _TwineAppState extends State<TwineApp> {
  static const _invalidKey = 'Enter an nsec or a 64-character hex key.';
  static const _publicKeyPasted = 'That is the public key. Paste the nsec.';
  static const _saveFailed = 'Could not save the key on this device.';
  static const _removeFailed = 'Could not remove the key from this device.';

  TwineAccount? _account;
  bool _showBackup = false;
  bool _busy = false;
  String? _error;
  String? _logoutError;
  List<String> _relays = const [];
  String? _relayError;
  bool _connecting = false;

  @override
  void initState() {
    super.initState();
    _account = widget.initialAccount;
    widget.nostr.account = _account;
    if (widget.connectRelays) {
      _connecting = true;
      unawaited(_connect());
    }
  }

  Future<void> _connect() async {
    try {
      final open = await widget.nostr.connect();
      if (!mounted) return;
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
    setState(() {
      _account = account;
      _showBackup = false;
      _busy = false;
    });
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
    setState(() {
      _account = null;
      _showBackup = false;
      _error = null;
      _logoutError = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final status = RelayStatus(
      connecting: _connecting,
      relays: _relays,
      error: _relayError,
    );
    final account = _account;
    final Widget home;
    if (account == null) {
      home = LoginPage(
        onCreate: _create,
        onImport: _import,
        busy: _busy,
        error: _error,
        relayStatus: status,
      );
    } else if (_showBackup) {
      home = BackupPage(
        nsec: account.nsec,
        onContinue: () => setState(() => _showBackup = false),
        relayStatus: status,
      );
    } else {
      home = SignedInPage(
        account: account,
        onLogOut: _logOut,
        relayStatus: status,
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
