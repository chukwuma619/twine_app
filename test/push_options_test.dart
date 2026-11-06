import 'package:flutter_test/flutter_test.dart';
import 'package:twine_app/nostr/daemon.dart';
import 'package:twine_app/session/push_options.dart';

void main() {
  test('push url defaults to the official doorbell', () {
    expect(officialPushUrl, 'https://push.backr.site');
  });

  test('compile-time options are unused until every field is set', () {
    expect(PushFirebaseOptions.fromEnvironment(), isNull);
    const options = PushFirebaseOptions(
      apiKey: 'key',
      appId: '1:2:ios:abc',
      messagingSenderId: '2',
      projectId: 'twine',
    );
    expect(options.usable, isTrue);
  });
}
