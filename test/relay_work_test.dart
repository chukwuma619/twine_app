import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:twine_app/session/relay_work.dart';

void main() {
  test('a resume during a probe dials after the probe', () async {
    final work = RelayWork();
    final passes = <bool>[];
    final probe = work.run(
      replace: false,
      body: (replace) async {
        passes.add(replace);
        await Future<void>.delayed(const Duration(milliseconds: 10));
      },
    );
    final resume = work.run(
      replace: true,
      body: (replace) async {
        passes.add(replace);
      },
    );

    await probe;
    await resume;
    expect(passes, [false, true]);
  });

  test('a second resume during a redial runs one more dial', () async {
    final work = RelayWork();
    final passes = <bool>[];
    var release = false;
    final first = work.run(
      replace: true,
      body: (replace) async {
        passes.add(replace);
        while (!release) {
          await Future<void>.delayed(const Duration(milliseconds: 5));
        }
      },
    );
    final second = work.run(
      replace: true,
      body: (replace) async {
        passes.add(replace);
      },
    );

    release = true;
    await first;
    await second;
    expect(passes, [true, true]);
  });

  test('a probe during a redial does not add a pass', () async {
    final work = RelayWork();
    final passes = <bool>[];
    var release = false;
    final dial = work.run(
      replace: true,
      body: (replace) async {
        passes.add(replace);
        while (!release) {
          await Future<void>.delayed(const Duration(milliseconds: 5));
        }
      },
    );
    final probe = work.run(
      replace: false,
      body: (replace) async {
        passes.add(replace);
      },
    );

    release = true;
    await dial;
    await probe;
    expect(passes, [true]);
  });

  test('a queued resume is visible while a probe is running', () async {
    final work = RelayWork();
    var release = false;
    final probe = work.run(
      replace: false,
      body: (_) async {
        while (!release) {
          await Future<void>.delayed(const Duration(milliseconds: 5));
        }
      },
    );
    unawaited(work.run(replace: true, body: (_) async {}));
    expect(work.replaceQueued, isTrue);
    release = true;
    await probe;
  });
}
