import 'dart:async';

import 'package:flutter/material.dart';

import '../market/amount.dart';
import '../market/book.dart';
import '../market/chat.dart';
import '../market/outcome.dart';
import '../market/phase.dart';
import '../market/role.dart';
import '../market/steps.dart';
import '../market/trade.dart';
import '../nostr/keys.dart';
import '../nostr/order.dart';
import '../ui/twine_tokens.dart';
import 'market.dart';
import 'trade_page.dart';

const _settled = Color(0xFF067647);

const _months = [
  '',
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

enum _StatusFilter { active, settled, closed, all }

enum _TimeOrder { newest, oldest }

enum _Bucket { active, settled, closed }

/// The account's trades, filtered by status, in time order.
class TradeList extends StatefulWidget {
  const TradeList({
    super.key,
    required this.market,
    this.solverAvailable,
    this.onRefresh,
  });

  final TwineMarket market;
  final bool? solverAvailable;
  final Future<void> Function()? onRefresh;

  @override
  State<TradeList> createState() => _TradeListState();
}

class _TradeListState extends State<TradeList> {
  _StatusFilter _status = _StatusFilter.active;
  _TimeOrder _order = _TimeOrder.newest;
  Timer? _clock;

  @override
  void initState() {
    super.initState();
    _clock = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _clock?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final market = widget.market;
    final rows = [
      for (final trade in market.book.trades) _Row.forTrade(market, trade),
    ];
    if (rows.isEmpty) {
      return const _Empty(
        message: 'No trades yet.',
        icon: Icons.swap_horiz_outlined,
      );
    }

    var active = 0;
    var settled = 0;
    var closed = 0;
    for (final row in rows) {
      switch (_bucket(row.trade.phase)) {
        case _Bucket.active:
          active++;
        case _Bucket.settled:
          settled++;
        case _Bucket.closed:
          closed++;
      }
    }
    final shown =
        [
          for (final row in rows)
            if (_matchesStatus(row.trade.phase, _status)) row,
        ]..sort((a, b) {
          final newest = compareTradesByTime(a.trade, b.trade);
          return _order == _TimeOrder.newest ? newest : -newest;
        });
    final now = DateTime.now();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Filters(
          status: _status,
          order: _order,
          active: active,
          settled: settled,
          closed: closed,
          onStatus: (next) => setState(() => _status = next),
          onOrder: () {
            setState(() {
              _order = _order == _TimeOrder.newest
                  ? _TimeOrder.oldest
                  : _TimeOrder.newest;
            });
          },
        ),
        Expanded(
          child: shown.isEmpty
              ? _Empty(
                  message: _emptyMessage(_status),
                  icon: Icons.swap_horiz_outlined,
                )
              : _wrapRefresh(
                  ListView.separated(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.only(bottom: TwineTokens.lg),
                    itemCount: shown.length,
                    separatorBuilder: (context, index) {
                      return Divider(
                        height: 1,
                        thickness: 1,
                        indent: TwineTokens.md,
                        endIndent: TwineTokens.md,
                        color: Theme.of(context).colorScheme.outlineVariant,
                      );
                    },
                    itemBuilder: (context, index) {
                      final row = shown[index];
                      final hasPaymentDetails =
                          market.book.paymentDetails(row.trade.id) != null;
                      return _TradeTile(
                        row: row,
                        now: now,
                        yourMove: _yourMove(
                          row.trade,
                          row.side,
                          widget.solverAvailable,
                          hasPaymentDetails: hasPaymentDetails,
                        ),
                        preview: _lastLine(market, row.trade.id),
                        onTap: () => _open(context, row.trade.id),
                      );
                    },
                  ),
                ),
        ),
      ],
    );
  }

  Widget _wrapRefresh(Widget list) {
    final refresh = widget.onRefresh;
    if (refresh == null) return list;
    return RefreshIndicator(onRefresh: refresh, child: list);
  }

  void _open(BuildContext context, String tradeId) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => TradePage(
          market: widget.market,
          tradeId: tradeId,
          solverAvailable: widget.solverAvailable,
        ),
      ),
    );
  }
}

class _Row {
  _Row({
    required this.market,
    required this.trade,
    required this.order,
    required this.side,
  });

  factory _Row.forTrade(TwineMarket market, TwineTrade trade) {
    final order = market.book.order(trade.orderId);
    return _Row(
      market: market,
      trade: trade,
      order: order,
      side: sideOn(trade, market.accountPubkey, order),
    );
  }

  final TwineMarket market;
  final TwineTrade trade;
  final TwineOrder? order;
  final TradeSide? side;
}

class _Filters extends StatelessWidget {
  const _Filters({
    required this.status,
    required this.order,
    required this.active,
    required this.settled,
    required this.closed,
    required this.onStatus,
    required this.onOrder,
  });

