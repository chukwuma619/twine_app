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
import '../ui/twine_tokens.dart';
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
                padding: EdgeInsets.all(TwineTokens.lg),
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
        _pin(lines.length + (outcome == null ? 0 : 1));
        final timing = _timing(trade, side);
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
          appBar: AppBar(
            title: Text(
              tradeTitle(trade.phase, side),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            actions: [
              IconButton(
                tooltip: 'Trade details',
                onPressed: () => _openDetails(
                  trade: trade,
                  side: side,
                  timing: timing,
                  orderCurrency: order?.fiatCurrency,
                ),
                icon: const Icon(Icons.info_outline),
              ),
            ],
          ),
          body: SafeArea(
            child: Column(
              children: [
                if (notice != null)
                  DismissibleNotice(message: notice, onDismiss: _dismissNotice),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final height = constraints.maxHeight;
                      final summaryMax = height * 0.34 < 148
                          ? height * 0.34
                          : 148.0;
                      final dockCap = height * 0.46 < 240
                          ? height * 0.46
                          : 240.0;
                      return Column(
                        children: [
                          ConstrainedBox(
                            constraints: BoxConstraints(maxHeight: summaryMax),
                            child: SingleChildScrollView(
                              child: _summary(
                                theme: theme,
                                trade: trade,
                                orderCurrency: order?.fiatCurrency,
                                side: side,
                                timing: timing,
                              ),
                            ),
                          ),
                          Expanded(
                            child: _conversation(
                              theme,
                              lines,
                              peer,
                              outcome: outcome,
                            ),
                          ),
                          if (step != null && dockCap > 0)
                            ConstrainedBox(
                              constraints: BoxConstraints(maxHeight: dockCap),
                              child: _ActionDock(child: step),
                            ),
                        ],
                      );
                    },
                  ),
                ),
                if (compose) _composer(trade, separated: step == null),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _summary({
    required ThemeData theme,
    required TwineTrade trade,
    required TradeSide? side,
    required List<String> timing,
    String? orderCurrency,
  }) {
    final scheme = theme.colorScheme;
    final muted = TwineTokens.muted(theme);
    final ckb = trade.amountShannons == null
        ? null
        : '${shannonsToCkb(trade.amountShannons!)} CKB';
    final showPayment = _showPayment(trade);
    final role = switch (side) {
      TradeSide.buyer => 'Buyer',
      TradeSide.seller => 'Seller',
      null => null,
    };
    final deadline = timing.isEmpty ? null : timing.first;
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: scheme.outlineVariant)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          TwineTokens.md,
          TwineTokens.sm,
          TwineTokens.md,
          TwineTokens.sm,
        ),
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
                      if (ckb != null)
                        Text(ckb, style: TwineTokens.title(theme)),
                      if (showPayment) ...[
                        if (ckb != null)
                          const SizedBox(height: TwineTokens.xxs),
                        Text(
                          _paymentLine(side, trade),
                          style: TwineTokens.body(theme),
                        ),
                      ] else if (orderCurrency != null && ckb == null)
                        Text(
                          orderCurrency,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      if (side == null)
                        Padding(
                          padding: const EdgeInsets.only(top: TwineTokens.xxs),
                          child: Text(
                            'Waiting to learn which side you are on.',
                            style: muted,
                          ),
                        ),
                    ],
                  ),
                ),
                if (role != null) ...[
                  const SizedBox(width: TwineTokens.sm),
                  _RoleMark(label: role),
                ],
              ],
            ),
            if (showPayment) ...[
              const SizedBox(height: TwineTokens.xs),
              _CopyLine(
                label: 'Reference',
                value: trade.reference ?? trade.id,
                onCopy: () => _copy(trade.reference ?? trade.id),
              ),
              if (side == TradeSide.buyer) ...[
                const SizedBox(height: TwineTokens.xxs),
                Text('Put the reference on the payment.', style: muted),
              ],
            ],
            if (deadline != null) ...[
              const SizedBox(height: TwineTokens.xs),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.schedule,
                    size: TwineTokens.iconSm,
                    color: scheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: TwineTokens.xs),
                  Expanded(child: Text(deadline, style: muted)),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _conversation(
    ThemeData theme,
    List<TradeNote> lines,
    String? peer, {
    String? outcome,
  }) {
    if (peer == null) {
      return Column(
        children: [
          if (outcome != null) _SystemLine(text: outcome),
          const Expanded(
            child: _ThreadEmpty(
              icon: Icons.lock_outline,
              message: 'The thread opens once this trade has both keys.',
            ),
          ),
        ],
      );
    }
    final closing = outcome == null ? 0 : 1;
    if (lines.isEmpty && closing == 0) {
      return const _ThreadEmpty(
        icon: Icons.chat_bubble_outline,
        message: 'No messages yet.',
      );
    }
    return ListView.builder(
      controller: _thread,
      padding: const EdgeInsets.fromLTRB(
        TwineTokens.md,
        TwineTokens.sm,
        TwineTokens.md,
        TwineTokens.md,
      ),
      itemCount: lines.length + closing,
      itemBuilder: (context, index) {
        if (index == lines.length) {
          return Padding(
            padding: EdgeInsets.only(top: lines.isEmpty ? 0 : TwineTokens.sm),
            child: _SystemLine(text: outcome!),
          );
        }
        final line = lines[index];
        final previous = index == 0 ? null : lines[index - 1];
        final grouped = previous != null && _sameSpeaker(previous, line);
        return Padding(
          padding: EdgeInsets.only(
            top: grouped ? TwineTokens.xxs : (index == 0 ? 0 : TwineTokens.sm),
          ),
          child: _Bubble(
            line: line,
            mine:
                line.author?.toLowerCase() ==
                widget.market.accountPubkey.toLowerCase(),
            showName: !grouped,
            onOpenReceipt: _openReceipt,
          ),
        );
      },
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
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
      height: 1.35,
    );
    void add(Widget child, {double gap = TwineTokens.sm}) {
      if (children.isNotEmpty) children.add(SizedBox(height: gap));
      children.add(child);
    }

    final accountVisible = details != null && _holdLocked(trade.phase);
    if (accountVisible) {
      add(_AccountCard(details: details, side: side));
    } else if (shareAccount && peer != null) {
      add(
        const Text(
          'The CKB is locked. Send the payment details the buyer should use.',
        ),
      );
      add(_detailsField());
      add(_primary('Send', _Work.share, () => _share(trade)));
    } else if (shareAccount) {
      add(const Text('Waiting to learn who the buyer is.'));
    } else if (waitingFiat) {
      add(
        const Text(
          'The CKB is locked. Waiting for the seller to share the account you should pay.',
        ),
      );
    }
    if (trade.payoutFailure != null) {
      add(
        Text(
          trade.payoutFailure!,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.error,
            height: 1.35,
          ),
        ),
      );
      if (side == TradeSide.buyer) {
        add(
          const Text('Paste another invoice for the same payment.'),
          gap: TwineTokens.xs,
        );
      }
    }
    if (actions.payHold) {
      add(
        const Text(
          'A buyer took this. Pay this invoice in your Fiber wallet. You cannot cancel after it locks.',
        ),
      );
      add(_invoiceQr(trade.holdInvoice!), gap: TwineTokens.sm);
      add(_invoiceCopy(trade.holdInvoice!), gap: TwineTokens.xs);
      add(
        Text('Waiting for the operator node to report the lock.', style: muted),
        gap: TwineTokens.xs,
      );
    } else if (side == TradeSide.buyer &&
        trade.phase == TradePhase.waitingHold) {
      add(
        const Text(
          'When the seller locks the CKB, they send the account you should pay.',
        ),
      );
    } else if (side == null && trade.phase == TradePhase.waitingHold) {
      add(const Text('Waiting to learn who locks the CKB.'));
    }
    if (trade.phase == TradePhase.fiatSent && side == TradeSide.seller) {
      add(
        const Text(
          'The buyer says they paid. Release the CKB after the money is in your account.',
        ),
      );
    } else if (trade.phase == TradePhase.fiatSent && side == TradeSide.buyer) {
      add(const Text('Waiting for the seller to release the CKB.'));
    }
    if (proof != null &&
        side == TradeSide.seller &&
        (trade.phase == TradePhase.fiatSent ||
            trade.phase == TradePhase.disputed)) {
      add(_ReceiptCard(proof: proof, onOpen: _openReceipt));
    }
    if (trade.phase == TradePhase.releasing) {
      add(const Text('Sending the CKB to the invoice on file.'));
    }
    if (trade.phase == TradePhase.disputed) {
      add(Text(_disputeLine(trade)));
    }
    if (actions.submitInvoice) {
      add(_invoiceField(trade));
      add(
        _primary(
          'Submit payout invoice',
          _Work.invoice,
          () => _submitInvoice(trade),
        ),
      );
    }
    if (waitingFiat && details != null) {
      add(_primary("I've paid", _Work.paid, () => _paid(trade, proof != null)));
    } else if (actions.sendFiat && trade.phase != TradePhase.waitingFiat) {
      add(_invoiceField(trade));
      add(_primary('Submit payout invoice', _Work.invoice, () => _fiat(trade)));
    }
    if (actions.release) {
      add(_primary('Release the CKB', _Work.release, () => _release(trade)));
    }
    if (actions.dispute) {
      add(
        _quiet('Dispute', _Work.dispute, () => _dispute(trade)),
        gap: TwineTokens.xs,
      );
    }
    if (actions.cancel) {
      add(
        _quiet('Cancel trade', _Work.cancel, () => _cancel(trade)),
        gap: TwineTokens.xxs,
      );
    }
    if (children.isEmpty) return null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    );
  }

  Widget _detailsField() {
    return TextField(
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
    );
  }

  Widget _invoiceQr(String invoice) {
    return Center(
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(TwineTokens.radiusSm),
        ),
        child: Padding(
          padding: const EdgeInsets.all(TwineTokens.sm),
          child: QrImageView(
            data: invoice,
            size: 168,
            backgroundColor: Colors.white,
          ),
        ),
      ),
    );
  }

  Widget _invoiceCopy(String invoice) {
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(TwineTokens.radiusSm),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                TwineTokens.sm,
                10,
                TwineTokens.xxs,
                10,
              ),
              child: SelectableText(
                invoice,
                style: theme.textTheme.bodySmall?.copyWith(height: 1.35),
              ),
            ),
          ),
          IconButton(
            tooltip: 'Copy invoice',
            visualDensity: VisualDensity.compact,
            onPressed: () => _copy(invoice),
            icon: const Icon(Icons.copy, size: 20),
          ),
        ],
      ),
    );
  }

  Widget _primary(String label, _Work work, VoidCallback onPressed) {
    return FilledButton(
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(TwineTokens.control),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(TwineTokens.radiusSm),
        ),
      ),
      onPressed: _blocked ? null : onPressed,
      child: _actionChild(label, work),
    );
  }

  Widget _quiet(String label, _Work work, VoidCallback onPressed) {
    final theme = Theme.of(context);
    return TextButton(
      style: TextButton.styleFrom(
        foregroundColor: theme.colorScheme.error,
        minimumSize: const Size.fromHeight(40),
      ),
      onPressed: _blocked ? null : onPressed,
      child: _actionChild(label, work),
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

  Widget _composer(TwineTrade trade, {required bool separated}) {
    final blocked = _blocked;
    final over = _chat.text.length > maxChatText;
    final canSend = !blocked && _chat.text.trim().isNotEmpty && !over;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final radius = BorderRadius.circular(TwineTokens.radiusComposer);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surface,
        border: separated
            ? Border(top: BorderSide(color: scheme.outlineVariant))
            : null,
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          TwineTokens.sm,
          TwineTokens.xs,
          TwineTokens.sm,
          TwineTokens.sm,
        ),
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
                      onSubmitted: canSend ? (_) => _send(trade) : null,
                      onChanged: (value) {
                        if (_shiftHeld || !value.contains('\n')) return;
                        final text = value.replaceAll('\n', '');
                        _chat.value = TextEditingValue(
                          text: text,
                          selection: TextSelection.collapsed(
                            offset: text.length,
                          ),
                        );
                        if (text.trim().isEmpty || blocked || over) return;
                        _send(trade);
                      },
                      decoration: InputDecoration(
                        hintText: 'Message',
                        isDense: true,
                        filled: true,
                        fillColor: scheme.surfaceContainerHighest,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: TwineTokens.md,
                          vertical: TwineTokens.sm,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: radius,
                          borderSide: BorderSide.none,
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: radius,
                          borderSide: BorderSide.none,
                        ),
                        disabledBorder: OutlineInputBorder(
                          borderRadius: radius,
                          borderSide: BorderSide.none,
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: radius,
                          borderSide: BorderSide(
                            color: scheme.primary,
                            width: 1.5,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: TwineTokens.xs),
                IconButton.filled(
                  tooltip: 'Send message',
                  style: IconButton.styleFrom(
                    minimumSize: const Size(
                      TwineTokens.control,
                      TwineTokens.control,
                    ),
                    fixedSize: const Size(
                      TwineTokens.control,
                      TwineTokens.control,
                    ),
                  ),
                  onPressed: canSend ? () => _send(trade) : null,
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
              const SizedBox(height: TwineTokens.xxs),
              Padding(
                padding: const EdgeInsets.only(right: TwineTokens.control),
                child: Text(
                  '${_chat.text.length}/$maxChatText',
                  textAlign: TextAlign.end,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: over ? scheme.error : scheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ],
        ),
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

  List<String> _timing(TwineTrade trade, TradeSide? side) {
    final now = DateTime.now().toUtc();
    final lines = <String>[];
    if (trade.phase == TradePhase.waitingInvoice) {
      final due = trade.invoiceBy;
      if (due != null) {
        final left = remainingLabel(due, now);
        lines.add(
          side == TradeSide.buyer
              ? 'Send the payout invoice. $left'
              : 'Waiting for the payout invoice. $left',
        );
      } else {
        lines.add('The payout invoice is due within an hour.');
      }
    } else if (trade.phase == TradePhase.waitingHold) {
      if (side == TradeSide.seller) {
        if (trade.lockBy != null) {
          lines.add(remainingLabel(trade.lockBy!, now));
        } else {
          lines.add('Pay the hold invoice within an hour.');
        }
      }
    } else if (!trade.phase.terminal && trade.phase != TradePhase.refunding) {
      if (side == TradeSide.buyer && trade.phase == TradePhase.waitingFiat) {
        if (trade.payBy != null) {
          lines.add(remainingLabel(trade.payBy!, now));
        } else {
          lines.add('Pay before the hold’s release deadline.');
        }
      }
      if (trade.releaseBy != null) {
        lines.add('Release window: ${remainingLabel(trade.releaseBy!, now)}');
      } else {
        lines.add('Release at least 30 minutes before the hold ends.');
      }
      if (trade.holdEndsAt != null) {
        lines.add(
          'The hold returns the CKB to the seller ${remainingLabel(trade.holdEndsAt!, now)}.',
        );
      } else {
        lines.add('The hold returns the CKB to the seller when it ends.');
      }
    }
    return lines;
  }

  void _openDetails({
    required TwineTrade trade,
    required TradeSide? side,
    required List<String> timing,
    String? orderCurrency,
  }) {
    final amount = trade.amountShannons == null
        ? null
        : '${shannonsToCkb(trade.amountShannons!)} CKB';
    final reference = trade.reference ?? trade.id;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) {
        final theme = Theme.of(context);
        final bottom = MediaQuery.viewPaddingOf(context).bottom;
        final muted = TwineTokens.muted(theme);
        return Padding(
          padding: EdgeInsets.fromLTRB(
            TwineTokens.md,
            0,
            TwineTokens.md,
            TwineTokens.lg + bottom,
          ),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Trade details', style: TwineTokens.title(theme)),
                const SizedBox(height: TwineTokens.md),
                Text(_sideLine(side), style: TwineTokens.body(theme)),
                if (amount != null) ...[
                  const SizedBox(height: TwineTokens.sm),
                  Text(
                    amount,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ] else if (orderCurrency != null) ...[
                  const SizedBox(height: TwineTokens.xs),
                  Text(orderCurrency),
                ],
                const SizedBox(height: TwineTokens.md),
                Text('Reference', style: TwineTokens.section(theme)),
                const SizedBox(height: TwineTokens.xxs),
                Row(
                  children: [
                    Expanded(child: SelectableText(reference)),
                    IconButton(
                      tooltip: 'Copy reference',
                      visualDensity: VisualDensity.compact,
                      onPressed: () => _copy(reference),
                      icon: const Icon(Icons.copy, size: 20),
                    ),
                  ],
                ),
                if (timing.isNotEmpty) ...[
                  const SizedBox(height: TwineTokens.sm),
                  Text('Timing', style: TwineTokens.section(theme)),
                  const SizedBox(height: TwineTokens.xxs),
                  for (final line in timing)
                    Padding(
                      padding: const EdgeInsets.only(bottom: TwineTokens.xxs),
                      child: Text(
                        line,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          height: 1.35,
                        ),
                      ),
                    ),
                ],
                const SizedBox(height: TwineTokens.xs),
                _Parties(
                  me: widget.market.accountPubkey,
                  seller: trade.sellerNostr,
                  buyer: trade.buyerNostr,
                  encode: _npub,
                ),
                const SizedBox(height: TwineTokens.xs),
                Text(
                  'Encrypted to the other trader. The relay can see that these two keys are talking.',
                  style: muted,
                ),
              ],
            ),
          ),
        );
      },
    );
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
                  constraints: BoxConstraints(
                    maxHeight: 480,
                    maxWidth: MediaQuery.sizeOf(context).width - 48,
                  ),
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
      showDragHandle: true,
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
    final theme = Theme.of(context);
    final rows = <Widget>[];
    void add(String label, String hex) {
      final mine = hex.toLowerCase() == me.toLowerCase();
      final npub = encode(hex);
      rows.add(
        Padding(
          padding: const EdgeInsets.only(bottom: TwineTokens.xs),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      mine ? 'You · $label' : 'Them · $label',
                      style: theme.textTheme.labelMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: TwineTokens.xxs),
                    SelectableText(
                      npub,
                      style: theme.textTheme.bodySmall?.copyWith(height: 1.35),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Copy',
                visualDensity: VisualDensity.compact,
                onPressed: () => Clipboard.setData(ClipboardData(text: npub)),
                icon: const Icon(Icons.copy, size: 20),
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
    final body = text.isEmpty ? 'No details.' : text;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: TwineTokens.xs),
        DecoratedBox(
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: BorderRadius.circular(TwineTokens.radiusSm),
            border: Border.all(color: theme.colorScheme.outlineVariant),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                    TwineTokens.sm,
                    10,
                    TwineTokens.xxs,
                    10,
                  ),
                  child: SelectableText(
                    body,
                    style: theme.textTheme.bodyMedium?.copyWith(height: 1.35),
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Copy payment details',
                visualDensity: VisualDensity.compact,
                onPressed: text.isEmpty
                    ? null
                    : () => Clipboard.setData(ClipboardData(text: text)),
                icon: const Icon(Icons.copy, size: 20),
              ),
            ],
          ),
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
    final theme = Theme.of(context);
    final bytes = _receiptBytes(proof.image);
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
      height: 1.35,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Receipt',
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        if (proof.amount != null) ...[
          const SizedBox(height: TwineTokens.xxs),
          Text(proof.amount!, style: theme.textTheme.bodyMedium),
        ],
        if (proof.bankReference != null) ...[
          const SizedBox(height: 2),
          SelectableText(proof.bankReference!, style: muted),
        ],
        const SizedBox(height: TwineTokens.xs),
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
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : MediaQuery.sizeOf(context).width;
        return Align(
          alignment: Alignment.centerLeft,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxWidth, maxHeight: 160),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () => onOpen(bytes),
                borderRadius: BorderRadius.circular(TwineTokens.radiusSm),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(TwineTokens.radiusSm),
                  child: Image.memory(
                    bytes,
                    width: maxWidth,
                    height: 160,
                    fit: BoxFit.contain,
                  ),
                ),
              ),
            ),
          ),
        );
      },
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

