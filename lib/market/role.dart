/// Who this key is on a post, and which buttons that allows.
library;

import '../nostr/order.dart';
import 'phase.dart';

enum TradeSide { seller, buyer }

bool isMaker(TwineOrder order, String pubkey) {
  return order.makerNostrPubkey.toLowerCase() == pubkey.toLowerCase();
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
      dispute: _canDispute(phase) && side != null,
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
