import 'package:flutter/material.dart';

import '../market/role.dart';
import '../market/steps.dart';
import '../nostr/order.dart';
import 'market.dart';
import 'post_page.dart';
import 'take_page.dart';
import 'trade_page.dart';

enum _Section { post, trade, account }

/// Which side of the book is open.
///
/// Buy lists what this key can buy: other people selling, and this key's own
/// buy posts. Sell lists what this key can sell into: other people buying,
/// and this key's own sell posts.
enum _Book { buy, sell }

class MarketPage extends StatefulWidget {
  const MarketPage({
    super.key,
    required this.market,
    required this.account,
    this.fiberNode,
    this.solverAvailable,
    this.connecting = false,
    this.linked = false,
    this.relayError,
    this.connectedRelays = const [],
    this.relayCount = 0,
  });

  final TwineMarket market;
  final Widget account;
  final String? fiberNode;
  final bool? solverAvailable;
  final bool connecting;
  final bool linked;
  final String? relayError;
  final List<String> connectedRelays;
  final int relayCount;

  @override
  State<MarketPage> createState() => _MarketPageState();
}

class _MarketPageState extends State<MarketPage> {
  _Section _section = _Section.post;
  _Book _book = _Book.buy;
  bool _showCanceled = false;

  @override
  Widget build(BuildContext context) {
    final market = widget.market;
    final posting = _section == _Section.post;
    return ListenableBuilder(
      listenable: market,
      builder: (context, _) {
        final canPost =
            posting &&
            market.ready &&
            !market.sending &&
            market.book.catalog.isNotEmpty;
        final title = switch (_section) {
          _Section.post => 'Book',
          _Section.trade => 'Trades',
          _Section.account => 'Account',
        };
        return Scaffold(
          appBar: AppBar(title: Text(title)),
          floatingActionButton: canPost
              ? FloatingActionButton(
                  onPressed: () => _openPost(context),
                  tooltip: 'New post',
                  child: const Icon(Icons.add),
                )
              : null,
          bottomNavigationBar: NavigationBar(
            selectedIndex: switch (_section) {
              _Section.post => 0,
              _Section.trade => 1,
              _Section.account => 2,
            },
            onDestinationSelected: (index) {
              setState(() {
                _section = switch (index) {
                  0 => _Section.post,
                  1 => _Section.trade,
                  _ => _Section.account,
                };
              });
            },
            destinations: const [
              NavigationDestination(
                icon: Icon(Icons.list_alt_outlined),
                selectedIcon: Icon(Icons.list_alt),
                label: 'Post',
              ),
              NavigationDestination(
                icon: Icon(Icons.swap_horiz_outlined),
                selectedIcon: Icon(Icons.swap_horiz),
                label: 'Trade',
              ),
              NavigationDestination(
                icon: Icon(Icons.person_outline),
                selectedIcon: Icon(Icons.person),
                label: 'Account',
              ),
            ],
          ),
          body: _section == _Section.account
              ? Column(
                  children: [
                    _Status(
                      market: market,
                      fiberNode: widget.fiberNode,
                      connecting: widget.connecting,
                      linked: widget.linked,
                      relayError: widget.relayError,
                      partialRelays:
                          widget.linked &&
                          widget.connectedRelays.isNotEmpty &&
                          widget.relayCount > 0 &&
                          widget.connectedRelays.length != widget.relayCount,
                    ),
                    Expanded(child: widget.account),
                  ],
                )
              : Column(
                  children: [
                    if (posting)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                        child: SegmentedButton<_Book>(
                          expandedInsets: EdgeInsets.zero,
                          segments: const [
                            ButtonSegment(
                              value: _Book.buy,
                              label: Text('Buy'),
                            ),
                            ButtonSegment(
                              value: _Book.sell,
                              label: Text('Sell'),
                            ),
                          ],
                          selected: {_book},
                          showSelectedIcon: false,
                          onSelectionChanged: (next) {
                            setState(() => _book = next.first);
                          },
                        ),
                      ),
                    if (posting)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                        child: Text(
                          _book == _Book.buy
                              ? 'Offers to sell CKB'
                              : 'Bids you can fill',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                    if (posting)
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          onPressed: () {
                            setState(() => _showCanceled = !_showCanceled);
                          },
                          child: Text(
                            _showCanceled ? 'Hide canceled' : 'Show canceled',
                          ),
                        ),
                      ),
                    _Status(
                      market: market,
                      fiberNode: widget.fiberNode,
                      connecting: widget.connecting,
                      linked: widget.linked,
                      relayError: widget.relayError,
                      partialRelays:
                          widget.linked &&
                          widget.connectedRelays.isNotEmpty &&
                          widget.relayCount > 0 &&
                          widget.connectedRelays.length != widget.relayCount,
                    ),
                    Expanded(
                      child: posting
                          ? _Posts(
                              market: market,
                              book: _book,
                              showCanceled: _showCanceled,
                              solverAvailable: widget.solverAvailable,
                              fiberNode: widget.fiberNode,
                            )
                          : _Trades(
                              market: market,
                              solverAvailable: widget.solverAvailable,
                              fiberNode: widget.fiberNode,
                            ),
                    ),
                  ],
                ),
        );
      },
    );
  }

  Future<void> _openPost(BuildContext context) async {
    final side = _book == _Book.buy ? OrderSide.buy : OrderSide.sell;
    final posted = await Navigator.of(context).push<OrderSide>(
      MaterialPageRoute<OrderSide>(
        builder: (context) => _LivePost(
          market: widget.market,
          side: side,
          fiberNode: widget.fiberNode,
        ),
      ),
    );
    if (!mounted || posted == null) return;
    setState(() {
      _book = posted == OrderSide.buy ? _Book.buy : _Book.sell;
    });
  }
}