bool _sameSpeaker(TradeNote previous, TradeNote line) {
  if (previous.kind == TradeNoteKind.status ||
      line.kind == TradeNoteKind.status) {
    return false;
  }
  return previous.author?.toLowerCase() == line.author?.toLowerCase();
}

class _Bubble extends StatelessWidget {
  const _Bubble({
    required this.line,
    required this.mine,
    required this.showName,
    required this.onOpenReceipt,
  });

  final TradeNote line;
  final bool mine;
  final bool showName;
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
      padding: const EdgeInsets.symmetric(vertical: TwineTokens.xxs),
      child: Center(
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(TwineTokens.radiusPill),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: TwineTokens.sm,
              vertical: TwineTokens.xxs,
            ),
            child: Text(
              text,
              textAlign: TextAlign.center,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                height: 1.3,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _proof(BuildContext context, ThemeData theme) {
    final bytes = _receiptBytes(line.image);
    final colors = _BubbleInk.of(theme, mine);
    final bubble = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (bytes != null)
          _ReceiptImage(bytes: bytes, onOpen: onOpenReceipt)
        else
          const Text('The receipt could not be shown.'),
        const SizedBox(height: TwineTokens.xxs),
        Text(_when(line.at), style: _BubbleInk.time(theme, colors.meta)),
      ],
    );
    return _align(context, theme, bubble, colors);
  }

  Widget _text(
    BuildContext context,
    ThemeData theme, {
    required String body,
    String? label,
  }) {
    final colors = _BubbleInk.of(theme, mine);
    final bubble = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (label != null) ...[
          Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(
              color: colors.meta,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: TwineTokens.xxs),
        ],
        SelectableText(
          body,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: colors.foreground,
            height: 1.35,
          ),
        ),
        const SizedBox(height: TwineTokens.xxs),
        Align(
          alignment: Alignment.centerRight,
          child: Text(
            _when(line.at),
            style: _BubbleInk.time(theme, colors.meta),
          ),
        ),
      ],
    );
    return _align(context, theme, bubble, colors);
  }

  Widget _align(
    BuildContext context,
    ThemeData theme,
    Widget child,
    _BubbleInk colors,
  ) {
    final tail = TwineTokens.radiusBubbleTail;
    final round = TwineTokens.radiusMd;
    final corner = showName ? tail : round;
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.maxWidth.isFinite
            ? constraints.maxWidth * 0.78
            : MediaQuery.sizeOf(context).width * 0.78;
        return Align(
          alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxWidth),
            child: Column(
              crossAxisAlignment: mine
                  ? CrossAxisAlignment.end
                  : CrossAxisAlignment.start,
              children: [
                if (showName)
                  Padding(
                    padding: const EdgeInsets.only(bottom: TwineTokens.xxs),
                    child: Text(
                      mine ? 'You' : 'Them',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: colors.fill,
                    borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(mine ? round : corner),
                      topRight: Radius.circular(mine ? corner : round),
                      bottomLeft: Radius.circular(round),
                      bottomRight: Radius.circular(round),
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(
                      TwineTokens.sm,
                      TwineTokens.xs,
                      TwineTokens.sm,
                      TwineTokens.xs,
                    ),
                    child: child,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _BubbleInk {
  const _BubbleInk({
    required this.fill,
    required this.foreground,
    required this.meta,
  });

  final Color fill;
  final Color foreground;
  final Color meta;

  static _BubbleInk of(ThemeData theme, bool mine) {
    final scheme = theme.colorScheme;
    if (mine) {
      return _BubbleInk(
        fill: scheme.primaryContainer,
        foreground: scheme.onPrimaryContainer,
        meta: scheme.onPrimaryContainer.withValues(alpha: 0.72),
      );
    }
    return _BubbleInk(
      fill: scheme.surfaceContainerHigh,
      foreground: scheme.onSurface,
      meta: scheme.onSurfaceVariant,
    );
  }

  static TextStyle? time(ThemeData theme, Color color) {
    return theme.textTheme.labelSmall?.copyWith(color: color, height: 1.2);
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
      padding: EdgeInsets.fromLTRB(24, 4, 24, 16 + bottom),
      child: ListView(
        shrinkWrap: true,
        children: [
          Text(
            widget.needsReceipt
                ? 'Attach the receipt'
                : 'Mark the payment as sent',
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w600,
              height: 1.2,
            ),
          ),
          const SizedBox(height: TwineTokens.xs),
          Text(
            widget.needsReceipt
                ? 'A photo of the ${widget.amount} payment. Twine shrinks it before it is sent.'
                : 'The receipt is already on this trade.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              height: 1.35,
            ),
          ),
          if (widget.needsReceipt) ...[
            const SizedBox(height: TwineTokens.md),
            if (receipt != null)
              ClipRRect(
                borderRadius: BorderRadius.circular(TwineTokens.radiusSm),
                child: Image.memory(
                  receipt,
                  height: 180,
                  width: MediaQuery.sizeOf(context).width - 48,
                  fit: BoxFit.contain,
                ),
              ),
            if (_compressing) ...[
              const SizedBox(height: TwineTokens.sm),
              const Text('Shrinking the photo…'),
            ],
            const SizedBox(height: TwineTokens.sm),
            Wrap(
              spacing: TwineTokens.xs,
              runSpacing: TwineTokens.xs,
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
            const SizedBox(height: TwineTokens.xs),
            Text(
              _error!,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.error,
                height: 1.35,
              ),
            ),
          ],
          const SizedBox(height: TwineTokens.md),
          FilledButton(
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(TwineTokens.control),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(TwineTokens.radiusSm),
              ),
            ),
            onPressed: _compressing || !ready ? null : _submit,
            child: const Text("I've paid"),
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

bool _showPayment(TwineTrade trade) {
  return trade.fiatAmount != null &&
      trade.phase != TradePhase.waitingHold &&
      trade.phase != TradePhase.waitingInvoice;
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
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Confirm'),
          ),
        ],
      );
    },
  );
  return confirmed == true;
}

class _ActionDock extends StatelessWidget {
  const _ActionDock({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return DecoratedBox(
      decoration: TwineTokens.dock(scheme),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          TwineTokens.md,
          TwineTokens.sm,
          TwineTokens.md,
          TwineTokens.sm,
        ),
        child: DefaultTextStyle.merge(
          style: TwineTokens.body(theme),
          child: child,
        ),
      ),
    );
  }
}

