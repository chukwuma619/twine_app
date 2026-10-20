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
  return 'Connect your Fiber node to this hub (outbound). '
      'Sellers fund a channel for outbound liquidity to pay the hold. '
      'Buyers: a laptop node does not need a public IP. Stay online with auto-accept on. Twine opens inbound at payout.';
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
        'Connect your Fiber node to this hub. A laptop or home node does not need a public IP.',
        'Leave auto-accept on (Fiber default) and keep about 99 CKB on-chain.',
        'Keep the node online until payout. Twine then opens inbound to you.',
      ];
    case ChannelRole.both:
      return const [
        'Connect your Fiber node to this hub (outbound).',
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

String channelConnectCommand(String pubkey, List<String> addresses) {
  if (addresses.isEmpty) {
    return 'fnn-cli peer connect_peer --pubkey $pubkey --save true';
  }
  return "fnn-cli peer connect_peer --pubkey $pubkey --address '${addresses.first}' --save true";
}
