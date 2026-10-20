import 'package:flutter_test/flutter_test.dart';
import 'package:twine_app/market/channel.dart';
import 'package:twine_app/market/role.dart';

void main() {
  test('channelRoleFor maps trade sides', () {
    expect(channelRoleFor(TradeSide.seller), ChannelRole.seller);
    expect(channelRoleFor(TradeSide.buyer), ChannelRole.buyer);
  });

  test('seller checklist requires outbound liquidity', () {
    final steps = channelChecklist(ChannelRole.seller);
    expect(steps[1], contains('outbound liquidity'));
    expect(channelReadyLabel(ChannelRole.seller), contains('outbound liquidity'));
    expect(channelConfirmLine(ChannelRole.seller), contains('outbound liquidity'));
  });

  test('buyer checklist requires inbound liquidity', () {
    final steps = channelChecklist(ChannelRole.buyer);
    expect(steps[1], contains('inbound liquidity'));
    expect(steps[2], contains('dual-fund'));
    expect(channelReadyLabel(ChannelRole.buyer), contains('inbound liquidity'));
    expect(channelConfirmLine(ChannelRole.buyer), contains('inbound liquidity'));
  });

  test('hub summary covers both legs', () {
    final summary = channelHubSummary();
    expect(summary, contains('outbound liquidity'));
    expect(summary, contains('inbound liquidity'));
  });
}
