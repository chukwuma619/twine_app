import 'package:flutter_test/flutter_test.dart';
import 'package:twine_app/nostr/fiber_node.dart';

void main() {
  test('a fiber node announcement names the pubkey', () {
    expect(openFiberNode('{"pubkey":"02abc"}'), '02abc');
    expect(openFiberNode('{"pubkey":""}'), isNull);
    expect(FiberAnnouncement.fromContent('not-json'), isNull);
  });

  test('a fiber node announcement names the solver or null', () {
    final without = FiberAnnouncement.fromContent('{"pubkey":"02abc"}');
    expect(without?.hasSolverField, isFalse);
    expect(without?.solver, isNull);

    final none = FiberAnnouncement.fromContent(
      '{"pubkey":"02abc","solver":null}',
    );
    expect(none?.hasSolverField, isTrue);
    expect(none?.solverConfigured, isFalse);

    final solver = FiberAnnouncement.fromContent(
      '{"pubkey":"02abc","solver":"npub1solver"}',
    );
    expect(solver?.solver, 'npub1solver');
    expect(solver?.solverConfigured, isTrue);
    expect(solver?.solverWindowSecs, isNull);

    final timed = FiberAnnouncement.fromContent(
      '{"pubkey":"02abc","solver":"npub1solver","solver_window_secs":14400}',
    );
    expect(timed?.solverWindowSecs, 14400);
  });

  test('a fiber node announcement can name public listen addresses', () {
    final announcement = FiberAnnouncement.fromContent(
      '{"pubkey":"02abc","solver":null,"addresses":["/ip4/1.2.3.4/tcp/8228"]}',
    );
    expect(announcement?.addresses, ['/ip4/1.2.3.4/tcp/8228']);
  });
}
