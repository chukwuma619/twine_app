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
  return 'In Fiber Studio, add this hub as a saved peer with the pubkey and multiaddr below. '
      'Sellers open a channel and fund outbound liquidity for the hold. '
      'Buyers: a laptop node does not need a public IP. Stay online with auto-accept on. Twine opens inbound at payout.';
}

List<String> channelChecklist(ChannelRole role) {
  switch (role) {
    case ChannelRole.seller:
      return const [
        'In Fiber Studio, add this hub as a saved peer, then open a channel to it.',
        'Fund it so your outbound liquidity covers the hold.',
      ];
    case ChannelRole.buyer:
      return const [
        'In Fiber Studio, add this hub as a saved peer with its pubkey and multiaddr. A laptop or home node does not need a public IP.',
        'Leave auto-accept on (Fiber default) and keep about 99 CKB on-chain.',
        'Keep the node online until payout. Twine then opens inbound to you.',
      ];
    case ChannelRole.both:
      return const [
        'In Fiber Studio, add this hub as a saved peer with its pubkey and multiaddr.',
        'To sell: open and fund a channel for outbound liquidity.',
        'To buy: stay online so Twine can open inbound at payout.',
      ];
  }
}

String channelReadyLabel(ChannelRole role) {
  switch (role) {
    case ChannelRole.seller:
      return 'My channel is open and I have outbound liquidity for the hold.';
    case ChannelRole.buyer:
      return 'My Fiber node will stay online so Twine can open inbound at payout.';
    case ChannelRole.both:
      return 'My Fiber channel to the operator is ready for this trade.';
  }
}

String channelConfirmLine(ChannelRole role) {
  switch (role) {
    case ChannelRole.seller:
      return 'Your channel needs outbound liquidity toward the operator.';
    case ChannelRole.buyer:
      return 'Keep your Fiber node connected to this hub. Twine opens inbound to you at payout if you cannot receive yet.';
    case ChannelRole.both:
      return 'Your Fiber channel to the operator must be ready.';
  }
}

List<String> fiberConnectSteps({
  required bool announced,
  required bool hasMultiaddr,
}) {
  final String connect;
  if (!announced) {
    connect =
        'This daemon has not announced its Fiber node yet. The pubkey and multiaddr appear here when it does.';
  } else if (!hasMultiaddr) {
    connect =
        'This daemon has not announced a public multiaddr yet. Fiber Studio needs that address to connect.';
  } else {
    connect =
        'In Fiber Studio, open Network, then Add saved peer. Paste the pubkey and multiaddr below, then connect.';
  }
  return [
    'Install Fiber Studio and start your node. CKB stays in that wallet.',
    connect,
    'To sell, open a channel to that hub in Fiber Studio and fund it so your outbound liquidity covers the hold.',
    'To buy, leave auto-accept on, keep about 99 CKB on-chain, and stay online. A laptop node does not need a public IP. Twine opens inbound at payout.',
  ];
}
