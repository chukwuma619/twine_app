/// The book and this key's trades.
library;

import 'package:cupertino_native_better/cupertino_native_better.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../market/role.dart';
import '../nostr/order.dart';
import 'market.dart';
import 'post_page.dart';
import 'take_page.dart';
import 'trade_page.dart';

enum _Section { post, trade }

/// Which side of the book is open. Buy lists buy posts, and sell lists sell posts.
enum _Book { buy, sell }

class MarketPage extends StatefulWidget {
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
  State<MarketPage> createState() => _MarketPageState();
}

class _MarketPageState extends State<MarketPage> {
  _Section _section = _Section.post;
  _Book _book = _Book.buy;

  @override
  Widget build(BuildContext context) {
    final market = widget.market;
    final posting = _section == _Section.post;
    return ListenableBuilder(
      listenable: market,
      builder: (context, _) {
        return CupertinoTheme(
          data: CupertinoThemeData(
            brightness: Theme.of(context).brightness,
            primaryColor: CupertinoColors.label.resolveFrom(context),
          ),
          child: Scaffold(
            extendBody: _apple(context),
            bottomNavigationBar: _SectionBar(
              section: _section,
              onChanged: (section) => setState(() => _section = section),
            ),
            body: Column(
              children: [
                _TopBar(
                  posting: posting,
                  book: _book,
                  onBook: (book) => setState(() => _book = book),
                  onAccount: widget.onAccount,
                  onPost: posting && market.ready && !market.sending
                      ? () => _openPost(context)
                      : null,
                ),
                _Status(
                  market: market,
                  fiberNode: widget.fiberNode,
                  connecting: widget.connecting,
                  linked: widget.linked,
                  relayError: widget.relayError,
                ),
                Expanded(
                  child: posting
                      ? _Posts(market: market, book: _book)
                      : _Trades(market: market),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _openPost(BuildContext context) {
    final side = _book == _Book.buy ? OrderSide.buy : OrderSide.sell;
    return Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => _LivePost(market: widget.market, side: side),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.posting,
    required this.book,
    required this.onBook,
    required this.onAccount,
    required this.onPost,
  });

  final bool posting;
  final _Book book;
  final ValueChanged<_Book> onBook;
  final VoidCallback onAccount;
  final VoidCallback? onPost;

  @override
  Widget build(BuildContext context) {
    final label = CupertinoColors.label.resolveFrom(context);
    return SafeArea(
      bottom: false,
      child: SizedBox(
        height: 52,
        child: Stack(
          alignment: Alignment.center,
          children: [
            if (posting)
              _BookBar(book: book, onChanged: onBook)
            else
              Text(
                'Trade',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                  color: label,
                ),
              ),
            Row(
              children: [
                SizedBox(
                  width: 52,
                  child: posting
                      ? CupertinoButton(
                          padding: EdgeInsets.zero,
                          onPressed: onPost,
                          child: Icon(
                            CupertinoIcons.plus,
                            color: label,
                            size: 22,
                          ),
                        )
                      : null,
                ),
                const Spacer(),
                CupertinoButton(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  onPressed: onAccount,
                  child: Text(
                    'Account',
                    style: TextStyle(fontSize: 17, color: label),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _BookBar extends StatelessWidget {
  const _BookBar({required this.book, required this.onChanged});

  final _Book book;
  final ValueChanged<_Book> onChanged;

  @override
  Widget build(BuildContext context) {
    return _bookControl(context);
  }

  Widget _bookControl(BuildContext context) {
    if (_apple(context) && !_inWidgetTest) {
      return CNSegmentedControl(
        labels: const ['Buy', 'Sell'],
        selectedIndex: book == _Book.buy ? 0 : 1,
        shrinkWrap: true,
        onValueChanged: (next) => onChanged(next == 0 ? _Book.buy : _Book.sell),
      );
    }
    if (_apple(context)) {
      return SizedBox(
        width: double.infinity,
        child: CupertinoSlidingSegmentedControl<_Book>(
          groupValue: book,
          children: const {_Book.buy: Text('Buy'), _Book.sell: Text('Sell')},
          onValueChanged: (next) {
            if (next != null) onChanged(next);
          },
        ),
      );
    }
    return SegmentedButton<_Book>(
      segments: const [
        ButtonSegment(value: _Book.buy, label: Text('Buy')),
        ButtonSegment(value: _Book.sell, label: Text('Sell')),
      ],
      selected: {book},
      showSelectedIcon: false,
      onSelectionChanged: (next) => onChanged(next.first),
    );
  }
}

class _SectionBar extends StatelessWidget {
  const _SectionBar({required this.section, required this.onChanged});

  final _Section section;
  final ValueChanged<_Section> onChanged;

  @override
  Widget build(BuildContext context) {
    final index = section == _Section.post ? 0 : 1;
    void select(int next) {
      onChanged(next == 0 ? _Section.post : _Section.trade);
    }

    final platform = Theme.of(context).platform;
    switch (platform) {
      case TargetPlatform.iOS:
      case TargetPlatform.macOS:
        if (!_inWidgetTest) {
          return CNTabBar(
            items: const [
              CNTabBarItem(
                label: 'Post',
                icon: CNSymbol('list.bullet'),
                activeIcon: CNSymbol('list.bullet'),
              ),
              CNTabBarItem(
                label: 'Trade',
                icon: CNSymbol('arrow.left.arrow.right'),
                activeIcon: CNSymbol('arrow.left.arrow.right'),
              ),
            ],
            currentIndex: index,
            onTap: select,
          );
        }
        return CupertinoTabBar(
          currentIndex: index,
          onTap: select,
          activeColor: Theme.of(context).colorScheme.primary,
          items: const [
            BottomNavigationBarItem(
              icon: Icon(CupertinoIcons.list_bullet),
              label: 'Post',
            ),
            BottomNavigationBarItem(
              icon: Icon(CupertinoIcons.arrow_right_arrow_left),
              label: 'Trade',
            ),
          ],
        );
      case TargetPlatform.android:
      case TargetPlatform.fuchsia:
      case TargetPlatform.linux:
      case TargetPlatform.windows:
        return NavigationBar(
          selectedIndex: index,
          onDestinationSelected: select,
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.edit_outlined),
              selectedIcon: Icon(Icons.edit),
              label: 'Post',
            ),
            NavigationDestination(
              icon: Icon(Icons.swap_horiz_outlined),
              selectedIcon: Icon(Icons.swap_horiz),
              label: 'Trade',
            ),
          ],
        );
    }
  }
}

bool _apple(BuildContext context) {
  final platform = Theme.of(context).platform;
  return platform == TargetPlatform.iOS || platform == TargetPlatform.macOS;
}

bool get _inWidgetTest {
  return WidgetsBinding.instance.runtimeType.toString().contains(
    'TestWidgetsFlutterBinding',
  );
}

List<TwineOrder> _ordersFor(_Book book, List<TwineOrder> orders) {
  final side = book == _Book.buy ? OrderSide.buy : OrderSide.sell;
  return [
    for (final order in orders)
      if (order.side == side) order,
  ];
}

class _LivePost extends StatelessWidget {
  const _LivePost({required this.market, required this.side});

  final TwineMarket market;
  final OrderSide side;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: market,
      builder: (context, _) {
        return PostPage(
          fiberPubkey: market.fiberPubkey,
          catalog: market.book.catalog,
          initialSide: side,
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
    } else if (fiberNode == null && linked) {
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
  const _Posts({required this.market, required this.book});

  final TwineMarket market;
  final _Book book;

  @override
  Widget build(BuildContext context) {
    final orders = _ordersFor(book, market.book.orders);
    final bottom = _apple(context)
        ? MediaQuery.paddingOf(context).bottom + 128
        : 88.0;
    if (orders.isEmpty) {
      return const Center(child: Text('No posts yet.'));
    }
    return ListView.separated(
      padding: EdgeInsets.fromLTRB(24, 16, 24, bottom),
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
    final bottom = _apple(context)
        ? MediaQuery.paddingOf(context).bottom + 72
        : 24.0;
    if (trades.isEmpty) {
      return const Center(child: Text('No trades yet.'));
    }
    return ListView.separated(
      padding: EdgeInsets.fromLTRB(24, 16, 24, bottom),
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
