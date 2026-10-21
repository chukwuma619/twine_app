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
  return 'In Fiber Studio, open Network, then Add saved peer. Paste the pubkey and multiaddr and click Add & connect. '
      'Sellers then open Channels, then Open channel, and set at least 1,000 CKB so outbound liquidity covers the hold. '
      'Buyers stay online with 99 CKB on-chain. A laptop node does not need a public IP. Twine opens inbound at payout.';
}

List<String> channelChecklist(ChannelRole role) {
  switch (role) {
    case ChannelRole.seller:
      return const [
        'In Fiber Studio, open Network, then Add saved peer. Paste the pubkey and multiaddr and click Add & connect.',
        'Open Channels, then Open channel. Choose this hub and set at least 1,000 CKB so outbound liquidity covers the hold. Wait until the channel is Ready.',
      ];
    case ChannelRole.buyer:
      return const [
        'In Fiber Studio, open Network, then Add saved peer. Paste the pubkey and multiaddr and click Add & connect. A laptop or home node does not need a public IP.',
        'Stay online with 99 CKB on-chain until payout.',
        'Twine opens inbound to you at payout.',
      ];
    case ChannelRole.both:
      return const [
        'In Fiber Studio, open Network, then Add saved peer. Paste the pubkey and multiaddr and click Add & connect.',
        'To sell: open Channels, then Open channel, with at least 1,000 CKB so outbound liquidity covers the hold.',
        'To buy: stay online with 99 CKB on-chain. Twine opens inbound at payout.',
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
        'This daemon has not announced a public multiaddr yet. Paste it into the multiaddr field when it appears. Fiber Studio marks that field optional; this hub needs it.';
  } else {
    connect =
        'In Fiber Studio, open Network, then Add saved peer. Paste the pubkey and multiaddr below into those fields. The public node buttons fill in a different peer. Click Add & connect.';
  }
  return [
    'Install Fiber Studio and start your node. CKB stays in that wallet.',
    connect,
    'To sell, open Channels, then Open channel. This hub has to show Connected. Choose CKB and set capacity to at least 1,000 CKB so outbound liquidity covers the hold. The wallet needs another 109 CKB for the reserve and fees. Wait until the channel is Ready.',
    'To buy, stay online with this hub connected and keep 99 CKB on-chain. Leave the inbound channel to Twine. A laptop node does not need a public IP. Twine opens it at payout.',
  ];
}
