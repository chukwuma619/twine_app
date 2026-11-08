import 'phase.dart';

const recordFiatOwed = 'fiat-owed';
const recordBuyerUnpaid = 'buyer-unpaid';
const recordUnresolved = 'unresolved';

String? recordLabel(String? outcome) {
  switch (outcome) {
    case recordFiatOwed:
      return 'Fiat owed';
    case recordBuyerUnpaid:
      return 'Buyer unpaid';
    case recordUnresolved:
      return 'Unresolved';
    default:
      return null;
  }
}

String? recordLine(String? outcome) {
  switch (outcome) {
    case recordFiatOwed:
      return 'Fiat owed. The CKB returned and the seller still owes that fiat. This desk cannot move it.';
    case recordBuyerUnpaid:
      return 'Buyer unpaid. The solver found the buyer did not pay.';
    case recordUnresolved:
      return 'Unresolved. The solver window ended with no decision. The CKB still returns to the seller.';
    default:
      return null;
  }
}

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
    case TradePhase.awaitingRoute:
    case TradePhase.waitingFiat:
    case TradePhase.fiatSent:
    case TradePhase.releasing:
    case TradePhase.awaitingInvoice:
    case TradePhase.disputed:
      return null;
  }
}
