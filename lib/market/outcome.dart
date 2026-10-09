import 'phase.dart';

String? tradeOutcome(TradePhase phase) {
  switch (phase) {
    case TradePhase.settled:
      return 'The buyer received the CKB. Fiat was never held by this app.';
    case TradePhase.expired:
      return 'The hold expired. The CKB returned to the seller. Fiat was never held by this app.';
    case TradePhase.canceled:
      return 'This trade ended before the CKB was locked.';
    case TradePhase.refunding:
      return 'The CKB is returning to the seller. Fiat was never held by this app.';
    case TradePhase.waitingInvoice:
    case TradePhase.waitingHold:
    case TradePhase.waitingFiat:
    case TradePhase.fiatSent:
    case TradePhase.releasing:
    case TradePhase.awaitingInvoice:
    case TradePhase.disputed:
      return null;
  }
}