List<TwineOrder> _ordersFor(
  _Book book,
  List<TwineOrder> orders,
  String pubkey,
) {
  return [
    for (final order in orders)
      if (_onBook(book, order, pubkey)) order,
  ];
}

/// A sell is an offer to buy from. Your own post stays on the side you posted.
bool _onBook(_Book book, TwineOrder order, String pubkey) {
  final mine = isMaker(order, pubkey);
  final offeredToBuy = order.side == OrderSide.sell;
  final forBuyers = mine ? !offeredToBuy : offeredToBuy;
  return book == _Book.buy ? forBuyers : !forBuyers;
}

class _LivePost extends StatelessWidget {
  const _LivePost({
    required this.market,
    required this.side,
    this.fiberNode,
  });

  final TwineMarket market;
  final OrderSide side;
  final String? fiberNode;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: market,
      builder: (context, _) {
        return PostPage(
          fiberPubkey: market.fiberPubkey,
          catalog: market.book.catalog,
          initialSide: side,
          fiberNode: fiberNode,
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
    this.partialRelays = false,
  });

  final TwineMarket market;
  final String? fiberNode;
  final bool connecting;
  final bool linked;
  final String? relayError;
  final bool partialRelays;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final lines = <Widget>[];
    if (!market.ready) {
      lines.add(const Text('Opening the book…'));
    }
    if (market.awaitingPost) {
      lines.add(
        const Text('Publishing. You cannot cancel until the daemon lists this post.'),
      );
    }
    if (market.awaitingTake) {
      lines.add(const Text('Opening the trade…'));
    }
    if (partialRelays) {
      lines.add(const Text('Some of the relays you entered are not connected.'));
    }
    final status = market.status;
    if (status != null) lines.add(Text(status));
    final notice = market.book.notice;
    final failed = notice != null || relayError != null;
    if (notice != null) {
      lines.add(_errorLine(theme, notice, onContainer: failed));
    }
    if (relayError != null) {
      lines.add(_errorLine(theme, relayError!, onContainer: failed));
    } else if (connecting) {
      lines.add(const Text('Connecting to relays…'));
    } else if (fiberNode == null && linked) {
      lines.add(const Text('Waiting for the Fiber node…'));
    }
    if (lines.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Card(
        color: failed ? theme.colorScheme.errorContainer : null,
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var i = 0; i < lines.length; i++) ...[
                if (i > 0) const SizedBox(height: 8),
                lines[i],
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Posts extends StatelessWidget {
  const _Posts({
    required this.market,
    required this.book,
    required this.showCanceled,
    this.solverAvailable,
    this.fiberNode,
  });

  final TwineMarket market;
  final _Book book;
  final bool showCanceled;
  final bool? solverAvailable;
  final String? fiberNode;

  @override
  Widget build(BuildContext context) {
    final orders = [
      for (final order in _ordersFor(book, [
        ...market.pending,
        ...market.book.orders,
      ], market.accountPubkey))
        if (showCanceled || order.status != PostStatus.canceled) order,
    ];
    if (orders.isEmpty) {
      return _Empty(
        message: book == _Book.buy
            ? 'No one selling CKB here yet.'
            : 'No buy bids yet.',
        icon: Icons.list_alt_outlined,
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
      itemCount: orders.length,
      separatorBuilder: (context, index) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        return _PostCard(
          market: market,
          order: orders[index],
          solverAvailable: solverAvailable,
          fiberNode: fiberNode,
        );
      },
    );
  }
}

class _PostCard extends StatelessWidget {
  const _PostCard({
    required this.market,
    required this.order,
    this.solverAvailable,
    this.fiberNode,
  });

  final TwineMarket market;
  final TwineOrder order;
  final bool? solverAvailable;
  final String? fiberNode;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mine = isMaker(order, market.accountPubkey);
    final pending = order.orderId.startsWith('local-');
    final open = market.book.openTradeFor(order.orderId);
    final listed = order.status == PostStatus.open;
    final methods = order.paymentMethods
        .map((method) => method.label)
        .join(', ');
    final muted = theme.textTheme.bodyMedium?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final Widget? action;
    if (open != null) {
      action = FilledButton.tonal(
        onPressed: () => _openTrade(context, open.id),
        child: const Text('Trade'),
      );
    } else if (listed && !mine && order.hasCkb) {
      action = FilledButton(
        onPressed: market.sending ? null : () => _openTake(context),
        child: const Text('Take'),
      );
    } else if (listed && mine && !pending) {
      action = TextButton(
        onPressed: market.sending ? null : () => _cancel(context),
        style: TextButton.styleFrom(foregroundColor: theme.colorScheme.error),
        child: const Text('Cancel post'),
      );
    } else {
      action = null;
    }
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        order.side == OrderSide.sell
                            ? 'Offers ${order.availableCkb} CKB'
                            : 'Wants to buy up to ${order.availableCkb} CKB',
                        style: theme.textTheme.titleSmall,
                      ),
                      Text(
                        order.side == OrderSide.sell
                            ? (mine
                                  ? 'You are offering these coins'
                                  : 'This trader is offering CKB')
                            : (mine
                                  ? 'You want these coins'
                                  : 'This trader wants CKB'),
                        style: muted,
                      ),
                      Text(
                        '${order.pricePerCkb} ${order.fiatCurrency}',
                        style: theme.textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text('per CKB', style: muted),
                    ],
                  ),
                ),
                if (action != null) action,
              ],
            ),
            if (mine || !listed) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  if (mine)
                    Chip(
                      label: Text(pending ? 'Publishing' : 'Yours'),
                      visualDensity: VisualDensity.compact,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  if (!listed)
                    const Chip(
                      label: Text('Canceled'),
                      visualDensity: VisualDensity.compact,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  if (listed && !order.hasCkb)
                    const Chip(
                      label: Text('Fully taken'),
                      visualDensity: VisualDensity.compact,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                ],
              ),
            ],
            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 8),
            _Fact(label: 'Available', value: '${order.availableCkb} CKB'),
            if (order.hasReserved)
              _Fact(
                label: 'Reserved',
                value: '${order.reservedCkb} CKB in an open trade',
              ),
            _Fact(
              label: 'Limits',
              value: '${order.min}–${order.max} ${order.fiatCurrency}',
            ),
            if (methods.isNotEmpty) _Fact(label: 'Payment', value: methods),
            _Fact(
              label: 'Fiber hold',
              value: '${_holdLabel(order.holdHours)} locked on Fiber',
            ),
          ],
        ),
      ),
    );
  }

  void _openTrade(BuildContext context, String tradeId) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => TradePage(
          market: market,
          tradeId: tradeId,
          solverAvailable: solverAvailable,
          fiberNode: fiberNode,
        ),
      ),
    );
  }

  void _openTake(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => TakePage(
          market: market,
          orderId: order.orderId,
          fiberNode: fiberNode,
        ),
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

class _Fact extends StatelessWidget {
  const _Fact({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 88,
            child: Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(child: Text(value, textAlign: TextAlign.end)),
        ],
      ),
    );
  }
}

