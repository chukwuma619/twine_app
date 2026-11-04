import 'package:flutter/material.dart';
import 'package:twine_app/twine_logo.dart';
import 'package:twine_app/update/update_controller.dart';
import 'package:twine_app/update/update_panel.dart';

import '../market/chat.dart';
import '../market/role.dart';
import '../market/steps.dart';
import '../nostr/order.dart';
import '../ui/twine_tokens.dart';
import 'fiber_guide.dart';
import 'market.dart';
import 'notice_bar.dart';
import 'post_page.dart';
import 'take_page.dart';
import 'trade_page.dart';

enum _Section { post, trade, account }

class MarketPage extends StatefulWidget {
  const MarketPage({
    super.key,
    required this.market,
    required this.account,
    this.fiberNode,
    this.fiberAddresses = const [],
    this.solverAvailable,
    this.connecting = false,
    this.linked = false,
    this.relayError,
    this.connectedRelays = const [],
    this.relayCount = 0,
    this.showFiberGuide = false,
    this.onFiberGuideDismissed,
    this.updates,
  });

  final TwineMarket market;
  final UpdateController? updates;
  final Widget account;
  final String? fiberNode;
  final List<String> fiberAddresses;
  final bool? solverAvailable;
  final bool connecting;
  final bool linked;
  final String? relayError;
  final List<String> connectedRelays;
  final int relayCount;
  final bool showFiberGuide;
  final Future<void> Function()? onFiberGuideDismissed;

  @override
  State<MarketPage> createState() => _MarketPageState();
}

class _MarketPageState extends State<MarketPage> {
  _Section _section = _Section.post;
  bool _showCanceled = false;
  bool _fiberGuideHandled = false;
  StateSetter? _dialogSetState;

  @override
  void initState() {
    super.initState();
    widget.market.addListener(_presentNotice);
    _scheduleFiberGuide();
    WidgetsBinding.instance.addPostFrameCallback((_) => _presentNotice());
  }

  @override
  void dispose() {
    widget.market.removeListener(_presentNotice);
    super.dispose();
  }

  String? _notice;

  void _presentNotice() {
    final notice = widget.market.book.notice;
    if (notice == null || !mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final current = widget.market.book.notice;
      if (current == null) return;
      widget.market.dismissNotice();
      setState(() => _notice = current);
    });
  }

  void _dismissShownNotice() {
    if (_notice == null) return;
    setState(() => _notice = null);
  }

  Widget _updateBanner() {
    final updates = widget.updates;
    if (updates == null) return const SizedBox.shrink();
    return UpdateBanner(controller: updates);
  }

  Widget _noticeBanner() {
    final notice = _notice;
    if (notice == null) return const SizedBox.shrink();
    return DismissibleNotice(message: notice, onDismiss: _dismissShownNotice);
  }

  @override
  void didUpdateWidget(MarketPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    _scheduleFiberGuide();
    final update = _dialogSetState;
    if (update == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _dialogSetState != update) return;
      update(() {});
    });
  }

  void _scheduleFiberGuide() {
    if (_fiberGuideHandled || !widget.showFiberGuide) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _fiberGuideHandled || !widget.showFiberGuide) return;
      _fiberGuideHandled = true;
      showDialog<void>(
        context: context,
        barrierDismissible: true,
        builder: (dialogContext) {
          return StatefulBuilder(
            builder: (context, setDialogState) {
              _dialogSetState = setDialogState;
              return AlertDialog(
                content: SingleChildScrollView(
                  child: FiberConnectGuide(
                    fiberNode: widget.fiberNode,
                    fiberAddresses: widget.fiberAddresses,
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(dialogContext).pop(),
                    child: const Text('Got it'),
                  ),
                ],
              );
            },
          );
        },
      ).then((_) {
        _dialogSetState = null;
        if (!mounted) return;
        widget.onFiberGuideDismissed?.call();
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final market = widget.market;
    final posting = _section == _Section.post;
    return ListenableBuilder(
      listenable: market,
      builder: (context, _) {
        final canPost = posting && market.ready && !market.sending;
        final title = switch (_section) {
          _Section.post => 'Posts',
          _Section.trade => 'Trades',
          _Section.account => 'Account',
        };
        return Scaffold(
          appBar: AppBar(title: TwineTitle(title)),
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
                label: 'Posts',
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
                    _updateBanner(),
                    _noticeBanner(),
                    _Status(
                      market: market,
                      connecting: widget.connecting,
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
                    _updateBanner(),
                    _noticeBanner(),
                    if (posting)
                      Padding(
                        padding: const EdgeInsets.only(right: TwineTokens.xs),
                        child: Align(
                          alignment: Alignment.centerRight,
                          child: TextButton(
                            style: TextButton.styleFrom(
                              visualDensity: VisualDensity.compact,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              foregroundColor: Theme.of(
                                context,
                              ).colorScheme.onSurfaceVariant,
                            ),
                            onPressed: () {
                              setState(() => _showCanceled = !_showCanceled);
                            },
                            child: Text(
                              _showCanceled ? 'Hide canceled' : 'Show canceled',
                            ),
                          ),
                        ),
                      ),
                    _Status(
                      market: market,
                      connecting: widget.connecting,
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
                              showCanceled: _showCanceled,
                              solverAvailable: widget.solverAvailable,
                            )
                          : _Trades(
                              market: market,
                              solverAvailable: widget.solverAvailable,
                            ),
                    ),
                  ],
                ),
        );
      },
    );
  }

  Future<void> _openPost(BuildContext context) {
    return Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (context) => _LivePost(market: widget.market),
      ),
    );
  }
}

