/// One trade: the hold, the fiat, and the release.
library;

import 'package:flutter/material.dart';

import '../market/amount.dart';
import '../market/phase.dart';
import '../market/role.dart';
import '../market/trade.dart';
import 'market.dart';

class TradePage extends StatefulWidget {
  const TradePage({super.key, required this.market, required this.tradeId});

  final TwineMarket market;
  final String tradeId;

  @override
  State<TradePage> createState() => _TradePageState();
}

class _TradePageState extends State<TradePage> {
  final _invoice = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _invoice.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.market,
      builder: (context, _) {
        final trade = widget.market.book.trade(widget.tradeId);
        if (trade == null) {
          return Scaffold(
            appBar: AppBar(title: const Text('Trade')),
            body: const SafeArea(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text('This trade is no longer on this device.'),
              ),
            ),
          );
        }
        final order = trade.orderId.isEmpty
            ? null
            : widget.market.book.order(trade.orderId);
        final side = order == null
            ? null
            : tradeSide(order, widget.market.accountPubkey);
        final actions = TradeActions.of(
          phase: trade.phase,
          side: side,
          hasHoldInvoice: trade.holdInvoice != null,
        );
        final theme = Theme.of(context);
        final notice = trade.notice ?? _error;
        return Scaffold(
          appBar: AppBar(title: Text(trade.phase.label)),
          body: SafeArea(
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                if (order != null) ...[
                  Text(
                    '${order.side.label} · ${order.fiatCurrency}',
                    style: theme.textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                ],
                if (trade.amountShannons != null)
                  Text('${shannonsToCkb(trade.amountShannons!)} CKB'),
                const SizedBox(height: 8),
                Text('Reference', style: theme.textTheme.titleSmall),
                SelectableText(trade.reference ?? trade.id),
                if (trade.fiatAmount != null) ...[
                  const SizedBox(height: 16),
                  Text(
                    'Send ${trade.fiatAmount} ${trade.fiatCurrency ?? ''} with ${trade.paymentLabel ?? 'the named method'}.',
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Account details stay in your own chat. Put the reference on the payment.',
                  ),
                ],
                if (trade.payoutFailure != null) ...[
                  const SizedBox(height: 16),
                  Text(trade.payoutFailure!),
                ],
                if (actions.payHold) ...[
                  const SizedBox(height: 16),
                  const Text('Pay this invoice in your Fiber wallet.'),
                  const SizedBox(height: 8),
                  SelectableText(trade.holdInvoice!),
                ] else if (side == null &&
                    trade.phase == TradePhase.waitingHold) ...[
                  const SizedBox(height: 16),
                  const Text(
                    'Waiting for the post to confirm who locks the hold.',
                  ),
                ],
                if (trade.phase == TradePhase.releasing) ...[
                  const SizedBox(height: 16),
                  const Text('Releasing the hold.'),
                ],
                if (actions.sendFiat) ...[
                  const SizedBox(height: 16),
                  TextField(
                    controller: _invoice,
                    enabled: !widget.market.sending,
                    minLines: 1,
                    maxLines: 4,
                    autocorrect: false,
                    enableSuggestions: false,
                    decoration: const InputDecoration(
                      labelText: 'Payout invoice',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: widget.market.sending
                        ? null
                        : () => _fiat(trade),
                    child: Text(
                      trade.phase == TradePhase.waitingFiat
                          ? "I've sent the fiat"
                          : 'Submit payout invoice',
                    ),
                  ),
                ],
                if (actions.release) ...[
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: widget.market.sending
                        ? null
                        : () => _release(trade),
                    child: const Text('Release'),
                  ),
                ],
                if (actions.dispute) ...[
                  const SizedBox(height: 12),
                  OutlinedButton(
                    onPressed: widget.market.sending
                        ? null
                        : () => _dispute(trade),
                    child: const Text('Dispute'),
                  ),
                ],
                if (actions.cancel) ...[
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: widget.market.sending
                        ? null
                        : () => _cancel(trade),
                    child: const Text('Cancel trade'),
                  ),
                ],
                if (notice != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    notice,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.error,
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _fiat(TwineTrade trade) async {
    final error = await widget.market.fiatSent(trade.id, _invoice.text);
    if (!mounted) return;
    setState(() => _error = error);
  }

  Future<void> _release(TwineTrade trade) async {
    final confirmed = await _confirm(
      context,
      'Release the hold?',
      'This pays the buyer.',
    );
    if (!confirmed || !mounted) return;
    final error = await widget.market.release(trade.id);
    if (!mounted) return;
    setState(() => _error = error);
  }

  Future<void> _dispute(TwineTrade trade) async {
    final confirmed = await _confirm(
      context,
      'Open a dispute?',
      'The hold stays locked until the solver decides.',
    );
    if (!confirmed || !mounted) return;
    final invoice = _invoice.text.trim();
    final error = await widget.market.dispute(
      trade.id,
      invoice: invoice.isEmpty ? null : invoice,
    );
    if (!mounted) return;
    setState(() => _error = error);
  }

  Future<void> _cancel(TwineTrade trade) async {
    final confirmed = await _confirm(
      context,
      'Cancel this trade?',
      'This drops the hold before it locks.',
    );
    if (!confirmed || !mounted) return;
    final error = await widget.market.cancelTrade(trade.id);
    if (!mounted) return;
    setState(() => _error = error);
  }
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
