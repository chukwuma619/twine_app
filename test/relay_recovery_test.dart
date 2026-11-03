import 'package:flutter_test/flutter_test.dart';
import 'package:twine_app/nostr/twine_nostr.dart';

void main() {
  test('a relay that answers keeps the sockets', () {
    final plan = planRelayRecovery(
      force: false,
      socketsOpen: true,
      probeAnswered: true,
      quietProbes: 4,
      cooledDown: true,
    );

    expect(plan.replace, isFalse);
    expect(plan.quietProbes, 0);
  });

  test('one quiet probe leaves an open socket in place', () {
    final plan = planRelayRecovery(
      force: false,
      socketsOpen: true,
      probeAnswered: false,
      quietProbes: 0,
      cooledDown: true,
    );

    expect(plan.replace, isFalse);
    expect(plan.quietProbes, 1);
  });

  test('a second quiet probe replaces an open socket', () {
    final plan = planRelayRecovery(
      force: false,
      socketsOpen: true,
      probeAnswered: false,
      quietProbes: 1,
      cooledDown: true,
    );

    expect(plan.replace, isTrue);
    expect(plan.quietProbes, 0);
  });

  test('a closed socket is replaced on the first quiet probe', () {
    final plan = planRelayRecovery(
      force: false,
      socketsOpen: false,
      probeAnswered: false,
      quietProbes: 0,
      cooledDown: true,
    );

    expect(plan.replace, isTrue);
  });

  test('a fresh dial is not torn down before it can answer', () {
    final plan = planRelayRecovery(
      force: false,
      socketsOpen: false,
      probeAnswered: false,
      quietProbes: 3,
      cooledDown: false,
    );

    expect(plan.replace, isFalse);
    expect(plan.quietProbes, 4);
  });

  test('returning to the app dials again', () {
    final plan = planRelayRecovery(
      force: true,
      socketsOpen: true,
      probeAnswered: true,
      quietProbes: 0,
      cooledDown: false,
    );

    expect(plan.replace, isTrue);
    expect(plan.quietProbes, 0);
  });
}
