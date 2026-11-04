import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../market/amount.dart';
import '../market/chat.dart';
import '../market/clocks.dart';
import '../market/outcome.dart';
import '../market/phase.dart';
import '../market/receipt.dart';
import '../market/role.dart';
import '../market/steps.dart';
import '../market/trade.dart';
import 'market.dart';
import 'notice_bar.dart';

enum _Work { share, paid, invoice, chat, release, dispute, cancel }

class TradePage extends StatefulWidget {
  const TradePage({
    super.key,
    required this.market,
    required this.tradeId,
    this.solverAvailable,
  });

  final TwineMarket market;
  final String tradeId;
  final bool? solverAvailable;

  @override
  State<TradePage> createState() => _TradePageState();
}

class _TradePageState extends State<TradePage> {
  final _invoice = TextEditingController();
  final _details = TextEditingController();
  final _chat = TextEditingController();
  final _thread = ScrollController();
  Timer? _tick;
  String? _error;
  String? _banner;
  bool _lifting = false;
  bool _showKeys = false;
  bool _nearLimit = false;
  bool _shiftHeld = false;
  _Work? _busy;
  int _pinned = -1;

  @override
  void initState() {
    super.initState();
    _chat.addListener(_onDraft);
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    _chat.removeListener(_onDraft);
    _invoice.dispose();
    _details.dispose();
    _chat.dispose();
    _thread.dispose();
    super.dispose();
  }

  void _onDraft() {
    final near = _chat.text.length >= 800;
    if (!near && !_nearLimit) return;
    if (!mounted) return;
    setState(() => _nearLimit = near);
  }

