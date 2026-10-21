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
    expect(
      channelReadyLabel(ChannelRole.seller),
      contains('outbound liquidity'),
    );
    expect(
      channelConfirmLine(ChannelRole.seller),
      contains('outbound liquidity'),
    );
  });

  test('buyer checklist is JIT inbound at payout', () {
    final steps = channelChecklist(ChannelRole.buyer);
    expect(steps[0], contains('does not need a public IP'));
    expect(steps[1], contains('auto-accept'));
    expect(channelReadyLabel(ChannelRole.buyer), contains('open inbound'));
    expect(channelConfirmLine(ChannelRole.buyer), contains('opens inbound'));
    expect(steps[0], contains('Fiber Studio'));
  });

  test('hub summary covers both legs', () {
    final summary = channelHubSummary();
    expect(summary, contains('outbound liquidity'));
    expect(summary, contains('opens inbound'));
  });

  test('connect steps point at Fiber Studio and the broadcast multiaddr', () {
    final waiting = fiberConnectSteps(announced: false, hasMultiaddr: false);
    expect(waiting, hasLength(4));
    expect(waiting[0], contains('Fiber Studio'));
    expect(waiting[1], contains('has not announced'));
    expect(waiting[2], contains('outbound liquidity'));
    expect(waiting[3], contains('does not need a public IP'));

    final pubkeyOnly = fiberConnectSteps(announced: true, hasMultiaddr: false);
    expect(pubkeyOnly[1], contains('public multiaddr'));

    final ready = fiberConnectSteps(announced: true, hasMultiaddr: true);
    expect(ready[1], contains('Add saved peer'));
  });
}
