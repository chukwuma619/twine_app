enum TradePhase {
  waitingInvoice('waiting-invoice', 'Waiting for the invoice'),
  waitingHold('waiting-hold', 'Waiting for the hold'),
  waitingFiat('waiting-fiat', 'Waiting for fiat'),
  fiatSent('fiat-sent', 'Fiat sent'),
  releasing('releasing', 'Releasing'),
  awaitingInvoice('awaiting-invoice', 'Needs a new invoice'),
  disputed('disputed', 'Disputed'),
  refunding('refunding', 'Refunding'),
  settled('settled', 'Settled'),
  canceled('canceled', 'Canceled'),
  expired('expired', 'Expired');

  const TradePhase(this.wire, this.label);

  final String wire;
  final String label;

  bool get terminal {
    switch (this) {
      case TradePhase.settled:
      case TradePhase.canceled:
      case TradePhase.expired:
        return true;
      case TradePhase.waitingInvoice:
      case TradePhase.waitingHold:
      case TradePhase.waitingFiat:
      case TradePhase.fiatSent:
      case TradePhase.releasing:
      case TradePhase.awaitingInvoice:
      case TradePhase.disputed:
      case TradePhase.refunding:
        return false;
    }
  }

  static TradePhase? parse(String value) {
    for (final phase in TradePhase.values) {
      if (phase.wire == value) return phase;
    }
    return null;
  }
}

/// Whether a reply may move a trade from [current] to [next].
/// A finished trade stays finished. An older reply cannot walk it backwards.
bool canEnter(TradePhase? current, TradePhase next) {
  if (current == null) {
    switch (next) {
      case TradePhase.releasing:
        return false;
      case TradePhase.waitingInvoice:
      case TradePhase.waitingHold:
      case TradePhase.waitingFiat:
      case TradePhase.fiatSent:
      case TradePhase.awaitingInvoice:
      case TradePhase.disputed:
      case TradePhase.refunding:
      case TradePhase.settled:
      case TradePhase.canceled:
      case TradePhase.expired:
        return true;
    }
  }
  if (current.terminal) return false;
  if (current == next) return true;
  switch (next) {
    case TradePhase.waitingInvoice:
      return false;
    case TradePhase.waitingHold:
      return current == TradePhase.waitingInvoice;
    case TradePhase.waitingFiat:
      return current == TradePhase.waitingHold;
    case TradePhase.fiatSent:
      return current == TradePhase.waitingHold ||
          current == TradePhase.waitingFiat;
    case TradePhase.releasing:
      return current == TradePhase.fiatSent || current == TradePhase.disputed;
    case TradePhase.awaitingInvoice:
      return current == TradePhase.releasing ||
          current == TradePhase.fiatSent ||
          current == TradePhase.waitingFiat ||
          current == TradePhase.disputed;
    case TradePhase.disputed:
      return current == TradePhase.waitingFiat ||
          current == TradePhase.fiatSent ||
          current == TradePhase.awaitingInvoice;
    case TradePhase.refunding:
    case TradePhase.settled:
    case TradePhase.canceled:
    case TradePhase.expired:
      return true;
  }
}