  KeyEventResult _trackShift(FocusNode node, KeyEvent event) {
    final key = event.logicalKey;
    if (key != LogicalKeyboardKey.shiftLeft &&
        key != LogicalKeyboardKey.shiftRight) {
      return KeyEventResult.ignored;
    }
    _shiftHeld = event is! KeyUpEvent;
    return KeyEventResult.ignored;
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
        final side = sideOn(trade, widget.market.accountPubkey, order);
        final actions = TradeActions.of(
          phase: trade.phase,
          side: side,
          hasHoldInvoice: trade.holdInvoice != null,
          solverAvailable: widget.solverAvailable,
        );
        final details = widget.market.book.paymentDetails(trade.id);
        final proof = widget.market.book.paymentProof(trade.id);
        final peer = counterparty(trade, widget.market.accountPubkey);
        final theme = Theme.of(context);
        final stored = trade.notice ?? widget.market.book.notice;
        _liftNotice(stored);
        final notice = _banner ?? stored ?? _error;
        final waitingFiat =
            side == TradeSide.buyer && trade.phase == TradePhase.waitingFiat;
        final shareAccount =
            side == TradeSide.seller &&
            trade.phase == TradePhase.waitingFiat &&
            details == null;
        final outcome = tradeOutcome(trade.phase);
        final compose =
            peer != null &&
            !trade.phase.terminal &&
            trade.phase != TradePhase.refunding;
        final lines = _lines(trade.id);
        _pin(lines.length);
        final step = _step(
          trade: trade,
          side: side,
          actions: actions,
          details: details,
          proof: proof,
          peer: peer,
          shareAccount: shareAccount,
          waitingFiat: waitingFiat,
        );
        return Scaffold(
          resizeToAvoidBottomInset: true,
          appBar: AppBar(title: Text(tradeTitle(trade.phase, side))),
          body: SafeArea(
            child: Column(
              children: [
                if (notice != null)
                  DismissibleNotice(message: notice, onDismiss: _dismissNotice),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      return Column(
                        children: [
                          ConstrainedBox(
                            constraints: BoxConstraints(
                              maxHeight: constraints.maxHeight * 0.34,
                            ),
                            child: ListView(
                              shrinkWrap: true,
                              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                              children: [
                                _header(
                                  theme: theme,
                                  trade: trade,
                                  orderCurrency: order?.fiatCurrency,
                                  side: side,
                                  outcome: outcome,
                                ),
                              ],
                            ),
                          ),
                          const Divider(height: 1),
                          Expanded(child: _conversation(theme, lines, peer)),
                          if (step != null) ...[
                            const Divider(height: 1),
                            ConstrainedBox(
                              constraints: BoxConstraints(
                                maxHeight: constraints.maxHeight * 0.38,
                              ),
                              child: ListView(
                                shrinkWrap: true,
                                padding: const EdgeInsets.fromLTRB(
                                  16,
                                  12,
                                  16,
                                  8,
                                ),
                                children: [step],
                              ),
                            ),
                          ],
                        ],
                      );
                    },
                  ),
                ),
                if (compose) _composer(trade),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _header({
    required ThemeData theme,
    required TwineTrade trade,
    required TradeSide? side,
    required String? outcome,
    String? orderCurrency,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (outcome != null) ...[
          Text(outcome, style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
        ],
        if (orderCurrency != null)
          Text(orderCurrency, style: theme.textTheme.titleMedium),
        if (trade.amountShannons != null)
          Text('${shannonsToCkb(trade.amountShannons!)} CKB'),
        const SizedBox(height: 4),
        Text(_sideLine(side)),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            style: TextButton.styleFrom(
              visualDensity: VisualDensity.compact,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            onPressed: () => setState(() => _showKeys = !_showKeys),
            child: Text(_showKeys ? 'Hide keys' : 'Show keys'),
          ),
        ),
        if (_showKeys)
          _Parties(
            me: widget.market.accountPubkey,
            seller: trade.sellerNostr,
            buyer: trade.buyerNostr,
            encode: _npub,
          ),
        ..._clocks(trade, side),
        const SizedBox(height: 8),
        Text('Reference', style: theme.textTheme.titleSmall),
        SelectableText(trade.reference ?? trade.id),
        if (trade.fiatAmount != null &&
            trade.phase != TradePhase.waitingHold &&
            trade.phase != TradePhase.waitingInvoice) ...[
          const SizedBox(height: 8),
          Text(_paymentLine(side, trade)),
          if (side == TradeSide.buyer) ...[
            const SizedBox(height: 4),
            const Text('Put the reference on the payment.'),
          ],
        ],
      ],
    );
  }

  Widget _conversation(ThemeData theme, List<TradeNote> lines, String? peer) {
    if (peer == null) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Text('The thread opens once this trade has both keys.'),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Text(
            'Encrypted to the other trader. The relay can see that these two keys are talking.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        Expanded(
          child: ListView.builder(
            controller: _thread,
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            itemCount: lines.isEmpty ? 1 : lines.length,
            itemBuilder: (context, index) {
              if (lines.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Text(
                    'No messages yet.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                );
              }
              final line = lines[index];
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _Bubble(
                  line: line,
                  mine:
                      line.author?.toLowerCase() ==
                      widget.market.accountPubkey.toLowerCase(),
                  onOpenReceipt: _openReceipt,
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget? _step({
    required TwineTrade trade,
    required TradeSide? side,
    required TradeActions actions,
    required TradeNote? details,
    required TradeNote? proof,
    required String? peer,
    required bool shareAccount,
    required bool waitingFiat,
  }) {
    final children = <Widget>[];
    final accountVisible = details != null && _holdLocked(trade.phase);
    if (accountVisible) {
      children.add(_AccountCard(details: details, side: side));
    } else if (shareAccount && peer != null) {
      children.add(
        const Text(
          'The CKB is locked. Send the payment details the buyer should use.',
        ),
      );
      children.add(const SizedBox(height: 12));
      children.add(
        TextField(
          controller: _details,
          enabled: !_blocked,
          minLines: 3,
          maxLines: 6,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
            labelText: 'Payment details',
            alignLabelWithHint: true,
            hintText: 'Bank, account name, account number',
          ),
        ),
      );
      children.add(const SizedBox(height: 12));
      children.add(
        FilledButton(
          onPressed: _blocked ? null : () => _share(trade),
          child: _actionChild('Send', _Work.share),
        ),
      );
    } else if (shareAccount) {
      children.add(const Text('Waiting to learn who the buyer is.'));
    } else if (waitingFiat) {
      children.add(
        const Text(
          'The CKB is locked. Waiting for the seller to share the account you should pay.',
        ),
      );
    }
    if (trade.payoutFailure != null) {
      children.add(const SizedBox(height: 12));
      children.add(Text(trade.payoutFailure!));
      if (side == TradeSide.buyer) {
        children.add(const SizedBox(height: 8));
        children.add(const Text('Paste another invoice for the same payment.'));
      }
    }
    if (actions.payHold) {
      children.add(const SizedBox(height: 12));
      children.add(
        const Text(
          'A buyer took this. Pay this invoice in your Fiber wallet. You cannot cancel after it locks.',
        ),
      );
      children.add(const SizedBox(height: 8));
      children.add(
        Center(
          child: QrImageView(
            data: trade.holdInvoice!,
            size: 180,
            backgroundColor: Colors.white,
          ),
        ),
      );
      children.add(const SizedBox(height: 8));
      children.add(
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: SelectableText(trade.holdInvoice!)),
            IconButton(
              tooltip: 'Copy invoice',
              onPressed: () => _copy(trade.holdInvoice!),
              icon: const Icon(Icons.copy),
            ),
          ],
        ),
      );
      children.add(const SizedBox(height: 4));
      children.add(
        const Text('Waiting for the operator node to report the lock.'),
      );
    } else if (side == TradeSide.buyer &&
        trade.phase == TradePhase.waitingHold) {
      children.add(const SizedBox(height: 12));
      children.add(
        const Text(
          'When the seller locks the CKB, they send the account you should pay.',
        ),
      );
    } else if (side == null && trade.phase == TradePhase.waitingHold) {
      children.add(const SizedBox(height: 12));
      children.add(const Text('Waiting to learn who locks the CKB.'));
    }
    if (trade.phase == TradePhase.fiatSent && side == TradeSide.seller) {
      children.add(const SizedBox(height: 12));
      children.add(
        const Text(
          'The buyer says they paid. Release the CKB after the money is in your account.',
        ),
      );
    } else if (trade.phase == TradePhase.fiatSent && side == TradeSide.buyer) {
      children.add(const SizedBox(height: 12));
      children.add(const Text('Waiting for the seller to release the CKB.'));
    }
    if (proof != null &&
        side == TradeSide.seller &&
        (trade.phase == TradePhase.fiatSent ||
            trade.phase == TradePhase.disputed)) {
      children.add(const SizedBox(height: 12));
      children.add(_ReceiptCard(proof: proof, onOpen: _openReceipt));
    }
    if (trade.phase == TradePhase.releasing) {
      children.add(const SizedBox(height: 12));
      children.add(const Text('Sending the CKB to the invoice on file.'));
    }
    if (trade.phase == TradePhase.disputed) {
      children.add(const SizedBox(height: 12));
      children.add(Text(_disputeLine(trade)));
    }
    if (actions.submitInvoice) {
      children.add(const SizedBox(height: 12));
      children.add(_invoiceField(trade));
      children.add(const SizedBox(height: 12));
      children.add(
        FilledButton(
          onPressed: _blocked ? null : () => _submitInvoice(trade),
          child: _actionChild('Submit payout invoice', _Work.invoice),
        ),
      );
    }
    if (waitingFiat && details != null) {
      children.add(const SizedBox(height: 12));
      children.add(
        FilledButton(
          onPressed: _blocked ? null : () => _paid(trade, proof != null),
          child: _actionChild("I've paid", _Work.paid),
        ),
      );
    } else if (actions.sendFiat && trade.phase != TradePhase.waitingFiat) {
      children.add(const SizedBox(height: 12));
      children.add(_invoiceField(trade));
      children.add(const SizedBox(height: 12));
      children.add(
        FilledButton(
          onPressed: _blocked ? null : () => _fiat(trade),
          child: _actionChild('Submit payout invoice', _Work.invoice),
        ),
      );
    }
    if (actions.release) {
      children.add(const SizedBox(height: 12));
      children.add(
        FilledButton(
          onPressed: _blocked ? null : () => _release(trade),
          child: _actionChild('Release the CKB', _Work.release),
        ),
      );
    }
    if (actions.dispute) {
      children.add(const SizedBox(height: 12));
      children.add(
        OutlinedButton(
          onPressed: _blocked ? null : () => _dispute(trade),
          child: _actionChild('Dispute', _Work.dispute),
        ),
      );
    }
    if (actions.cancel) {
      children.add(const SizedBox(height: 4));
      children.add(
        TextButton(
          onPressed: _blocked ? null : () => _cancel(trade),
          child: _actionChild('Cancel trade', _Work.cancel),
        ),
      );
    }
    if (children.isEmpty) return null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    );
  }

  Widget _invoiceField(TwineTrade trade) {
    return TextField(
      controller: _invoice,
      enabled: !_blocked,
      minLines: 1,
      maxLines: 4,
      autocorrect: false,
      enableSuggestions: false,
      decoration: InputDecoration(
        labelText: 'Fiber invoice for the CKB',
        helperText: _invoiceHelp(trade),
      ),
    );
  }

  Widget _composer(TwineTrade trade) {
    final blocked = _blocked;
    final over = _chat.text.length > maxChatText;
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Focus(
                  onKeyEvent: _trackShift,
                  child: TextField(
                    controller: _chat,
                    enabled: !blocked,
                    minLines: 1,
                    maxLines: 4,
                    textCapitalization: TextCapitalization.sentences,
                    textInputAction: TextInputAction.send,
                    onSubmitted: blocked ? null : (_) => _send(trade),
                    onChanged: (value) {
                      if (_shiftHeld || !value.contains('\n')) return;
                      final text = value.replaceAll('\n', '');
                      _chat.value = TextEditingValue(
                        text: text,
                        selection: TextSelection.collapsed(offset: text.length),
                      );
                      if (text.trim().isEmpty || blocked) return;
                      _send(trade);
                    },
                    decoration: const InputDecoration(
                      hintText: 'Message',
                      isDense: true,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filled(
                tooltip: 'Send message',
                onPressed: blocked ? null : () => _send(trade),
                icon: _busy == _Work.chat
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.send),
              ),
            ],
          ),
          if (_nearLimit) ...[
            const SizedBox(height: 4),
            Text(
              '${_chat.text.length}/$maxChatText',
              style: theme.textTheme.labelSmall?.copyWith(
                color: over
                    ? theme.colorScheme.error
                    : theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }

  bool get _blocked => widget.market.sending || _busy != null;

  Widget _actionChild(String label, _Work work) {
    if (_busy != work) return Text(label);
    return const SizedBox(
      height: 18,
      width: 18,
      child: CircularProgressIndicator(strokeWidth: 2),
    );
  }

  List<Widget> _clocks(TwineTrade trade, TradeSide? side) {
    final now = DateTime.now().toUtc();
    final lines = <Widget>[];
    if (trade.phase == TradePhase.waitingInvoice) {
      final due = trade.invoiceBy;
      if (due != null) {
        final left = remainingLabel(due, now);
        lines.add(
          Text(
            side == TradeSide.buyer
                ? 'Send the payout invoice. $left'
                : 'Waiting for the payout invoice. $left',
          ),
        );
      } else {
        lines.add(const Text('The payout invoice is due within an hour.'));
      }
    } else if (trade.phase == TradePhase.waitingHold) {
      if (side == TradeSide.seller) {
        if (trade.lockBy != null) {
          lines.add(Text(remainingLabel(trade.lockBy!, now)));
        } else {
          lines.add(const Text('Pay the hold invoice within an hour.'));
        }
      }
    } else if (!trade.phase.terminal && trade.phase != TradePhase.refunding) {
      if (side == TradeSide.buyer && trade.phase == TradePhase.waitingFiat) {
        if (trade.payBy != null) {
          lines.add(Text(remainingLabel(trade.payBy!, now)));
        } else {
          lines.add(const Text('Pay before the hold’s release deadline.'));
        }
      }
      if (trade.releaseBy != null) {
        lines.add(
          Text('Release window: ${remainingLabel(trade.releaseBy!, now)}'),
        );
      } else {
        lines.add(
          const Text('Release at least 30 minutes before the hold ends.'),
        );
      }
      if (trade.holdEndsAt != null) {
        lines.add(
          Text(
            'The hold returns the CKB to the seller ${remainingLabel(trade.holdEndsAt!, now)}.',
          ),
        );
      } else {
        lines.add(
          const Text('The hold returns the CKB to the seller when it ends.'),
        );
      }
    }
    if (lines.isEmpty) return const [];
    return [const SizedBox(height: 8), ...lines];
  }

  String _npub(String hex) {
    final key = hex.trim().toLowerCase();
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(key)) return hex;
    try {
      return widget.market.nostr.nostr.bech32.encodePublicKeyToNpub(key);
    } catch (_) {
      return hex;
    }
  }

  String _invoiceHelp(TwineTrade trade) {
    if (trade.phase == TradePhase.awaitingInvoice ||
        trade.phase == TradePhase.disputed) {
      return 'Use the same payment hash as the invoice already on this trade. A new hash cannot settle the hold.';
    }
    final amount = trade.amountShannons == null
        ? 'the locked CKB'
        : '${shannonsToCkb(trade.amountShannons!)} CKB';
    return 'Paste the invoice from the wallet that should receive the CKB. The hold uses this invoice\'s payment hash, and $amount is paid there.';
  }

  List<TradeNote> _lines(String tradeId) {
    return widget.market.book.thread(tradeId);
  }

  void _pin(int count) {
    if (count == _pinned) return;
    _pinned = count;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_thread.hasClients) return;
      final position = _thread.position;
      if (!position.hasContentDimensions) return;
      if (position.maxScrollExtent <= 0) return;
      _thread.jumpTo(position.maxScrollExtent);
    });
  }

  void _liftNotice(String? stored) {
    if (stored == null || _lifting || stored == _banner) return;
    _lifting = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _lifting = false;
      if (!mounted) return;
      final trade = widget.market.book.trade(widget.tradeId);
      final current = trade?.notice ?? widget.market.book.notice;
      if (current == null) return;
      widget.market.dismissTradeNotice(widget.tradeId);
      setState(() => _banner = current);
    });
  }

  void _dismissNotice() {
    if (!mounted) return;
    setState(() {
      _banner = null;
      _error = null;
    });
  }

  Future<void> _copy(String value) async {
    await Clipboard.setData(ClipboardData(text: value));
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Copied')));
  }

  void _openReceipt(Uint8List bytes) {
    showDialog<void>(
      context: context,
      builder: (context) {
        return Dialog(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Align(
                  alignment: Alignment.centerRight,
                  child: IconButton(
                    tooltip: 'Close',
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 480),
                  child: InteractiveViewer(
                    child: Image.memory(bytes, fit: BoxFit.contain),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _run(_Work work, Future<String?> Function() action) async {
    if (_busy != null || widget.market.sending) return;
    _busy = work;
    setState(() {});
    final error = await action();
    if (!mounted) return;
    setState(() {
      _busy = null;
      _error = error;
    });
  }

  Future<void> _share(TwineTrade trade) {
    return _run(_Work.share, () {
      return widget.market.shareAccount(trade.id, details: _details.text);
    });
  }

  Future<void> _paid(TwineTrade trade, bool hasProof) async {
    if (_busy != null || widget.market.sending) return;
    final details = widget.market.book.paymentDetails(trade.id);
    if (details == null) return;
    final paid = await showModalBottomSheet<_PaidInput>(
      context: context,
      isScrollControlled: true,
      builder: (context) => _PaidSheet(
        amount: '${trade.fiatAmount ?? ''} ${trade.fiatCurrency ?? ''}'.trim(),
        needsReceipt: !hasProof,
      ),
    );
    if (paid == null || !mounted) return;
    await _run(
      _Work.paid,
      () => widget.market.markPaid(trade.id, image: paid.image),
    );
  }

  Future<void> _submitInvoice(TwineTrade trade) {
    return _run(
      _Work.invoice,
      () => widget.market.submitPayoutInvoice(trade.id, _invoice.text),
    );
  }

  Future<void> _send(TwineTrade trade) async {
    if (_busy != null || widget.market.sending) return;
    final text = _chat.text;
    await _run(_Work.chat, () => widget.market.sendChat(trade.id, text));
    if (!mounted) return;
    if (_error == null) _chat.clear();
  }

  Future<void> _fiat(TwineTrade trade) {
    return _run(
      _Work.invoice,
      () => widget.market.fiatSent(trade.id, _invoice.text),
    );
  }

  Future<void> _release(TwineTrade trade) async {
    if (_busy != null || widget.market.sending) return;
    final ckb = trade.amountShannons == null
        ? 'the locked CKB'
        : '${shannonsToCkb(trade.amountShannons!)} CKB';
    final fiat = '${trade.fiatAmount ?? ''} ${trade.fiatCurrency ?? ''}'.trim();
    final reference = trade.reference ?? trade.id;
    final confirmed = await _confirm(
      context,
      'Release the CKB?',
      'Release $ckb for $fiat (reference $reference). This pays the payout invoice on file.',
    );
    if (!confirmed || !mounted) return;
    await _run(_Work.release, () => widget.market.release(trade.id));
  }

  Future<void> _dispute(TwineTrade trade) async {
    if (_busy != null || widget.market.sending) return;
    final confirmed = await _confirm(
      context,
      'Open a dispute?',
      '${_disputeLine(trade)} You can still release if a payout invoice is stored.',
    );
    if (!confirmed || !mounted) return;
    final invoice = _invoice.text.trim();
    await _run(_Work.dispute, () {
      return widget.market.dispute(
        trade.id,
        invoice: invoice.isEmpty ? null : invoice,
      );
    });
  }

  Future<void> _cancel(TwineTrade trade) async {
    if (_busy != null || widget.market.sending) return;
    final confirmed = await _confirm(
      context,
      'Cancel this trade?',
      'This ends the trade before the CKB is locked.',
    );
    if (!confirmed || !mounted) return;
    await _run(_Work.cancel, () => widget.market.cancelTrade(trade.id));
  }
}

String _sideLine(TradeSide? side) {
  switch (side) {
    case TradeSide.buyer:
      return 'You are the buyer.';
    case TradeSide.seller:
      return 'You are the seller.';
    case null:
      return 'Waiting to learn which side you are on.';
  }
}

class _Parties extends StatelessWidget {
  const _Parties({
    required this.me,
    required this.encode,
    this.seller,
    this.buyer,
  });

  final String me;
  final String? seller;
  final String? buyer;
  final String Function(String hex) encode;

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    void add(String label, String hex) {
      final mine = hex.toLowerCase() == me.toLowerCase();
      final npub = encode(hex);
      rows.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(mine ? 'You · $label' : 'Them · $label'),
                    SelectableText(npub),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Copy',
                onPressed: () => Clipboard.setData(ClipboardData(text: npub)),
                icon: const Icon(Icons.copy),
              ),
            ],
          ),
        ),
      );
    }

    if (seller != null) add('Seller', seller!);
    if (buyer != null) add('Buyer', buyer!);
    if (rows.isEmpty) return const SizedBox.shrink();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: rows);
  }
}