  final _StatusFilter status;
  final _TimeOrder order;
  final int active;
  final int settled;
  final int closed;
  final ValueChanged<_StatusFilter> onStatus;
  final VoidCallback onOrder;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final newest = order == _TimeOrder.newest;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        TwineTokens.md,
        TwineTokens.sm,
        TwineTokens.md,
        TwineTokens.xs,
      ),
      child: Row(
        children: [
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _Pill(
                    key: const ValueKey('trade-status-active'),
                    label: _countLabel('Active', active),
                    selected: status == _StatusFilter.active,
                    onTap: () => onStatus(_StatusFilter.active),
                  ),
                  _Pill(
                    key: const ValueKey('trade-status-settled'),
                    label: _countLabel('Settled', settled),
                    selected: status == _StatusFilter.settled,
                    onTap: () => onStatus(_StatusFilter.settled),
                  ),
                  _Pill(
                    key: const ValueKey('trade-status-closed'),
                    label: _countLabel('Closed', closed),
                    selected: status == _StatusFilter.closed,
                    onTap: () => onStatus(_StatusFilter.closed),
                  ),
                  _Pill(
                    key: const ValueKey('trade-status-all'),
                    label: _countLabel('All', active + settled + closed),
                    selected: status == _StatusFilter.all,
                    onTap: () => onStatus(_StatusFilter.all),
                  ),
                ],
              ),
            ),
          ),
          TextButton(
            style: TextButton.styleFrom(
              visualDensity: VisualDensity.compact,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              foregroundColor: scheme.onSurface,
              padding: const EdgeInsets.symmetric(horizontal: TwineTokens.xs),
            ),
            onPressed: onOrder,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  newest ? Icons.arrow_downward : Icons.arrow_upward,
                  size: TwineTokens.iconSm,
                ),
                const SizedBox(width: TwineTokens.xxs),
                Text(newest ? 'Newest' : 'Oldest'),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final background = selected
        ? scheme.secondaryContainer
        : scheme.surfaceContainerHighest;
    final foreground = selected
        ? scheme.onSecondaryContainer
        : scheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.only(right: TwineTokens.xs),
      child: Material(
        color: background,
        borderRadius: BorderRadius.circular(TwineTokens.radiusPill),
        child: InkWell(
          borderRadius: BorderRadius.circular(TwineTokens.radiusPill),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: TwineTokens.sm,
              vertical: TwineTokens.xs,
            ),
            child: Text(
              label,
              softWrap: false,
              style: theme.textTheme.labelLarge?.copyWith(
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: foreground,
                height: 1.1,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TradeTile extends StatelessWidget {
  const _TradeTile({
    required this.row,
    required this.now,
    required this.yourMove,
    required this.preview,
    required this.onTap,
  });

  final _Row row;
  final DateTime now;
  final bool yourMove;
  final _LinePreview? preview;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final trade = row.trade;
    final ckb = _ckbLabel(trade, row.order);
    final fiat = _fiatLabel(trade, row.order);
    final title = tradeTitle(trade.phase, row.side);
    final hasAmount = ckb != null || fiat != null;
    final headline = ckb ?? fiat ?? title;
    final trailing = ckb != null ? fiat : null;
    final status = hasAmount ? title : null;
    final peer = _peer(trade, row.market);
    final recorded = recordLabel(trade.record);
    final when = _when(trade.updatedAt, now);
    final statusColor = _statusColor(scheme, trade.phase, yourMove);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            border: Border(
              left: BorderSide(
                color: yourMove ? scheme.primary : Colors.transparent,
                width: 3,
              ),
            ),
          ),
          padding: const EdgeInsets.fromLTRB(
            TwineTokens.sm,
            TwineTokens.sm,
            TwineTokens.md,
            TwineTokens.sm,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      headline,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        height: 1.2,
                      ),
                    ),
                  ),
                  if (trailing != null) ...[
                    const SizedBox(width: TwineTokens.xs),
                    Flexible(
                      child: Text(
                        trailing,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.end,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                          height: 1.2,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: TwineTokens.xxs),
              Row(
                children: [
                  Expanded(
                    child: status == null
                        ? const SizedBox.shrink()
                        : Text(
                            status,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: statusColor,
                              fontWeight: yourMove
                                  ? FontWeight.w600
                                  : FontWeight.w500,
                              height: 1.3,
                            ),
                          ),
                  ),
                  const SizedBox(width: TwineTokens.xs),
                  Text(when, style: TwineTokens.muted(theme)),
                ],
              ),
              if (recorded != null) ...[
                const SizedBox(height: TwineTokens.xxs),
                Text(
                  recorded,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                    height: 1.3,
                  ),
                ),
              ],
              if (peer != null) ...[
                const SizedBox(height: TwineTokens.xxs),
                Text(
                  peer,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TwineTokens.muted(theme),
                ),
              ],
              if (preview != null) ...[
                const SizedBox(height: TwineTokens.xxs),
                Text(
                  preview!.text,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: preview!.incoming
                      ? theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                          height: 1.3,
                        )
                      : TwineTokens.muted(theme),
                ),
              ],
            ],
          ),
        ),
      ),
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
      child: Padding(
        padding: const EdgeInsets.all(TwineTokens.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 40, color: theme.colorScheme.outline),
            const SizedBox(height: TwineTokens.sm),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TwineTokens.body(theme),
            ),
          ],
        ),
      ),
    );
  }
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

