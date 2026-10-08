import '../nostr/order.dart';
import 'phase.dart';
import 'trade.dart';

enum TradeSide { seller, buyer }

bool isMaker(TwineOrder order, String pubkey) {
  return order.makerNostrPubkey.toLowerCase() == pubkey.toLowerCase();
}

TradeSide? sideOn(TwineTrade trade, String pubkey, TwineOrder? order) {
  final me = pubkey.toLowerCase();
  final seller = trade.sellerNostr?.toLowerCase();
  final buyer = trade.buyerNostr?.toLowerCase();
  if (seller != null && seller == me) return TradeSide.seller;
  if (buyer != null && buyer == me) return TradeSide.buyer;
  if (order == null) return null;
  return tradeSide(order, pubkey);
}

/// The other person on [trade], once the daemon has named both keys.
String? counterparty(TwineTrade trade, String pubkey) {
  final seller = trade.sellerNostr;
  final buyer = trade.buyerNostr;
  if (seller == null || buyer == null) return null;
  final me = pubkey.toLowerCase();
  if (seller.toLowerCase() == me) return buyer;
  if (buyer.toLowerCase() == me) return seller;
  return null;
}

TradeSide tradeSide(TwineOrder order, String pubkey) {
  final maker = isMaker(order, pubkey);
  switch (order.side) {
    case OrderSide.sell:
      return maker ? TradeSide.seller : TradeSide.buyer;
    case OrderSide.buy:
      return maker ? TradeSide.buyer : TradeSide.seller;
  }
}

class TradeActions {
  const TradeActions({
    required this.payHold,
    required this.sendFiat,
    required this.release,
    required this.dispute,
    required this.cancel,
  });

  final bool payHold;
  final bool sendFiat;
  final bool release;
  final bool dispute;
  final bool cancel;

  static TradeActions of({
    required TradePhase phase,
    required TradeSide? side,
    required bool hasHoldInvoice,
    bool? solverAvailable,
  }) {
    return TradeActions(
      payHold:
          side == TradeSide.seller &&
          phase == TradePhase.waitingHold &&
          hasHoldInvoice,
      sendFiat:
          side == TradeSide.buyer &&
          (phase == TradePhase.waitingFiat ||
              phase == TradePhase.awaitingInvoice ||
              phase == TradePhase.disputed),
      release:
          side == TradeSide.seller &&
          (phase == TradePhase.fiatSent || phase == TradePhase.disputed),
      dispute:
          _canDispute(phase) && side != null && solverAvailable != false,
      cancel: phase == TradePhase.waitingHold && side != null,
    );
  }
}

bool _canDispute(TradePhase phase) {
  switch (phase) {
    case TradePhase.waitingFiat:
    case TradePhase.fiatSent:
    case TradePhase.awaitingInvoice:
      return true;
    case TradePhase.waitingHold:
    case TradePhase.releasing:
    case TradePhase.disputed:
    case TradePhase.refunding:
    case TradePhase.settled:
    case TradePhase.canceled:
    case TradePhase.expired:
      return false;
  }
}
