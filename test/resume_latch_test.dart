import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twine_app/session/resume_latch.dart';

void main() {
  test('a permission dialog does not dial', () {
    final latch = ResumeLatch();

    expect(latch.observe(AppLifecycleState.inactive), isFalse);
    expect(latch.observe(AppLifecycleState.resumed), isFalse);
  });

  test('unlocking the screen dials', () {
    final latch = ResumeLatch();

    expect(latch.observe(AppLifecycleState.paused), isFalse);
    expect(latch.observe(AppLifecycleState.inactive), isFalse);
    expect(latch.observe(AppLifecycleState.resumed), isTrue);
    expect(latch.observe(AppLifecycleState.resumed), isFalse);
  });

  test('switching back to the app dials', () {
    final latch = ResumeLatch();

    expect(latch.observe(AppLifecycleState.hidden), isFalse);
    expect(latch.observe(AppLifecycleState.inactive), isFalse);
    expect(latch.observe(AppLifecycleState.resumed), isTrue);
  });

  test('leaving again cancels a resume that has not run', () {
    final latch = ResumeLatch();

    latch.observe(AppLifecycleState.paused);
    expect(latch.observe(AppLifecycleState.resumed), isTrue);
    latch.observe(AppLifecycleState.paused);
    expect(latch.suspended, isTrue);
  });
}
