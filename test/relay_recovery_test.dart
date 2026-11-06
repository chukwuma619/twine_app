import 'package:flutter_test/flutter_test.dart';
import 'package:twine_app/nostr/twine_nostr.dart';

void main() {
  test('a relay that answers keeps the sockets', () {
    final replace = shouldReplaceRelay(
      force: false,
      probeAnswered: true,
      cooledDown: true,
    );

    expect(replace, isFalse);
  });

  test('a miss during the cooldown leaves the new sockets in place', () {
    final replace = shouldReplaceRelay(
      force: false,
      probeAnswered: false,
      cooledDown: false,
    );

    expect(replace, isFalse);
  });

  test('one miss after the cooldown dials again', () {
    final replace = shouldReplaceRelay(
      force: false,
      probeAnswered: false,
      cooledDown: true,
    );

    expect(replace, isTrue);
  });

  test('returning to the app dials again', () {
    final replace = shouldReplaceRelay(
      force: true,
      probeAnswered: true,
      cooledDown: false,
    );

    expect(replace, isTrue);
  });
}
