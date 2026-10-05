import 'package:flutter_test/flutter_test.dart';
import 'package:twine_app/nostr/relays.dart';
import 'package:twine_app/nostr/twine_nostr.dart';

void main() {
  test('uses the daemon relay list', () {
    expect(twineRelays, ['wss://relay.damus.io', 'wss://nos.lol']);
  });

  test('rejects a relay that is not a websocket', () {
    final client = TwineNostr();
    expect(
      () => client.connect(relays: ['https://example.com']),
      throwsA(isA<TwineRelayException>()),
    );
  });
}
