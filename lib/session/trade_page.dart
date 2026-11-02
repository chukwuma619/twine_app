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
  Timer? _tick;
  String? _error;
  String? _banner;
  bool _lifting = false;
  bool _copiedHold = false;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    _invoice.dispose();
    _details.dispose();
    _chat.dispose();
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
            (trade.phase == TradePhase.waitingHold ||
                trade.phase == TradePhase.waitingFiat) &&
            details == null;
        final outcome = tradeOutcome(trade.phase);
        final compose =
            peer != null &&
            !trade.phase.terminal &&
            trade.phase != TradePhase.refunding;
        return Scaffold(
          appBar: AppBar(title: Text(tradeTitle(trade.phase, side))),
          body: SafeArea(
            child: Column(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (outcome != null) ...[
                          Text(outcome, style: theme.textTheme.titleSmall),
                          const SizedBox(height: 16),
                        ],
                        if (order != null) ...[
                          Text(
                            order.fiatCurrency,
                            style: theme.textTheme.titleMedium,
                          ),
                          const SizedBox(height: 8),
                        ],
                        if (trade.amountShannons != null)
                          Text('${shannonsToCkb(trade.amountShannons!)} CKB'),
                        const SizedBox(height: 12),
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
                          const SizedBox(height: 16),
                          Text(_paymentLine(side, trade)),
                          if (side == TradeSide.buyer) ...[
                            const SizedBox(height: 8),
                            const Text('Put the reference on the payment.'),
                          ],
                        ],
                        if (details != null) ...[
                          const SizedBox(height: 16),
                          _AccountCard(details: details),
                        ] else if (shareAccount && peer != null) ...[
                          const SizedBox(height: 16),
                          Text(
                            trade.phase == TradePhase.waitingHold
                                ? 'Send the payment details before you lock, so the buyer can pay as soon as the CKB is locked.'
                                : 'The CKB is locked. Send the payment details the buyer should use.',
                          ),
                          const SizedBox(height: 16),
                          TextField(
                            controller: _details,
                            enabled: !widget.market.sending,
                            minLines: 4,
                            maxLines: 8,
                            decoration: const InputDecoration(
                              labelText: 'Payment details',
                              alignLabelWithHint: true,
                              hintText: 'Bank, account name, account number',
                            ),
                          ),
                          const SizedBox(height: 12),
                          FilledButton(
                            onPressed: widget.market.sending
                                ? null
                                : () => _share(trade),
                            child: _actionChild('Send'),
                          ),
                        ] else if (shareAccount) ...[
                          const SizedBox(height: 16),
                          const Text('Waiting to learn who the buyer is.'),
                        ] else if (waitingFiat) ...[
                          const SizedBox(height: 16),
                          const Text(
                            'The CKB is locked. Waiting for the seller to share the account you should pay.',
                          ),
                        ],
                        if (proof != null) ...[
                          const SizedBox(height: 16),
                          _ReceiptCard(proof: proof),
                        ],
                        if (trade.payoutFailure != null) ...[
                          const SizedBox(height: 16),
                          Text(trade.payoutFailure!),
                          if (side == TradeSide.buyer) ...[
                            const SizedBox(height: 8),
                            const Text(
                              'Paste another invoice for the same payment.',
                            ),
                          ],
                        ],
                        if (actions.payHold) ...[
                          const SizedBox(height: 16),
                          const Text(
                            'A buyer took this. Pay this invoice in your Fiber wallet. You cannot cancel after it locks.',
                          ),
                          const SizedBox(height: 8),
                          Center(
                            child: QrImageView(
                              data: trade.holdInvoice!,
                              size: 200,
                              backgroundColor: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: SelectableText(trade.holdInvoice!),
                              ),
                              IconButton(
                                tooltip: 'Copy invoice',
                                onPressed: () async {
                                  await Clipboard.setData(
                                    ClipboardData(text: trade.holdInvoice!),
                                  );
                                  if (!mounted) return;
                                  setState(() => _copiedHold = true);
                                },
                                icon: const Icon(Icons.copy),
                              ),
                            ],
                          ),
                          if (_copiedHold) ...[
                            const SizedBox(height: 8),
                            const Text(
                              'Waiting for the operator node to report the lock.',
                            ),
                          ],
                        ] else if (side == TradeSide.buyer &&
                            trade.phase == TradePhase.waitingHold) ...[
                          const SizedBox(height: 16),
                          const Text(
                            'Once the seller locks, pay any time before the hold’s release deadline.',
                          ),
                        ] else if (side == null &&
                            trade.phase == TradePhase.waitingHold) ...[
                          const SizedBox(height: 16),
                          const Text('Waiting to learn who locks the CKB.'),
                        ],
                        if (trade.phase == TradePhase.fiatSent &&
                            side == TradeSide.seller) ...[
                          const SizedBox(height: 16),
                          const Text(
                            'The buyer says they paid. Release the CKB after the money is in your account.',
                          ),
                        ] else if (trade.phase == TradePhase.fiatSent &&
                            side == TradeSide.buyer) ...[
                          const SizedBox(height: 16),
                          const Text(
                            'Waiting for the seller to release the CKB.',
                          ),
                        ],
                        if (trade.phase == TradePhase.releasing) ...[
                          const SizedBox(height: 16),
                          const Text('Sending the CKB to the invoice on file.'),
                        ],
                        if (trade.phase == TradePhase.disputed) ...[
                          const SizedBox(height: 16),
                          Text(_disputeLine(trade)),
                        ],
                        if (actions.submitInvoice) ...[
                          const SizedBox(height: 16),
                          TextField(
                            controller: _invoice,
                            enabled: !widget.market.sending,
                            minLines: 1,
                            maxLines: 4,
                            autocorrect: false,
                            enableSuggestions: false,
                            decoration: InputDecoration(
                              labelText: 'Fiber invoice for the CKB',
                              helperText: _invoiceHelp(trade),
                            ),
                          ),
                          const SizedBox(height: 12),
                          FilledButton(
                            onPressed: widget.market.sending
                                ? null
                                : () => _submitInvoice(trade),
                            child: _actionChild('Submit payout invoice'),
                          ),
                        ],
                        if (waitingFiat && details != null) ...[
                          const SizedBox(height: 16),
                          FilledButton(
                            onPressed: widget.market.sending
                                ? null
                                : () => _paid(trade, proof != null),
                            child: _actionChild("I've paid"),
                          ),
                        ] else if (actions.sendFiat &&
                            trade.phase != TradePhase.waitingFiat) ...[
                          const SizedBox(height: 16),
                          TextField(
                            controller: _invoice,
                            enabled: !widget.market.sending,
                            minLines: 1,
                            maxLines: 4,
                            autocorrect: false,
                            enableSuggestions: false,
                            decoration: InputDecoration(
                              labelText: 'Fiber invoice for the CKB',
                              helperText: _invoiceHelp(trade),
                            ),
                          ),
                          const SizedBox(height: 12),
                          FilledButton(
                            onPressed: widget.market.sending
                                ? null
                                : () => _fiat(trade),
                            child: _actionChild('Submit payout invoice'),
                          ),
                        ],
                        if (actions.release) ...[
                          const SizedBox(height: 12),
                          FilledButton(
                            onPressed: widget.market.sending
                                ? null
                                : () => _release(trade),
                            child: _actionChild('Release the CKB'),
                          ),
                        ],
                        if (actions.dispute) ...[
                          const SizedBox(height: 12),
                          OutlinedButton(
                            onPressed: widget.market.sending
                                ? null
                                : () => _dispute(trade),
                            child: widget.market.sending
                                ? const SizedBox(
                                    height: 18,
                                    width: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Text('Dispute'),
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
                        if (peer != null) ...[
                          const SizedBox(height: 24),
                          Text('Chat', style: theme.textTheme.titleSmall),
                          const SizedBox(height: 8),
                          const Text(
                            'This thread is encrypted to the other trader. The relay can see that the two keys are talking.',
                          ),
                          const SizedBox(height: 8),
                          for (final line in _lines(trade.id)) ...[
                            _Line(
                              line: line,
                              mine:
                                  line.author?.toLowerCase() ==
                                  widget.market.accountPubkey.toLowerCase(),
                            ),
                            const SizedBox(height: 8),
                          ],
                        ],
                        if (notice != null) ...[
                          const SizedBox(height: 12),
                          DismissibleNotice(
                            message: notice,
                            onDismiss: _dismissNotice,
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                if (compose)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _chat,
                            enabled: !widget.market.sending,
                            decoration: const InputDecoration(
                              hintText: 'Message',
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton(
                          onPressed: widget.market.sending
                              ? null
                              : () => _send(trade),
                          icon: widget.market.sending
                              ? const SizedBox(
                                  height: 18,
                                  width: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.send),
                        ),
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

  Widget _actionChild(String label) {
    if (!widget.market.sending) return Text(label);
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
    return [const SizedBox(height: 12), ...lines];
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
    return [
      for (final line in widget.market.book.thread(tradeId))
        if (line.kind == TradeNoteKind.text ||
            line.kind == TradeNoteKind.status)
          line,
    ];
  }

  Future<void> _share(TwineTrade trade) async {
    final error = await widget.market.shareAccount(
      trade.id,
      details: _details.text,
    );
    if (!mounted) return;
    setState(() => _error = error);
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

  Future<void> _paid(TwineTrade trade, bool hasProof) async {
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
    final error = await widget.market.markPaid(trade.id, image: paid.image);
    if (!mounted) return;
    setState(() => _error = error);
  }

  Future<void> _submitInvoice(TwineTrade trade) async {
    final error = await widget.market.submitPayoutInvoice(
      trade.id,
      _invoice.text,
    );
    if (!mounted) return;
    setState(() => _error = error);
  }

  Future<void> _send(TwineTrade trade) async {
    final error = await widget.market.sendChat(trade.id, _chat.text);
    if (!mounted) return;
    if (error == null) _chat.clear();
    setState(() => _error = error);
  }

  Future<void> _fiat(TwineTrade trade) async {
    final error = await widget.market.fiatSent(trade.id, _invoice.text);
    if (!mounted) return;
    setState(() => _error = error);
  }

  Future<void> _release(TwineTrade trade) async {
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
    final error = await widget.market.release(trade.id);
    if (!mounted) return;
    setState(() => _error = error);
  }

  Future<void> _dispute(TwineTrade trade) async {
    final confirmed = await _confirm(
      context,
      'Open a dispute?',
      '${_disputeLine(trade)} You can still release if a payout invoice is stored.',
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
      'This ends the trade before the CKB is locked.',
    );
    if (!confirmed || !mounted) return;
    final error = await widget.market.cancelTrade(trade.id);
    if (!mounted) return;
    setState(() => _error = error);
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

class _AccountCard extends StatelessWidget {
  const _AccountCard({required this.details});

  final TradeNote details;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = details.detailsText;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Pay here', style: theme.textTheme.titleSmall),
        const SizedBox(height: 8),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: SelectableText(text)),
            IconButton(
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
  const _ReceiptCard({required this.proof});

  final TradeNote proof;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final image = proof.image;
    List<int>? bytes;
    if (image != null) {
      try {
        bytes = base64Decode(image);
      } catch (_) {
        bytes = null;
      }
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Receipt', style: theme.textTheme.titleSmall),
        const SizedBox(height: 8),
        if (proof.amount != null) Text(proof.amount!),
        if (proof.bankReference != null) SelectableText(proof.bankReference!),
        if (bytes != null) ...[
          const SizedBox(height: 8),
          Image.memory(Uint8List.fromList(bytes), height: 180),
        ],
      ],
    );
  }
}

class _Line extends StatelessWidget {
  const _Line({required this.line, required this.mine});

  final TradeNote line;
  final bool mine;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (line.kind == TradeNoteKind.status) {
      return Text(line.text ?? '', style: theme.textTheme.bodySmall);
    }
    return Text('${mine ? 'You' : 'Them'}: ${line.text ?? ''}');
  }
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
    final receipt = _receipt;
    return Padding(
      padding: EdgeInsets.fromLTRB(24, 24, 24, 24 + bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.needsReceipt
                ? 'Attach the receipt'
                : 'Mark the payment as sent',
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
              children: [
                OutlinedButton(
                  onPressed: _compressing
                      ? null
                      : () => _pick(ImageSource.gallery),
                  child: const Text('Photo library'),
                ),
                OutlinedButton(
                  onPressed: _compressing
                      ? null
                      : () => _pick(ImageSource.camera),
                  child: const Text('Camera'),
                ),
              ],
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(
              _error!,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.error,
              ),
            ),
          ],
          const SizedBox(height: 12),
          FilledButton(
            onPressed: _compressing ? null : _submit,
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
