import 'role.dart';

enum ChannelRole { seller, buyer, both }

ChannelRole channelRoleFor(TradeSide side) {
  switch (side) {
    case TradeSide.seller:
      return ChannelRole.seller;
    case TradeSide.buyer:
      return ChannelRole.buyer;
  }
}

String channelHubSummary() {
  return 'Open a Fiber channel to this hub. '
      'Sellers fund it for outbound liquidity to pay the hold. '
      'Buyers need inbound liquidity: funds on the operator\'s side that can flow to them.';
}

List<String> channelChecklist(ChannelRole role) {
  switch (role) {
    case ChannelRole.seller:
      return const [
        'Open a channel to the operator Fiber node.',
        'Fund it so your outbound liquidity covers the hold.',
      ];
    case ChannelRole.buyer:
      return const [
        'Open a channel to the operator Fiber node.',
        'You need inbound liquidity. Funding alone leaves balance on your side, so you cannot receive.',
        'Have the operator open or dual-fund with funds on their side, or use an LSP / JIT channel.',
      ];
    case ChannelRole.both:
      return const [
        'Open a channel to the operator Fiber node.',
        'To sell: fund it for outbound liquidity.',
        'To buy: get inbound liquidity from the operator before you take.',
      ];
  }
}

String channelReadyLabel(ChannelRole role) {
  switch (role) {
    case ChannelRole.seller:
      return 'My channel is open and I have outbound liquidity for the hold.';
    case ChannelRole.buyer:
      return 'I have inbound liquidity from the operator for this payout.';
    case ChannelRole.both:
      return 'My Fiber channel to the operator is ready for this trade.';
  }
}

String channelConfirmLine(ChannelRole role) {
  switch (role) {
    case ChannelRole.seller:
      return 'Your channel needs outbound liquidity toward the operator.';
    case ChannelRole.buyer:
      return 'Without inbound liquidity from the operator, the payout will fail.';
    case ChannelRole.both:
      return 'Your Fiber channel to the operator must be ready.';
  }
}
