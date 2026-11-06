import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:twine_app/session/push_wake.dart';

void main() {
  test('a doorbell is consumed once', () {
    final wake = PushWake();
    expect(wake.consume(), isFalse);
    wake.note();
    expect(wake.consume(), isTrue);
    expect(wake.consume(), isFalse);
  });

  test('a background isolate note reaches the bound UI latch', () async {
    final wake = PushWake();
    wake.bind();
    addTearDown(wake.unbind);
    IsolateNameServer.lookupPortByName(pushWakePortName)?.send(true);
    await Future<void>.delayed(Duration.zero);
    expect(wake.consume(), isTrue);
  });
}