bool _yourMove(
  TwineTrade trade,
  TradeSide? side,
  bool? solverAvailable, {
  required bool hasPaymentDetails,
}) {
  if (trade.phase == TradePhase.waitingFiat) {
    if (side == TradeSide.seller) return !hasPaymentDetails;
    if (side == TradeSide.buyer) return hasPaymentDetails;
    return false;
  }
  final actions = TradeActions.of(
    phase: trade.phase,
    side: side,
    hasHoldInvoice: trade.holdInvoice != null && trade.holdInvoice!.isNotEmpty,
    solverAvailable: solverAvailable,
    releaseBy: trade.releaseBy,
    solverWindowSecs: trade.solverWindowSecs,
    record: trade.record,
  );
  return actions.payHold ||
      actions.submitInvoice ||
      actions.sendFiat ||
      actions.release;
}

_Bucket _bucket(TradePhase phase) {
  switch (phase) {
    case TradePhase.settled:
      return _Bucket.settled;
    case TradePhase.canceled:
    case TradePhase.expired:
      return _Bucket.closed;
    case TradePhase.waitingInvoice:
    case TradePhase.waitingHold:
    case TradePhase.awaitingRoute:
    case TradePhase.waitingFiat:
    case TradePhase.fiatSent:
    case TradePhase.releasing:
    case TradePhase.awaitingInvoice:
    case TradePhase.disputed:
    case TradePhase.refunding:
      return _Bucket.active;
  }
}

bool _matchesStatus(TradePhase phase, _StatusFilter filter) {
  switch (filter) {
    case _StatusFilter.all:
      return true;
    case _StatusFilter.active:
      return _bucket(phase) == _Bucket.active;
    case _StatusFilter.settled:
      return _bucket(phase) == _Bucket.settled;
    case _StatusFilter.closed:
      return _bucket(phase) == _Bucket.closed;
  }
}

String _countLabel(String name, int count) {
  if (count == 0) return name;
  return '$name $count';
}

String _emptyMessage(_StatusFilter status) {
  switch (status) {
    case _StatusFilter.active:
      return 'No active trades.';
    case _StatusFilter.settled:
      return 'No settled trades.';
    case _StatusFilter.closed:
      return 'No closed trades.';
    case _StatusFilter.all:
      return 'No trades yet.';
  }
}

String? _ckbLabel(TwineTrade trade, TwineOrder? order) {
  final shannons = trade.amountShannons;
  if (shannons != null) return '${shannonsToCkb(shannons)} CKB';
  final fiat = trade.fiatAmount;
  final price = order?.pricePerCkb;
  if (fiat == null || price == null) return null;
  final ckb = aboutCkb(fiat, price);
  if (ckb == null) return null;
  return '$ckb CKB';
}

String? _fiatLabel(TwineTrade trade, TwineOrder? order) {
  final amount = trade.fiatAmount;
  if (amount == null) return null;
  final currency = trade.fiatCurrency ?? order?.fiatCurrency ?? '';
  if (currency.isEmpty) return amount;
  return '$amount $currency';
}

String? _peer(TwineTrade trade, TwineMarket market) {
  final peer = counterparty(trade, market.accountPubkey);
  if (peer == null) return null;
  final clean = peer.trim().toLowerCase();
  var display = peer.trim();
  if (RegExp(r'^[0-9a-f]{64}$').hasMatch(clean)) {
    try {
      display = TwineKeys.encodeNpub(clean);
    } catch (_) {}
  }
  return 'With ${_shortKey(display)}';
}

String _shortKey(String value) {
  final text = value.trim();
  if (text.length <= 14) return text;
  return '${text.substring(0, 6)}…${text.substring(text.length - 4)}';
}

String _when(DateTime at, DateTime now) {
  final local = at.toLocal();
  final current = now.toLocal();
  var delta = current.difference(local);
  if (delta.isNegative) delta = Duration.zero;
  if (delta.inMinutes < 1) return 'Just now';
  if (delta.inHours < 1) return '${delta.inMinutes}m ago';
  if (delta.inHours < 24) return '${delta.inHours}h ago';
  if (delta.inDays < 7) return '${delta.inDays}d ago';
  final month = _months[local.month];
  if (local.year == current.year) return '${local.day} $month';
  return '${local.day} $month ${local.year}';
}

Color _statusColor(ColorScheme scheme, TradePhase phase, bool yourMove) {
  switch (phase) {
    case TradePhase.disputed:
      return scheme.error;
    case TradePhase.settled:
      return _settled;
    case TradePhase.waitingInvoice:
    case TradePhase.waitingHold:
    case TradePhase.awaitingRoute:
    case TradePhase.waitingFiat:
    case TradePhase.fiatSent:
    case TradePhase.releasing:
    case TradePhase.awaitingInvoice:
    case TradePhase.refunding:
      return yourMove ? scheme.primary : scheme.onSurfaceVariant;
    case TradePhase.canceled:
    case TradePhase.expired:
      return scheme.onSurfaceVariant;
  }
}
