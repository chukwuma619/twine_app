/// The posts and trades kept on this device, per account and daemon.
library;

import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../market/book.dart';
import 'secure_storage.dart';

abstract class BookStore {
  Future<TwineBook?> read(String accountPubkey, String daemonPubkey);

  Future<void> write(String accountPubkey, String daemonPubkey, TwineBook book);

  Future<void> clear(String accountPubkey, String daemonPubkey);
}

class MemoryBookStore implements BookStore {
  final books = <String, TwineBook>{};

  @override
  Future<TwineBook?> read(String accountPubkey, String daemonPubkey) async {
    return books[_key(accountPubkey, daemonPubkey)];
  }

  @override
  Future<void> write(
    String accountPubkey,
    String daemonPubkey,
    TwineBook book,
  ) async {
    books[_key(accountPubkey, daemonPubkey)] = book;
  }

  @override
  Future<void> clear(String accountPubkey, String daemonPubkey) async {
    books.remove(_key(accountPubkey, daemonPubkey));
  }
}

class SecureBookStore implements BookStore {
  SecureBookStore({FlutterSecureStorage? storage})
    : _storage = storage ?? twineSecureStorage();

  final FlutterSecureStorage _storage;

  @override
  Future<TwineBook?> read(String accountPubkey, String daemonPubkey) async {
    final key = _key(accountPubkey, daemonPubkey);
    final saved = await _storage.read(key: key);
    if (saved == null || saved.isEmpty) return null;
    try {
      final book = TwineBook.fromJson(jsonDecode(saved));
      if (book == null) {
        await _storage.delete(key: key);
      }
      return book;
    } catch (_) {
      await _storage.delete(key: key);
      return null;
    }
  }

  @override
  Future<void> write(
    String accountPubkey,
    String daemonPubkey,
    TwineBook book,
  ) {
    return _storage.write(
      key: _key(accountPubkey, daemonPubkey),
      value: jsonEncode(book.toJson()),
    );
  }

  @override
  Future<void> clear(String accountPubkey, String daemonPubkey) {
    return _storage.delete(key: _key(accountPubkey, daemonPubkey));
  }
}

String _key(String accountPubkey, String daemonPubkey) {
  return 'twine_book_${accountPubkey}_$daemonPubkey';
}