bool _holdLocked(TradePhase phase) {
  switch (phase) {
    case TradePhase.waitingInvoice:
    case TradePhase.waitingHold:
      return false;
    case TradePhase.waitingFiat:
    case TradePhase.fiatSent:
    case TradePhase.releasing:
    case TradePhase.awaitingInvoice:
    case TradePhase.disputed:
    case TradePhase.refunding:
    case TradePhase.settled:
    case TradePhase.canceled:
    case TradePhase.expired:
      return true;
  }
}

class _AccountCard extends StatelessWidget {
  const _AccountCard({required this.details, required this.side});

  final TradeNote details;
  final TradeSide? side;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = details.detailsText;
    final title = side == TradeSide.seller ? 'Account sent' : 'Pay here';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: theme.textTheme.titleSmall),
        const SizedBox(height: 8),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: SelectableText(text.isEmpty ? 'No details.' : text),
            ),
            IconButton(
              tooltip: 'Copy payment details',
              onPressed: text.isEmpty
                  ? null
                  : () => Clipboard.setData(ClipboardData(text: text)),
              icon: const Icon(Icons.copy),
            ),
          ],
        ),
      ],
    );
  }
}

class _ReceiptCard extends StatelessWidget {
  const _ReceiptCard({required this.proof, required this.onOpen});