List<TwineOrder> _listedPosts(List<TwineOrder> orders) {
  return [
    for (final order in orders)
      if (order.side == OrderSide.sell) order,
  ];
}

class _LivePost extends StatelessWidget {
  const _LivePost({required this.market});

  final TwineMarket market;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: market,
      builder: (context, _) {
        return PostPage(onSubmit: market.post);
      },
    );
  }
}

class _Status extends StatelessWidget {
  const _Status({
    required this.market,
    required this.connecting,
    this.relayError,
    this.partialRelays = false,
  });

  final TwineMarket market;
  final bool connecting;
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
        const Text(
          'Publishing. You cannot cancel until the daemon lists this post.',
        ),
      );
    }
    if (market.awaitingTake) {
      lines.add(const Text('Opening the trade…'));
    }
    if (partialRelays) {
      lines.add(
        const Text('Some of the relays you entered are not connected.'),
      );
    }
    final status = market.status;
    if (status != null) lines.add(Text(status));
    if (relayError != null) {
      lines.add(_errorLine(theme, relayError!, onContainer: true));
    } else if (connecting) {
      lines.add(const Text('Connecting to relays…'));
    }
    if (lines.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        TwineTokens.md,
        TwineTokens.sm,
        TwineTokens.md,
        0,
      ),
      child: Card(
        color: relayError != null ? theme.colorScheme.errorContainer : null,
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(TwineTokens.sm),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var i = 0; i < lines.length; i++) ...[
                if (i > 0) const SizedBox(height: TwineTokens.xs),
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
    required this.showCanceled,
    this.solverAvailable,
  });

  final TwineMarket market;
  final bool showCanceled;
  final bool? solverAvailable;

  @override
  Widget build(BuildContext context) {
    final orders = [
      for (final order in _listedPosts([
        ...market.pending,
        ...market.book.orders,
      ]))
        if (showCanceled || order.status != PostStatus.canceled) order,
    ];
    if (orders.isEmpty) {
      return const _Empty(
        message: 'No posts yet.',
        icon: Icons.list_alt_outlined,
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(
        TwineTokens.md,
        TwineTokens.sm,
        TwineTokens.md,
        96,
      ),
      itemCount: orders.length,
      separatorBuilder: (context, index) =>
          const SizedBox(height: TwineTokens.sm),
      itemBuilder: (context, index) {
        return _PostCard(
          market: market,
          order: orders[index],
          solverAvailable: solverAvailable,
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
  });

  final TwineMarket market;
  final TwineOrder order;
  final bool? solverAvailable;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mine = isMaker(order, market.accountPubkey);
    final pending = order.orderId.startsWith('local-');
    final open = market.book.openTradeFor(order.orderId);
    final listed = order.status == PostStatus.open;
    final muted = TwineTokens.muted(theme);
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
    final chips = <Widget>[
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
    ];
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(TwineTokens.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${order.pricePerCkb} ${order.fiatCurrency}',
                        style: TwineTokens.price(theme),
                      ),
                      Text('per CKB', style: muted),
                      const SizedBox(height: TwineTokens.xs),
                      Text(
                        '${order.availableCkb} CKB',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                          height: 1.2,
                        ),
                      ),
                    ],
                  ),
                ),
                if (action != null) ...[
                  const SizedBox(width: TwineTokens.sm),
                  action,
                ],
              ],
            ),
            const SizedBox(height: TwineTokens.sm),
            Text(
              '${order.min}–${order.max} ${order.fiatCurrency}',
              style: muted,
            ),
            if (order.hasReserved) ...[
              const SizedBox(height: TwineTokens.xxs),
              Text('${order.reservedCkb} CKB in an open trade', style: muted),
            ],
            const SizedBox(height: TwineTokens.xxs),
            Text(
              '${_holdLabel(order.holdHours)} locked on Fiber',
              style: muted,
            ),
            if (chips.isNotEmpty) ...[
              const SizedBox(height: TwineTokens.sm),
              Wrap(spacing: TwineTokens.xs, children: chips),
            ],
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
        ),
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

