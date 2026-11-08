import 'phase.dart';
import 'role.dart';

/// The title one person should see for this stage of a trade.
String tradeTitle(TradePhase phase, TradeSide? side) {
  switch (phase) {
    case TradePhase.waitingInvoice:
      switch (side) {
        case TradeSide.buyer:
          return 'Create the payout invoice';
        case TradeSide.seller:
          return "Waiting for the buyer's invoice";
        case null:
          return 'Waiting for the invoice';
      }
    case TradePhase.waitingHold:
      switch (side) {
        case TradeSide.seller:
          return 'Lock the CKB';
        case TradeSide.buyer:
          return 'Waiting for the seller';
        case null:
          return 'Waiting for the hold';
      }
    case TradePhase.awaitingRoute:
      switch (side) {
        case TradeSide.buyer:
          return 'Make the wallet able to receive';
        case TradeSide.seller:
        case null:
          return 'Waiting for the buyer wallet';
      }
    case TradePhase.waitingFiat:
      switch (side) {
        case TradeSide.seller:
          return 'Share your account';
        case TradeSide.buyer:
          return 'Pay the seller';
        case null:
          return 'Waiting for payment';
      }
    case TradePhase.fiatSent:
      switch (side) {
        case TradeSide.seller:
          return 'Check the payment';
        case TradeSide.buyer:
          return 'Waiting for the CKB';
        case null:
          return 'Payment marked sent';
      }
    case TradePhase.releasing:
      return 'Sending the CKB';
    case TradePhase.awaitingInvoice:
      switch (side) {
        case TradeSide.buyer:
          return 'Send the same invoice again';
        case TradeSide.seller:
        case null:
          return 'Waiting for the same invoice';
      }
    case TradePhase.disputed:
      return 'Disputed';
    case TradePhase.refunding:
      return 'Returning the CKB';
    case TradePhase.settled:
      return 'Settled';
    case TradePhase.canceled:
      return 'Canceled';
    case TradePhase.expired:
      return 'Expired';
  }
}