  final TradeNote proof;
  final void Function(Uint8List bytes) onOpen;

  @override
  Widget build(BuildContext context) {
    final bytes = _receiptBytes(proof.image);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Receipt', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        if (proof.amount != null) Text(proof.amount!),
        if (proof.bankReference != null) SelectableText(proof.bankReference!),
        if (bytes != null)
          _ReceiptImage(bytes: bytes, onOpen: onOpen)
        else
          const Text('The receipt could not be shown.'),
      ],
    );
  }
}

class _ReceiptImage extends StatelessWidget {
  const _ReceiptImage({required this.bytes, required this.onOpen});

  final Uint8List bytes;
  final void Function(Uint8List bytes) onOpen;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: InkWell(
        onTap: () => onOpen(bytes),
        child: Image.memory(bytes, height: 160, fit: BoxFit.contain),
      ),
    );
  }
}

Uint8List? _receiptBytes(String? image) {
  if (image == null) return null;
  try {
    return base64Decode(image);
  } catch (_) {
    return null;
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({
    required this.line,
    required this.mine,
    required this.onOpenReceipt,
  });

  final TradeNote line;
  final bool mine;
  final void Function(Uint8List bytes) onOpenReceipt;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    switch (line.kind) {
      case TradeNoteKind.status:
        return _event(theme, line.text ?? '');
      case TradeNoteKind.paymentDetails:
        return _text(
          context,
          theme,
          body: line.detailsText,
          label: 'Payment details',
        );
      case TradeNoteKind.paymentProof:
        return _proof(context, theme);
      case TradeNoteKind.text:
        return _text(context, theme, body: line.text ?? '');
    }
  }

  Widget _event(ThemeData theme, String text) {
    if (text.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Center(
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }

  Widget _proof(BuildContext context, ThemeData theme) {
    final bytes = _receiptBytes(line.image);
    final bubble = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(mine ? 'You' : 'Them', style: theme.textTheme.labelMedium),
        const SizedBox(height: 4),
        if (bytes != null)
          _ReceiptImage(bytes: bytes, onOpen: onOpenReceipt)
        else
          const Text('The receipt could not be shown.'),
        const SizedBox(height: 4),
        Text(_when(line.at), style: theme.textTheme.labelSmall),
      ],
    );
    return _align(context, theme, bubble);
  }

  Widget _text(
    BuildContext context,
    ThemeData theme, {
    required String body,
    String? label,
  }) {
    final bubble = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(mine ? 'You' : 'Them', style: theme.textTheme.labelMedium),
        if (label != null) ...[
          const SizedBox(height: 2),
          Text(label, style: theme.textTheme.labelSmall),
        ],
        const SizedBox(height: 2),
        SelectableText(body),
        const SizedBox(height: 4),
        Text(
          _when(line.at),
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
    return _align(context, theme, bubble);
  }

  Widget _align(BuildContext context, ThemeData theme, Widget child) {
    final scheme = theme.colorScheme;
    final width = MediaQuery.sizeOf(context).width;
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: width * 0.8),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: mine
                ? scheme.primaryContainer
                : scheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
            child: child,
          ),
        ),
      ),
    );
  }
}