String _holdLabel(int hours) {
  return hours == 1 ? '1 hour' : '$hours hours';
}

class _LinePreview {
  const _LinePreview(this.text, {required this.incoming});

  final String text;
  final bool incoming;
}

_LinePreview? _lastLine(TwineMarket market, String tradeId) {
  final notes = market.book.thread(tradeId);
  for (var i = notes.length - 1; i >= 0; i--) {
    final note = notes[i];
    final incoming =
        note.author?.toLowerCase() != market.accountPubkey.toLowerCase();
    final preview = _preview(note, incoming);
    if (preview != null) return preview;
  }
  return null;
}

_LinePreview? _preview(TradeNote note, bool incoming) {
  switch (note.kind) {
    case TradeNoteKind.text:
      final text = note.text?.trim();
      if (text == null || text.isEmpty) return null;
      return _LinePreview(
        '${incoming ? 'Them' : 'You'}: $text',
        incoming: incoming,
      );
    case TradeNoteKind.paymentDetails:
      return _LinePreview('Payment details', incoming: incoming);
    case TradeNoteKind.paymentProof:
      return _LinePreview('Receipt', incoming: incoming);
    case TradeNoteKind.status:
      final text = note.text?.trim();
      if (text == null || text.isEmpty) return null;
      return _LinePreview(text, incoming: false);
  }
}

class _Trades extends StatelessWidget {
  const _Trades({required this.market, this.solverAvailable});

  final TwineMarket market;
  final bool? solverAvailable;

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
      padding: const EdgeInsets.fromLTRB(
        TwineTokens.md,
        TwineTokens.sm,
        TwineTokens.md,
        TwineTokens.lg,
      ),
      itemCount: trades.length,
      separatorBuilder: (context, index) =>
          const SizedBox(height: TwineTokens.sm),
      itemBuilder: (context, index) {
        final trade = trades[index];
        final order = market.book.order(trade.orderId);
        final side = sideOn(trade, market.accountPubkey, order);
        final title = tradeTitle(trade.phase, side);
        final detail = trade.fiatAmount == null
            ? trade.id
            : '${trade.fiatAmount} ${trade.fiatCurrency ?? order?.fiatCurrency ?? ''}';
        final preview = _lastLine(market, trade.id);
        final theme = Theme.of(context);
        return Card(
          margin: EdgeInsets.zero,
          child: InkWell(
            borderRadius: TwineTokens.smRadius,
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (context) => TradePage(
                    market: market,
                    tradeId: trade.id,
                    solverAvailable: solverAvailable,
                  ),
                ),
              );
            },
            child: Padding(
              padding: const EdgeInsets.all(TwineTokens.md),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                            height: 1.2,
                          ),
                        ),
                        const SizedBox(height: TwineTokens.xxs),
                        Text(
                          detail,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TwineTokens.muted(theme),
                        ),
                        if (preview != null) ...[
                          const SizedBox(height: TwineTokens.xxs),
                          Text(
                            preview.text,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: preview.incoming
                                ? theme.textTheme.bodyMedium?.copyWith(
                                    fontWeight: FontWeight.w600,
                                    height: 1.3,
                                  )
                                : TwineTokens.body(theme),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: TwineTokens.xs),
                  Icon(
                    Icons.chevron_right,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ],
              ),
            ),
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
          const SizedBox(height: TwineTokens.sm),
          Text(message, style: TwineTokens.body(theme)),
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
