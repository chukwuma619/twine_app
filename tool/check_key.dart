import 'dart:convert';
import 'dart:io';

import 'package:dart_nostr/dart_nostr.dart';
import 'package:twine_app/nostr/account.dart';

void main() {
  final nostr = Nostr();
  final account = TwineAccount.generate(nostr);
  final event = NostrEvent.fromPartialData(
    kind: 1,
    content: 'twine',
    keyPairs: NostrKeyPairs(private: account.privateKey),
    createdAt: DateTime.fromMillisecondsSinceEpoch(1700000000 * 1000),
  );
  stdout
    ..writeln('KEYCHECK')
    ..writeln(account.nsec)
    ..writeln(account.publicKey)
    ..writeln(jsonEncode(event.toMap()));
}
