/// The daemon this install is pointed at, kept on this device.
library;

import 'dart:convert';

import 'package:dart_nostr/dart_nostr.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../nostr/daemon.dart';
import 'secure_storage.dart';

abstract class DaemonStore {
  Future<TwineDaemon?> read();

  Future<void> write(TwineDaemon daemon);

  Future<void> clear();
}

class MemoryDaemonStore implements DaemonStore {
  TwineDaemon? daemon;

  @override
  Future<TwineDaemon?> read() async => daemon;

  @override
  Future<void> write(TwineDaemon daemon) async {
    this.daemon = daemon;
  }

  @override
  Future<void> clear() async {
    daemon = null;
  }
}

class SecureDaemonStore implements DaemonStore {
  SecureDaemonStore(this._nostr, {FlutterSecureStorage? storage})
    : _storage = storage ?? twineSecureStorage();

  static const _daemonKey = 'twine_daemon';

  final Nostr _nostr;
  final FlutterSecureStorage _storage;

  @override
  Future<TwineDaemon?> read() async {
    final saved = await _storage.read(key: _daemonKey);
    if (saved == null || saved.isEmpty) return null;
    final daemon = _decode(saved);
    if (daemon == null) {
      await _storage.delete(key: _daemonKey);
    }
    return daemon;
  }

  @override
  Future<void> write(TwineDaemon daemon) {
    return _storage.write(key: _daemonKey, value: _encode(daemon));
  }

  @override
  Future<void> clear() {
    return _storage.delete(key: _daemonKey);
  }

  TwineDaemon? _decode(String saved) {
    try {
      final decoded = jsonDecode(saved);
      if (decoded is! Map) return null;
      final pubkey = decoded['publicKey'];
      final relays = decoded['relays'];
      if (pubkey is! String || relays is! List) return null;
      return TwineDaemon.tryParse(
        _nostr,
        pubkey: pubkey,
        relays: relays.whereType<String>().join(','),
      );
    } catch (_) {
      return null;
    }
  }

  String _encode(TwineDaemon daemon) {
    return jsonEncode({'publicKey': daemon.publicKey, 'relays': daemon.relays});
  }
}
