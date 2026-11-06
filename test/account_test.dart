import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_secure_storage/test/test_flutter_secure_storage_platform.dart';
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twine_app/nostr/account.dart';
import 'package:twine_app/store/account_store.dart';

void main() {
  test('a generated key imports back to the same account', () {
    final created = TwineAccount.generate();
    final imported = TwineAccount.tryParse(created.nsec);

    expect(imported, isNotNull);
    expect(imported!.publicKey, created.publicKey);
    expect(imported.npub, created.npub);
  });

  test('hex secrets import', () {
    final created = TwineAccount.generate();
    final imported = TwineAccount.tryParse(created.privateKey.toUpperCase());

    expect(imported?.publicKey, created.publicKey);
  });

  test('rejects a value that is not a key', () {
    expect(TwineAccount.tryParse('not-a-key'), isNull);
    expect(TwineAccount.tryParse(''), isNull);
    expect(TwineAccount.tryParse('nsec1notakey'), isNull);
    expect(TwineAccount.tryParse('0' * 64), isNull);
    expect(TwineAccount.tryParse('f' * 64), isNull);
  });

  test('secure store restores the key and drops a corrupt one', () async {
    final data = <String, String>{};
    FlutterSecureStoragePlatform.instance = TestFlutterSecureStoragePlatform(
      data,
    );
    final store = SecureAccountStore(storage: const FlutterSecureStorage());
    final account = TwineAccount.generate();

    await store.write(account);
    expect((await store.read())?.publicKey, account.publicKey);

    data[data.keys.single] = 'not-a-key';
    expect(await store.read(), isNull);
    expect(data, isEmpty);
  });

  test('backup confirmation survives a new store', () async {
    final data = <String, String>{};
    FlutterSecureStoragePlatform.instance = TestFlutterSecureStoragePlatform(
      data,
    );
    final store = SecureAccountStore(storage: const FlutterSecureStorage());
    final account = TwineAccount.generate();
    await store.write(account);
    expect(await store.backupConfirmed(), isTrue);

    await store.setBackupConfirmed(false);
    final again = SecureAccountStore(storage: const FlutterSecureStorage());
    expect(await again.backupConfirmed(), isFalse);
    await again.setBackupConfirmed(true);
    expect(await again.backupConfirmed(), isTrue);
  });

  test(
    'a missing fiber guide flag means the steps have not been seen',
    () async {
      final data = <String, String>{};
      FlutterSecureStoragePlatform.instance = TestFlutterSecureStoragePlatform(
        data,
      );
      final store = SecureAccountStore(storage: const FlutterSecureStorage());
      expect(await store.fiberGuideSeen(), isFalse);

      await store.setFiberGuideSeen(true);
      final again = SecureAccountStore(storage: const FlutterSecureStorage());
      expect(await again.fiberGuideSeen(), isTrue);

      await again.clear();
      expect(await again.fiberGuideSeen(), isTrue);
    },
  );

  test('accepts an uppercase nsec', () {
    final created = TwineAccount.generate();
    final imported = TwineAccount.tryParse(created.nsec.toUpperCase());

    expect(imported?.publicKey, created.publicKey);
  });
}
