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
  final _detailsFocus = FocusNode();
  final _detailsFieldKey = GlobalKey();
  final _chat = TextEditingController();
  final _thread = ScrollController();
  String? _error;
  String? _banner;
  bool _lifting = false;
  bool _nearLimit = false;
  bool _shiftHeld = false;
  bool _editingDetails = false;
  _Work? _busy;
  int _pinned = -1;
  double _lastBottomInset = 0;

  @override
  void initState() {
    super.initState();
    _chat.addListener(_onDraft);
    _invoice.addListener(_clearError);
    _details.addListener(_clearError);
    _detailsFocus.addListener(_onDetailsFocus);
  }

  @override
  void dispose() {
    _chat.removeListener(_onDraft);
    _invoice.removeListener(_clearError);
    _details.removeListener(_clearError);
    _detailsFocus.removeListener(_onDetailsFocus);
    _invoice.dispose();
    _details.dispose();
    _detailsFocus.dispose();
    _chat.dispose();
    _thread.dispose();
    super.dispose();
  }

  void _clearError() {
    if (_error == null || !mounted) return;
    setState(() => _error = null);
  }

  void _onDetailsFocus() {
    if (mounted) setState(() {});
  }

  void _onDraft() {
    final near = _chat.text.length >= 800;
    final clearErr = _error != null;
    if (!near && !_nearLimit && !clearErr) return;
    if (!mounted) return;
    setState(() {
      _nearLimit = near;
      _error = null;
    });
  }

  KeyEventResult _onComposerKey(
    FocusNode node,
    KeyEvent event,
    TwineTrade trade,
  ) {
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.shiftLeft ||
        key == LogicalKeyboardKey.shiftRight) {
      _shiftHeld = event is! KeyUpEvent;
      return KeyEventResult.ignored;
    }
    if ((key == LogicalKeyboardKey.enter ||
            key == LogicalKeyboardKey.numpadEnter) &&
        event is KeyDownEvent) {
      final shift =
          _shiftHeld || HardwareKeyboard.instance.isShiftPressed;
      if (!shift) {
        final over = _chat.text.length > maxChatText;
        if (!_blocked && _chat.text.trim().isNotEmpty && !over) {
          _send(trade);
        }
        return KeyEventResult.handled;
      }
    }
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
        final shareDetails =
            side == TradeSide.seller &&
            trade.phase == TradePhase.waitingFiat &&
            (details == null || _editingDetails);
        final canEditDetails =
            side == TradeSide.seller &&
            trade.phase == TradePhase.waitingFiat &&
            details != null &&
            !_editingDetails &&
            peer != null;
        final outcome = tradeOutcome(trade.phase);
        final compose =
            peer != null &&
            !trade.phase.terminal &&
            trade.phase != TradePhase.refunding;
        final lines = _lines(trade.id);
        final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
        final draftingDetails =
            shareDetails &&
            peer != null &&
            bottomInset > 0 &&
            _detailsFocus.hasFocus;
        _pin(
          lines.length + (outcome == null ? 0 : 1),
          bottomInset: bottomInset,
        );
        final reading = _reading(
          trade: trade,
          side: side,
          actions: actions,
          details: details,
          proof: proof,
          peer: peer,
          shareDetails: shareDetails,
          waitingFiat: waitingFiat,
        );
        final controls = draftingDetails
            ? null
            : _controls(
                trade: trade,
                actions: actions,
                details: details,
                proof: proof,
                peer: peer,
                shareDetails: shareDetails,
                canEditDetails: canEditDetails,
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
                      final keyboardOpen = bottomInset > 0;
                      final summaryMax = height * 0.28 < 140
                          ? height * 0.28
                          : 140.0;
                      final infoMax = keyboardOpen
                          ? (height * 0.22 < 120 ? height * 0.22 : 120.0)
                          : (height * 0.36 < 240 ? height * 0.36 : 240.0);
                      final dockCap = keyboardOpen
                          ? (height * 0.22 < 120 ? height * 0.22 : 120.0)
                          : (height * 0.28 < 168 ? height * 0.28 : 168.0);
                      if (draftingDetails) {
                        return Padding(
                          padding: const EdgeInsets.fromLTRB(
                            TwineTokens.md,
                            TwineTokens.sm,
                            TwineTokens.md,
                            TwineTokens.sm,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Expanded(child: _detailsField(expand: true)),
                              const SizedBox(height: TwineTokens.sm),
                              _primary(
                                'Send',
                                _Work.share,
                                () => _share(trade),
                              ),
                              if (_editingDetails)
                                TextButton(
                                  onPressed: _blocked
                                      ? null
                                      : () => setState(
                                          () => _editingDetails = false,
                                        ),
                                  child: const Text('Keep current details'),
                                ),
                            ],
                          ),
                        );
                      }
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
                              ),
                            ),
                          ),
                          if (reading != null && infoMax > 0)
                            _ReadPanel(maxHeight: infoMax, child: reading),
                          Expanded(
                            child: _conversation(
                              theme,
                              lines,
                              peer,
                              outcome: outcome,
                            ),
                          ),
                          if (controls != null && dockCap > 0)
                            ConstrainedBox(
                              constraints: BoxConstraints(maxHeight: dockCap),
                              child: _ActionDock(child: controls),
                            ),
                        ],
                      );
                    },
                  ),
                ),
                if (compose && !draftingDetails)
                  _composer(
                    trade,
                    side: side,
                    separated: controls == null,
                  ),
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
                      if (showPayment) ...[
                        Text(
                          _paymentLine(side, trade),
                          style: TwineTokens.price(theme),
                        ),
                        if (ckb != null) ...[
                          const SizedBox(height: TwineTokens.xxs),
                          Text(ckb, style: muted),
                        ],
                      ] else if (ckb != null)
                        Text(ckb, style: TwineTokens.title(theme))
                      else if (orderCurrency != null && ckb == null)
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
            _DeadlineTicker(trade: trade, side: side, style: muted),
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
            onCopy: _copy,
          ),
        );
      },
    );
  }

  Widget? _reading({
    required TwineTrade trade,
    required TradeSide? side,
    required TradeActions actions,
    required TradeNote? details,
    required TradeNote? proof,
    required String? peer,
    required bool shareDetails,
    required bool waitingFiat,
  }) {
    final children = <Widget>[];
    final theme = Theme.of(context);
    void add(Widget child, {double gap = TwineTokens.sm}) {
      if (children.isNotEmpty) children.add(SizedBox(height: gap));
      children.add(child);
    }

    if (shareDetails && peer != null) {
      add(
        const Text(
          'The CKB is locked. Send the payment details the buyer should use.',
        ),
      );
    } else if (shareDetails) {
      add(const Text('Waiting to learn who the buyer is.'));
    } else if (waitingFiat && details == null) {
      add(
        const Text(
          'The CKB is locked. Waiting for the seller to share the payment details.',
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
        _InvoiceCard(
          invoice: trade.holdInvoice!,
          onCopy: () => _copy(trade.holdInvoice!),
          onShowQr: () => _openInvoice(trade.holdInvoice!),
        ),
      );
    } else if (side == TradeSide.buyer &&
        trade.phase == TradePhase.waitingHold) {
      add(
        const Text(
          'When the seller locks the CKB, they send the payment details.',
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
    if (children.isEmpty) return null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    );
  }

  Widget? _controls({
    required TwineTrade trade,
    required TradeActions actions,
    required TradeNote? details,
    required TradeNote? proof,
    required String? peer,
    required bool shareDetails,
    required bool canEditDetails,
    required bool waitingFiat,
  }) {
    final children = <Widget>[];
    void add(Widget child, {double gap = TwineTokens.sm}) {
      if (children.isNotEmpty) children.add(SizedBox(height: gap));
      children.add(child);
    }

    if (shareDetails && peer != null) {
      add(_detailsField(expand: false));
      add(_primary('Send', _Work.share, () => _share(trade)));
      if (_editingDetails) {
        add(
          TextButton(
            onPressed: _blocked
                ? null
                : () => setState(() => _editingDetails = false),
            child: const Text('Keep current details'),
          ),
          gap: TwineTokens.xxs,
        );
      }
    } else if (canEditDetails && details != null) {
      add(
        TextButton(
          onPressed: _blocked
              ? null
              : () {
                  setState(() {
                    _details.text = details.detailsText;
                    _editingDetails = true;
                  });
                },
          child: const Text('Update payment details'),
        ),
        gap: TwineTokens.xs,
      );
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
        _quiet('Dispute (coming soon)', _Work.dispute, null),
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

  Widget _detailsField({required bool expand}) {
    final theme = Theme.of(context);
    return TextField(
      key: _detailsFieldKey,
      controller: _details,
      focusNode: _detailsFocus,
      enabled: !_blocked,
      minLines: expand ? null : 3,
      maxLines: expand ? null : 6,
      expands: expand,
      textAlignVertical: expand ? TextAlignVertical.top : null,
      textCapitalization: TextCapitalization.sentences,
      decoration: TwineTokens.field(
        theme,
        label: 'Payment details',
        alignLabelWithHint: true,
        hint: 'How the buyer should pay',
      ),
    );
  }

  void _openInvoice(String invoice) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) {
        final theme = Theme.of(context);
        final bottom = MediaQuery.viewPaddingOf(context).bottom;
        final width = MediaQuery.sizeOf(context).width;
        final qr = width < 360 ? 200.0 : 240.0;
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
                Text('Fiber invoice', style: TwineTokens.title(theme)),
                const SizedBox(height: TwineTokens.xs),
                Text(
                  'Scan this in your Fiber wallet, or copy the invoice.',
                  style: TwineTokens.muted(theme),
                ),
                const SizedBox(height: TwineTokens.md),
                Center(
                  child: _InvoiceQr(invoice: invoice, size: qr),
                ),
                const SizedBox(height: TwineTokens.md),
                SelectableText(
                  invoice,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontFamily: 'monospace',
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: TwineTokens.md),
                FilledButton(
                  onPressed: () => _copy(invoice),
                  child: const Text('Copy invoice'),
                ),
              ],
            ),
          ),
        );
      },
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

  Widget _quiet(String label, _Work work, VoidCallback? onPressed) {
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
    final theme = Theme.of(context);
    return TextField(
      controller: _invoice,
      enabled: !_blocked,
      minLines: 1,
      maxLines: 4,
      autocorrect: false,
      enableSuggestions: false,
      decoration: TwineTokens.field(
        theme,
        label: 'Fiber invoice for the CKB',
        helper: _invoiceHelp(trade),
      ).copyWith(
        suffixIcon: IconButton(
          tooltip: 'Paste invoice',
          onPressed: _blocked ? null : _pasteInvoice,
          icon: const Icon(Icons.content_paste, size: TwineTokens.iconSm),
        ),
      ),
    );
  }

  Future<void> _pasteInvoice() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim();
    if (text == null || text.isEmpty || !mounted) return;
    _invoice.text = text;
  }

  Widget _composer(
    TwineTrade trade, {
    required TradeSide? side,
    required bool separated,
  }) {
    final blocked = _blocked;
    final over = _chat.text.length > maxChatText;
    final canSend = !blocked && _chat.text.trim().isNotEmpty && !over;
    final canAttachReceipt =
        side == TradeSide.buyer &&
        (trade.phase == TradePhase.fiatSent ||
            trade.phase == TradePhase.disputed);
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
                if (canAttachReceipt) ...[
                  IconButton(
                    tooltip: 'Attach receipt',
                    onPressed: blocked ? null : () => _attachReceipt(trade),
                    icon: const Icon(Icons.receipt_long_outlined),
                  ),
                  const SizedBox(width: TwineTokens.xxs),
                ],
                Expanded(
                  child: Focus(
                    onKeyEvent: (node, event) =>
                        _onComposerKey(node, event, trade),
                    child: TextField(
                      controller: _chat,
                      enabled: !blocked,
                      minLines: 1,
                      maxLines: 4,
                      textCapitalization: TextCapitalization.sentences,
                      textInputAction: TextInputAction.send,
                      onSubmitted: canSend ? (_) => _send(trade) : null,
                      onChanged: (value) {
                        if (_shiftHeld || !value.endsWith('\n')) return;
                        final text = value.substring(0, value.length - 1);
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

  void _openDetails({
    required TwineTrade trade,
    required TradeSide? side,
    String? orderCurrency,
  }) {
    final timing = _timing(trade, side, DateTime.now().toUtc());
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
                Text('Steps', style: TwineTokens.section(theme)),
                const SizedBox(height: TwineTokens.xs),
                _PhaseSteps(phase: trade.phase),
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
                  onCopy: _copy,
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

  void _pin(int count, {double bottomInset = 0}) {
    final initial = _pinned == -1;
    final countChanged = count != _pinned;
    final keyboardOpened = bottomInset > _lastBottomInset;
    _pinned = count;
    _lastBottomInset = bottomInset;
    if (!countChanged && !keyboardOpened) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_thread.hasClients) return;
      final position = _thread.position;
      if (!position.hasContentDimensions) return;
      if (position.maxScrollExtent <= 0) return;
      if (!initial && position.extentAfter > 160 && !keyboardOpened) return;
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
    final clean = value.replaceAll('\u200b', '');
    await Clipboard.setData(ClipboardData(text: clean));
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

  Future<void> _share(TwineTrade trade) async {
    await _run(_Work.share, () {
      return widget.market.shareDetails(trade.id, details: _details.text);
    });
    if (!mounted) return;
    if (_error == null) {
      setState(() {
        _details.clear();
        _editingDetails = false;
      });
    }
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

  Future<void> _attachReceipt(TwineTrade trade) async {
    if (_busy != null || widget.market.sending) return;
    final paid = await showModalBottomSheet<_PaidInput>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => _PaidSheet(
        amount: '${trade.fiatAmount ?? ''} ${trade.fiatCurrency ?? ''}'.trim(),
        needsReceipt: true,
        submitLabel: 'Send receipt',
      ),
    );
    final image = paid?.image;
    if (image == null || !mounted) return;
    await _run(
      _Work.paid,
      () => widget.market.sendReceipt(trade.id, image),
    );
  }

  Future<void> _submitInvoice(TwineTrade trade) async {
    await _run(
      _Work.invoice,
      () => widget.market.submitPayoutInvoice(trade.id, _invoice.text),
    );
    if (!mounted) return;
    if (_error == null) _invoice.clear();
  }

  Future<void> _send(TwineTrade trade) async {
    if (_busy != null || widget.market.sending) return;
    final text = _chat.text;
    await _run(_Work.chat, () => widget.market.sendChat(trade.id, text));
    if (!mounted) return;
    if (_error == null) _chat.clear();
  }

  Future<void> _fiat(TwineTrade trade) async {
    await _run(
      _Work.invoice,
      () => widget.market.fiatSent(trade.id, _invoice.text),
    );
    if (!mounted) return;
    if (_error == null) _invoice.clear();
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

class _PhaseSteps extends StatelessWidget {
  const _PhaseSteps({required this.phase});

  final TradePhase phase;

  static const _steps = <String>[
    'Payout invoice',
    'Lock CKB',
    'Fiat payment',
    'Release CKB',
  ];

  int get _activeIndex {
    switch (phase) {
      case TradePhase.waitingInvoice:
        return 0;
      case TradePhase.waitingHold:
        return 1;
      case TradePhase.waitingFiat:
        return 2;
      case TradePhase.fiatSent:
      case TradePhase.releasing:
      case TradePhase.awaitingInvoice:
      case TradePhase.disputed:
        return 3;
      case TradePhase.settled:
        return 4;
      case TradePhase.refunding:
      case TradePhase.canceled:
      case TradePhase.expired:
        return -1;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final active = _activeIndex;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < _steps.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: TwineTokens.xxs),
            child: Row(
              children: [
                Icon(
                  active > i
                      ? Icons.check_circle
                      : (active == i
                            ? Icons.radio_button_checked
                            : Icons.radio_button_unchecked),
                  size: TwineTokens.iconSm,
                  color: active >= i ? scheme.primary : scheme.outline,
                ),
                const SizedBox(width: TwineTokens.xs),
                Text(
                  _steps[i],
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: active == i ? FontWeight.w600 : FontWeight.w400,
                    color: active >= i
                        ? scheme.onSurface
                        : scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _Parties extends StatelessWidget {
  const _Parties({
    required this.me,
    required this.encode,
    required this.onCopy,
    this.seller,
    this.buyer,
  });

  final String me;
  final String? seller;
  final String? buyer;
  final String Function(String hex) encode;
  final void Function(String value) onCopy;

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
                onPressed: () => onCopy(npub),
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

class _DetailsCard extends StatelessWidget {
  const _DetailsCard({
    required this.details,
    required this.title,
    required this.onCopy,
    this.kicker,
    this.when,
  });

  final TradeNote details;
  final String title;
  final void Function(String value) onCopy;
  final String? kicker;
  final String? when;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fields = _payFields(details);
    final text = details.detailsText;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (kicker != null) ...[
          Text(
            kicker!,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: TwineTokens.xxs),
        ],
        DecoratedBox(
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: BorderRadius.circular(TwineTokens.radiusSm),
            border: Border.all(color: theme.colorScheme.outlineVariant),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              TwineTokens.sm,
              TwineTokens.sm,
              TwineTokens.xxs,
              TwineTokens.xs,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Copy payment details',
                      visualDensity: VisualDensity.compact,
                      onPressed: text.isEmpty ? null : () => onCopy(text),
                      icon: const Icon(Icons.copy, size: TwineTokens.iconSm),
                    ),
                  ],
                ),
                if (fields.isEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: TwineTokens.xs),
                    child: Text('No details.', style: TwineTokens.muted(theme)),
                  )
                else
                  for (var i = 0; i < fields.length; i++) ...[
                    if (i > 0)
                      Divider(
                        height: 1,
                        color: theme.colorScheme.outlineVariant,
                      ),
                    _ValueRow(
                      value: fields[i].value,
                      onCopy: () => onCopy(fields[i].value),
                    ),
                  ],
                if (when != null)
                  Align(
                    alignment: Alignment.centerRight,
                    child: Padding(
                      padding: const EdgeInsets.only(
                        right: TwineTokens.xs,
                        bottom: TwineTokens.xxs,
                      ),
                      child: Text(
                        when!,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
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

final Map<String, Uint8List> _receiptByteCache = <String, Uint8List>{};

Uint8List? _receiptBytes(String? image) {
  if (image == null) return null;
  final cached = _receiptByteCache[image];
  if (cached != null) return cached;
  try {
    final decoded = base64Decode(image);
    if (_receiptByteCache.length >= 32) {
      _receiptByteCache.remove(_receiptByteCache.keys.first);
    }
    _receiptByteCache[image] = decoded;
    return decoded;
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
    required this.onCopy,
  });

  final TradeNote line;
  final bool mine;
  final bool showName;
  final void Function(Uint8List bytes) onOpenReceipt;
  final void Function(String value) onCopy;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    switch (line.kind) {
      case TradeNoteKind.status:
        return _event(theme, line.text ?? '');
      case TradeNoteKind.paymentDetails:
        return _DetailsCard(
          details: line,
          title: 'Payment details',
          kicker: showName ? (mine ? 'You' : 'Them') : null,
          when: _when(line.at),
          onCopy: onCopy,
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
    final bubble = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onLongPress: body.isEmpty ? null : () => onCopy(body),
      child: Column(
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
            _softBreak(body),
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colors.foreground,
              height: 1.4,
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
      ),
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

const _shortMonths = <String>[
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

String _when(DateTime at) {
  final local = at.toLocal();
  final now = DateTime.now().toLocal();
  final hour = local.hour.toString().padLeft(2, '0');
  final minute = local.minute.toString().padLeft(2, '0');
  final sameDay =
      local.year == now.year &&
      local.month == now.month &&
      local.day == now.day;
  if (sameDay) return '$hour:$minute';
  final month = _shortMonths[local.month];
  return '${local.day} $month, $hour:$minute';
}

class _PaidInput {
  const _PaidInput({this.image});

  final String? image;
}

class _PaidSheet extends StatefulWidget {
  const _PaidSheet({
    required this.amount,
    required this.needsReceipt,
    this.submitLabel = "I've paid",
  });

  final String amount;
  final bool needsReceipt;
  final String submitLabel;

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
            child: Text(widget.submitLabel),
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

class _ReadPanel extends StatelessWidget {
  const _ReadPanel({required this.maxHeight, required this.child});

  final double maxHeight;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxHeight),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: scheme.surfaceContainerLow,
          border: Border(bottom: BorderSide(color: scheme.outlineVariant)),
        ),
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
      ),
    );
  }
}

class _InvoiceCard extends StatelessWidget {
  const _InvoiceCard({
    required this.invoice,
    required this.onCopy,
    required this.onShowQr,
  });

  final String invoice;
  final VoidCallback onCopy;
  final VoidCallback onShowQr;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(TwineTokens.radiusSm),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          TwineTokens.sm,
          TwineTokens.sm,
          TwineTokens.sm,
          TwineTokens.xs,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(
                  Icons.qr_code_2,
                  size: TwineTokens.iconMd,
                  color: scheme.onSurface,
                ),
                const SizedBox(width: TwineTokens.xs),
                Expanded(
                  child: Text(
                    'Fiber invoice',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: TwineTokens.xs),
            const Text(
              'A buyer took this. Pay this invoice in your Fiber wallet. You cannot cancel after it locks.',
            ),
            const SizedBox(height: TwineTokens.sm),
            _ValueRow(
              value: _invoicePreview(invoice),
              mono: true,
              onCopy: onCopy,
              copyTooltip: 'Copy invoice',
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: onShowQr,
                icon: const Icon(Icons.qr_code_2, size: TwineTokens.iconSm),
                label: const Text('Show QR'),
              ),
            ),
            Text(
              'Waiting for the operator node to report the lock.',
              style: TwineTokens.muted(theme),
            ),
            const SizedBox(height: TwineTokens.xs),
          ],
        ),
      ),
    );
  }
}

class _InvoiceQr extends StatelessWidget {
  const _InvoiceQr({required this.invoice, required this.size});

  final String invoice;
  final double size;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(TwineTokens.radiusSm),
      ),
      child: Padding(
        padding: const EdgeInsets.all(TwineTokens.sm),
        child: QrImageView(
          data: invoice,
          size: size,
          backgroundColor: Colors.white,
        ),
      ),
    );
  }
}

class _ValueRow extends StatelessWidget {
  const _ValueRow({
    required this.value,
    required this.onCopy,
    this.mono = false,
    this.copyTooltip = 'Copy',
  });

  final String value;
  final VoidCallback onCopy;
  final bool mono;
  final String copyTooltip;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final valueStyle = theme.textTheme.bodyLarge?.copyWith(
      fontFamily: mono ? 'monospace' : null,
      fontWeight: FontWeight.w500,
      height: 1.35,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: TwineTokens.xxs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(child: SelectableText(value, style: valueStyle)),
          IconButton(
            tooltip: copyTooltip,
            visualDensity: VisualDensity.compact,
            onPressed: onCopy,
            icon: Icon(
              Icons.copy,
              size: TwineTokens.iconSm,
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _PayField {
  const _PayField({required this.value});

  final String value;
}

List<_PayField> _payFields(TradeNote details) {
  final written = details.detailsText;
  if (written.isEmpty) return const [];
  return [
    for (final line in written.split('\n'))
      if (line.trim().isNotEmpty) _PayField(value: line.trim()),
  ];
}

String _invoicePreview(String invoice) {
  final value = invoice.trim();
  if (value.length <= 36) return value;
  return '${value.substring(0, 14)}…${value.substring(value.length - 10)}';
}

/// Lets a long invoice wrap inside a chat bubble.
String _softBreak(String value) {
  final buffer = StringBuffer();
  var run = 0;
  for (final unit in value.runes) {
    final char = String.fromCharCode(unit);
    buffer.write(char);
    if (char == ' ' || char == '\n' || char == '\t') {
      run = 0;
      continue;
    }
    run += 1;
    if (run >= 18) {
      buffer.write('\u200b');
      run = 0;
    }
  }
  return buffer.toString();
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

List<String> _timing(TwineTrade trade, TradeSide? side, DateTime now) {
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

class _DeadlineTicker extends StatefulWidget {
  const _DeadlineTicker({
    required this.trade,
    required this.side,
    required this.style,
  });

  final TwineTrade trade;
  final TradeSide? side;
  final TextStyle? style;

  @override
  State<_DeadlineTicker> createState() => _DeadlineTickerState();
}

class _DeadlineTickerState extends State<_DeadlineTicker> {
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _syncTimer();
  }

  @override
  void didUpdateWidget(covariant _DeadlineTicker oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncTimer();
  }

  void _syncTimer() {
    if (widget.trade.phase.terminal) {
      _tick?.cancel();
      _tick = null;
      return;
    }
    _tick ??= Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final timing = _timing(widget.trade, widget.side, DateTime.now().toUtc());
    if (timing.isEmpty) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: TwineTokens.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.schedule,
            size: TwineTokens.iconSm,
            color: scheme.onSurfaceVariant,
          ),
          const SizedBox(width: TwineTokens.xs),
          Expanded(child: Text(timing.first, style: widget.style)),
        ],
      ),
    );
  }
}