String _when(DateTime at) {
  final local = at.toLocal();
  final hour = local.hour.toString().padLeft(2, '0');
  final minute = local.minute.toString().padLeft(2, '0');
  return '$hour:$minute';
}

class _PaidInput {
  const _PaidInput({this.image});

  final String? image;
}

class _PaidSheet extends StatefulWidget {
  const _PaidSheet({required this.amount, required this.needsReceipt});

  final String amount;
  final bool needsReceipt;

  @override
  State<_PaidSheet> createState() => _PaidSheetState();
}

class _PaidSheetState extends State<_PaidSheet> {
  Uint8List? _receipt;
  String? _error;
  bool _compressing = false;

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    final theme = Theme.of(context);
    final receipt = _receipt;
    final ready = !widget.needsReceipt || receipt != null;
    return Padding(
      padding: EdgeInsets.fromLTRB(24, 12, 24, 16 + bottom),
      child: ListView(
        shrinkWrap: true,
        children: [
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.outlineVariant,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                widget.needsReceipt
                    ? 'Attach the receipt'
                    : 'Mark the payment as sent',
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Text(
                widget.needsReceipt
                    ? 'A photo of the ${widget.amount} payment. Twine shrinks it before it is sent.'
                    : 'The receipt is already on this trade.',
              ),
              if (widget.needsReceipt) ...[
                const SizedBox(height: 16),
                if (receipt != null)
                  Image.memory(receipt, height: 180, fit: BoxFit.contain),
                if (_compressing) ...[
                  const SizedBox(height: 12),
                  const Text('Shrinking the photo…'),
                ],
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    OutlinedButton.icon(
                      onPressed: _compressing
                          ? null
                          : () => _pick(ImageSource.gallery),
                      icon: const Icon(Icons.photo_library_outlined),
                      label: const Text('Photo library'),
                    ),
                    OutlinedButton.icon(
                      onPressed: _compressing
                          ? null
                          : () => _pick(ImageSource.camera),
                      icon: const Icon(Icons.photo_camera_outlined),
                      label: const Text('Camera'),
                    ),
                  ],
                ),
              ],
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(
                  _error!,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
              ],
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _compressing || !ready ? null : _submit,
                child: const Text("I've paid"),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _pick(ImageSource source) async {
    try {
      final file = await ImagePicker().pickImage(
        source: source,
        maxWidth: 1600,
        imageQuality: 85,
      );
      if (file == null || !mounted) return;
      final bytes = await file.readAsBytes();
      if (!mounted) return;
      setState(() {
        _compressing = true;
        _receipt = null;
        _error = null;
      });
      final compressed = await compute(compressReceipt, bytes);
      if (!mounted) return;
      if (compressed == null) {
        setState(() {
          _compressing = false;
          _error = 'That picture could not be sent. Try another one.';
        });
        return;
      }
      setState(() {
        _compressing = false;
        _receipt = compressed;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _compressing = false;
        _error = 'Could not open the camera or library.';
      });
    }
  }

  void _submit() {
    if (widget.needsReceipt && _receipt == null) {
      setState(() => _error = 'Attach the receipt.');
      return;
    }
    Navigator.pop(
      context,
      _PaidInput(image: _receipt == null ? null : base64Encode(_receipt!)),
    );
  }
}

String _paymentLine(TradeSide? side, TwineTrade trade) {
  final amount = '${trade.fiatAmount ?? ''} ${trade.fiatCurrency ?? ''}'.trim();
  switch (side) {
    case TradeSide.buyer:
      return 'Pay $amount.';
    case TradeSide.seller:
      return 'The buyer pays you $amount.';
    case null:
      return 'This trade is for $amount.';
  }
}

String _disputeLine(TwineTrade trade) {
  final solver = trade.solver?.trim();
  final who = solver == null || solver.isEmpty
      ? 'The solver'
      : 'The solver ($solver)';
  return '$who can read this chat. The daemon cannot.';
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
