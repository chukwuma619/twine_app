import 'package:flutter_test/flutter_test.dart';
import 'package:twine_app/market/amount.dart';
import 'package:twine_app/market/clocks.dart';
import 'package:twine_app/market/outcome.dart';
import 'package:twine_app/market/phase.dart';

void main() {
  test('remaining time is read from the stored unix deadline', () {
    final now = DateTime.utc(2026, 10, 6, 12);
    expect(
      remainingLabel(DateTime.utc(2026, 10, 6, 14, 5), now),
      '2h 5m left',
    );
    expect(
      remainingLabel(DateTime.utc(2026, 10, 6, 12, 3, 10), now),
      '3m 10s left',
    );
    expect(remainingLabel(DateTime.utc(2026, 10, 6, 11), now), 'Time is up');
    expect(unixSeconds(1700000900), DateTime.utc(2023, 11, 14, 22, 28, 20));
  });

  test('about CKB divides the fiat amount by the posted price', () {
    expect(aboutCkb('1500', '1500'), '1.00');
    expect(aboutCkb('2500', '1500'), '1.67');
    expect(aboutCkb('0', '1500'), isNull);
  });

  test('terminal trades say who has the CKB', () {
    expect(
      tradeOutcome(TradePhase.settled),
      'The buyer received the CKB. Fiat was never held by this app.',
    );
    expect(
      tradeOutcome(TradePhase.expired),
      'The hold expired. The CKB returned to the seller. Fiat was never held by this app.',
    );
    expect(
      tradeOutcome(TradePhase.canceled),
      'This trade ended before the CKB was locked.',
    );
    expect(
      tradeOutcome(TradePhase.refunding),
      'The CKB is returning to the seller. Fiat was never held by this app.',
    );
    expect(tradeOutcome(TradePhase.waitingFiat), isNull);
  });
}