class _RoleMark extends StatelessWidget {
  const _RoleMark({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(TwineTokens.radiusPill),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: TwineTokens.sm,
          vertical: TwineTokens.xxs,
        ),
        child: Text(
          label,
          style: theme.textTheme.labelMedium?.copyWith(
            color: theme.colorScheme.onSecondaryContainer,
            fontWeight: FontWeight.w600,
            height: 1.2,
          ),
        ),
      ),
    );
  }
}

class _CopyLine extends StatelessWidget {
  const _CopyLine({
    required this.label,
    required this.value,
    required this.onCopy,
  });

  final String label;
  final String value;
  final VoidCallback onCopy;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(child: Text(label, style: TwineTokens.muted(theme))),
            IconButton(
              tooltip: 'Copy $label',
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints.tightFor(
                width: TwineTokens.control,
                height: TwineTokens.control,
              ),
              onPressed: onCopy,
              icon: const Icon(Icons.copy, size: TwineTokens.iconSm),
            ),
          ],
        ),
        SelectableText(
          value,
          style: theme.textTheme.bodyMedium?.copyWith(height: 1.3),
        ),
      ],
    );
  }
}

class _SystemLine extends StatelessWidget {
  const _SystemLine({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: TwineTokens.xs),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
          height: 1.35,
        ),
      ),
    );
  }
}

class _ThreadEmpty extends StatelessWidget {
  const _ThreadEmpty({required this.icon, required this.message});

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = theme.textTheme.bodyMedium?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
      height: 1.35,
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxHeight < 20) return const SizedBox.shrink();
        final text = Text(message, textAlign: TextAlign.center, style: style);
        if (constraints.maxHeight < 88) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: TwineTokens.md),
              child: text,
            ),
          );
        }
        return Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: TwineTokens.lg),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 28, color: theme.colorScheme.outline),
                const SizedBox(height: TwineTokens.xs),
                text,
              ],
            ),
          ),
        );
      },
    );
  }
}