String _holdLabel(int hours) {
  return hours == 1 ? '1 hour' : '$hours hours';
}

class _Trades extends StatelessWidget {
  const _Trades({
    required this.market,
    this.solverAvailable,
    this.fiberNode,
  });

  final TwineMarket market;
  final bool? solverAvailable;
  final String? fiberNode;

  @override
  Widget build(BuildContext context) {
    final trades = market.book.trades;
    if (trades.isEmpty) {
      return const _Empty(
        message: 'No trades yet.',
        icon: Icons.swap_horiz_outlined,
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      itemCount: trades.length,
      separatorBuilder: (context, index) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final trade = trades[index];
        final order = market.book.order(trade.orderId);
        final side = sideOn(trade, market.accountPubkey, order);
        final title = order == null
            ? tradeTitle(trade.phase, side)
            : '${order.side.label} · ${tradeTitle(trade.phase, side)}';
        final detail = trade.fiatAmount == null
            ? trade.id
            : '${trade.fiatAmount} ${trade.fiatCurrency ?? order?.fiatCurrency ?? ''}';
        return Card(
          margin: EdgeInsets.zero,
          child: ListTile(
            title: Text(title),
            subtitle: Text(detail),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (context) => TradePage(
                    market: market,
                    tradeId: trade.id,
                    solverAvailable: solverAvailable,
                    fiberNode: fiberNode,
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.message, required this.icon});

  final String message;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 40, color: theme.colorScheme.outline),
          const SizedBox(height: 12),
          Text(message, style: theme.textTheme.bodyLarge),
        ],
      ),
    );
  }
}

Text _errorLine(ThemeData theme, String message, {bool onContainer = false}) {
  final color = onContainer
      ? theme.colorScheme.onErrorContainer
      : theme.colorScheme.error;
  return Text(
    message,
    style: theme.textTheme.bodyMedium?.copyWith(color: color),
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
