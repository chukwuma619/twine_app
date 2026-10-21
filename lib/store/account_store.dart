import 'package:dart_nostr/dart_nostr.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../nostr/account.dart';
import 'secure_storage.dart';

abstract class AccountStore {
  Future<TwineAccount?> read();

  Future<void> write(TwineAccount account);

  Future<void> clear();

  Future<bool> backupConfirmed();

  Future<void> setBackupConfirmed(bool confirmed);

  Future<bool> fiberGuideSeen();

  Future<void> setFiberGuideSeen(bool seen);
}

/// Keeps the secret in memory. Used by tests and anywhere a keychain is absent.
class MemoryAccountStore implements AccountStore {
  TwineAccount? account;
  bool confirmedBackup = true;

  bool sawFiberGuide = true;

  @override
  Future<TwineAccount?> read() async => account;

  @override
  Future<void> write(TwineAccount account) async {
    this.account = account;
  }

  @override
  Future<void> clear() async {
    account = null;
    confirmedBackup = true;
  }

  @override
  Future<bool> backupConfirmed() async => confirmedBackup;

  @override
  Future<void> setBackupConfirmed(bool confirmed) async {
    confirmedBackup = confirmed;
  }

  @override
  Future<bool> fiberGuideSeen() async => sawFiberGuide;

  @override
  Future<void> setFiberGuideSeen(bool seen) async {
    sawFiberGuide = seen;
  }
}

class SecureAccountStore implements AccountStore {
  SecureAccountStore(this._nostr, {FlutterSecureStorage? storage})
    : _storage = storage ?? twineSecureStorage();

  static const _secretKey = 'twine_nostr_secret';
  static const _backupKey = 'twine_backup_ack';
  static const _fiberGuideKey = 'twine_fiber_guide';

  final Nostr _nostr;
  final FlutterSecureStorage _storage;

  @override
  Future<TwineAccount?> read() async {
    final saved = await _storage.read(key: _secretKey);
    if (saved == null || saved.isEmpty) return null;
    final account = TwineAccount.tryParse(_nostr, saved);
    if (account == null) {
      await _storage.delete(key: _secretKey);
    }
    return account;
  }

  @override
  Future<void> write(TwineAccount account) {
    return _storage.write(key: _secretKey, value: account.privateKey);
  }

  @override
  Future<void> clear() async {
    await _storage.delete(key: _secretKey);
    await _storage.delete(key: _backupKey);
  }

  @override
  Future<bool> backupConfirmed() async {
    final saved = await _storage.read(key: _backupKey);
    if (saved == null) return true;
    return saved == '1';
  }

  @override
  Future<void> setBackupConfirmed(bool confirmed) {
    return _storage.write(key: _backupKey, value: confirmed ? '1' : '0');
  }

  @override
  Future<bool> fiberGuideSeen() async {
    final saved = await _storage.read(key: _fiberGuideKey);
    return saved == '1';
  }

  @override
  Future<void> setFiberGuideSeen(bool seen) {
    return _storage.write(key: _fiberGuideKey, value: seen ? '1' : '0');
  }
}
