/// Posts on this daemon, and the trades this key is part of.
library;

import 'package:flutter/material.dart';

import '../market/role.dart';
import '../nostr/order.dart';
import 'market.dart';
import 'post_page.dart';
import 'take_page.dart';
import 'trade_page.dart';

class MarketPage extends StatelessWidget {
  const MarketPage({
    super.key,
    required this.market,
    required this.onAccount,
    this.fiberNode,
    this.connecting = false,
    this.linked = false,
    this.relayError,
  });

  final TwineMarket market;
  final VoidCallback onAccount;
  final String? fiberNode;
  final bool connecting;
  final bool linked;
  final String? relayError;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: market,
      builder: (context, _) {
        return DefaultTabController(
          length: 2,
          child: Scaffold(
            appBar: AppBar(
              title: const Text('Twine'),
              actions: [
                TextButton(onPressed: onAccount, child: const Text('Account')),
              ],
              bottom: const TabBar(
                tabs: [
                  Tab(text: 'Posts'),
                  Tab(text: 'Trades'),
                ],
              ),
            ),
            floatingActionButton: FloatingActionButton.extended(
              onPressed: market.ready && !market.sending
                  ? () => _openPost(context)
                  : null,
              label: const Text('Post'),
            ),
            body: Column(
              children: [
                _Status(
                  market: market,
                  fiberNode: fiberNode,
                  connecting: connecting,
                  linked: linked,
                  relayError: relayError,
                ),
                Expanded(
                  child: TabBarView(
                    children: [
                      _Posts(market: market),
                      _Trades(market: market),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _openPost(BuildContext context) {
    return Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (context) => _LivePost(market: market)),
    );
  }
}

class _LivePost extends StatelessWidget {
  const _LivePost({required this.market});

  final TwineMarket market;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: market,
      builder: (context, _) {
        return PostPage(
          fiberPubkey: market.fiberPubkey,
          catalog: market.book.catalog,
          onSubmit: market.post,
        );
      },
    );
  }
}

class _Status extends StatelessWidget {
  const _Status({
    required this.market,
    required this.connecting,
    required this.linked,
    this.fiberNode,
    this.relayError,
  });

  final TwineMarket market;
  final String? fiberNode;
  final bool connecting;
  final bool linked;
  final String? relayError;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final lines = <Widget>[];
    if (!market.ready) {
      lines.add(const Text('Opening the book…'));
    }
    if (market.awaitingPost) {
      lines.add(const Text('Waiting for the post to appear.'));
    }
    if (market.awaitingTake) {
      lines.add(const Text('Waiting for the hold invoice.'));
    }
    final status = market.status;
    if (status != null) lines.add(Text(status));
    final notice = market.book.notice;
    if (notice != null) {
      lines.add(_errorLine(theme, notice));
    }
    if (relayError != null) {
      lines.add(_errorLine(theme, relayError!));
    } else if (connecting) {
      lines.add(const Text('Connecting to relays…'));
    } else if (fiberNode != null) {
      lines.add(Text('Fiber node', style: theme.textTheme.titleSmall));
      lines.add(SelectableText(fiberNode!));
    } else if (linked) {
      lines.add(const Text('Waiting for the Fiber node…'));
    }
    if (lines.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < lines.length; i++) ...[
            if (i > 0) const SizedBox(height: 8),
            lines[i],
          ],
        ],
      ),
    );
  }
}

class _Posts extends StatelessWidget {
  const _Posts({required this.market});

  final TwineMarket market;

  @override
  Widget build(BuildContext context) {
    final orders = market.book.orders;
    if (orders.isEmpty) {
      return ListView(
        padding: const EdgeInsets.all(24),
        children: const [Text('No posts yet.')],
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 88),
      itemCount: orders.length,
      separatorBuilder: (context, index) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        return _PostCard(market: market, order: orders[index]);
      },
    );
  }
}

class _PostCard extends StatelessWidget {
  const _PostCard({required this.market, required this.order});

  final TwineMarket market;
  final TwineOrder order;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mine = isMaker(order, market.accountPubkey);
    final open = market.book.openTradeFor(order.orderId);
    final listed = order.status == PostStatus.open;
    final methods = order.paymentMethods
        .map((method) => method.label)
        .join(', ');
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${order.side.label} · ${order.availableCkb} CKB',
              style: theme.textTheme.titleMedium,
            ),
            if (mine) ...[const SizedBox(height: 4), const Text('Yours')],
            if (!listed) ...[const SizedBox(height: 4), const Text('Canceled')],
            const SizedBox(height: 8),
            Text('${order.pricePerCkb} ${order.fiatCurrency} per CKB'),
            Text('${order.min}–${order.max} ${order.fiatCurrency}'),
            Text(methods),
            Text('${order.holdHours} hour hold'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                if (open != null)
                  TextButton(
                    onPressed: () => _openTrade(context, open.id),
                    child: const Text('Trade'),
                  ),
                if (listed && open == null && !mine && order.hasCkb)
                  TextButton(
                    onPressed: market.sending ? null : () => _openTake(context),
                    child: const Text('Take'),
                  ),
                if (listed && mine && open == null)
                  TextButton(
                    onPressed: market.sending ? null : () => _cancel(context),
                    child: const Text('Cancel post'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _openTrade(BuildContext context, String tradeId) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => TradePage(market: market, tradeId: tradeId),
      ),
    );
  }

  void _openTake(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => TakePage(market: market, orderId: order.orderId),
      ),
    );
  }

  Future<void> _cancel(BuildContext context) async {
    final confirmed = await _confirm(
      context,
      'Cancel this post?',
      'This removes it from the book.',
    );
    if (!confirmed) return;
    await market.cancelOrder(order.orderId);
  }
}

class _Trades extends StatelessWidget {
  const _Trades({required this.market});

  final TwineMarket market;

  @override
  Widget build(BuildContext context) {
    final trades = market.book.trades;
    if (trades.isEmpty) {
      return ListView(
        padding: const EdgeInsets.all(24),
        children: const [Text('No trades yet.')],
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 88),
      itemCount: trades.length,
      separatorBuilder: (context, index) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final trade = trades[index];
        final order = market.book.order(trade.orderId);
        final title = order == null
            ? trade.phase.label
            : '${order.side.label} · ${trade.phase.label}';
        final detail = trade.fiatAmount == null
            ? trade.id
            : '${trade.fiatAmount} ${trade.fiatCurrency ?? order?.fiatCurrency ?? ''}';
        return Card(
          child: ListTile(
            title: Text(title),
            subtitle: Text(detail),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (context) =>
                      TradePage(market: market, tradeId: trade.id),
                ),
              );
            },
          ),
        );
      },
    );
  }
}

Text _errorLine(ThemeData theme, String message) {
  return Text(
    message,
    style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.error),
  );
}

Future<bool> _confirm(BuildContext context, String title, String body) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) {
      return AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Back'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Confirm'),
          ),
        ],
      );
    },
  );
  return confirmed == true;
}
