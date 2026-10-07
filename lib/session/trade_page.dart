import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../market/amount.dart';
import '../market/chat.dart';
import '../market/phase.dart';
import '../market/role.dart';
import '../market/steps.dart';
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
  final _accountName = TextEditingController();
  final _accountNumber = TextEditingController();
  final _accountNote = TextEditingController();
  final _chat = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _invoice.dispose();
    _accountName.dispose();
    _accountNumber.dispose();
    _accountNote.dispose();
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
        );
        final details = widget.market.book.paymentDetails(trade.id);
        final proof = widget.market.book.paymentProof(trade.id);
        final peer = counterparty(trade, widget.market.accountPubkey);
        final theme = Theme.of(context);
        final notice = trade.notice ?? _error;
        final waitingFiat =
            side == TradeSide.buyer && trade.phase == TradePhase.waitingFiat;
        final shareAccount =
            side == TradeSide.seller &&
            trade.phase == TradePhase.waitingFiat &&
            details == null;
        return Scaffold(
          appBar: AppBar(title: Text(tradeTitle(trade.phase, side))),
          body: SafeArea(
            child: Column(
              children: [
                Expanded(
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
                      if (trade.fiatAmount != null &&
                          trade.phase != TradePhase.waitingHold) ...[
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
                        const Text(
                          'The CKB is locked. Share the account the buyer should pay.',
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Account for ${trade.paymentLabel ?? 'this method'}',
                          style: theme.textTheme.titleSmall,
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _accountName,
                          enabled: !widget.market.sending,
                          decoration: const InputDecoration(
                            labelText: 'Account name',
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _accountNumber,
                          enabled: !widget.market.sending,
                          decoration: const InputDecoration(
                            labelText: 'Account number',
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _accountNote,
                          enabled: !widget.market.sending,
                          decoration: const InputDecoration(labelText: 'Note'),
                        ),
                        const SizedBox(height: 12),
                        FilledButton(
                          onPressed: widget.market.sending
                              ? null
                              : () => _share(trade),
                          child: const Text('Share account'),
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
                      ],
                      if (actions.payHold) ...[
                        const SizedBox(height: 16),
                        const Text(
                          'A buyer took this. Pay the invoice below from your Fiber wallet. That locks the CKB until you release it.',
                        ),
                        const SizedBox(height: 8),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(child: SelectableText(trade.holdInvoice!)),
                            IconButton(
                              tooltip: 'Copy invoice',
                              onPressed: () => Clipboard.setData(
                                ClipboardData(text: trade.holdInvoice!),
                              ),
                              icon: const Icon(Icons.copy),
                            ),
                          ],
                        ),
                      ] else if (side == TradeSide.buyer &&
                          trade.phase == TradePhase.waitingHold) ...[
                        const SizedBox(height: 16),
                        const Text(
                          'The seller is locking the CKB. You pay them after that. You can cancel until the lock is in.',
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
                        const Text('Sending the CKB to the buyer.'),
                      ],
                      if (waitingFiat && details != null) ...[
                        const SizedBox(height: 16),
                        FilledButton(
                          onPressed: widget.market.sending
                              ? null
                              : () => _paid(trade, proof != null),
                          child: Text(
                            proof == null
                                ? "I've paid"
                                : 'Submit payout invoice',
                          ),
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
                          decoration: const InputDecoration(
                            labelText: 'Fiber invoice for the CKB',
                            helperText:
                                'Create this in your Fiber wallet. The CKB is sent to it.',
                          ),
                        ),
                        const SizedBox(height: 12),
                        FilledButton(
                          onPressed: widget.market.sending
                              ? null
                              : () => _fiat(trade),
                          child: const Text('Submit payout invoice'),
                        ),
                      ],
                      if (actions.release) ...[
                        const SizedBox(height: 12),
                        FilledButton(
                          onPressed: widget.market.sending
                              ? null
                              : () => _release(trade),
                          child: const Text('Release the CKB'),
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
                      if (peer != null) ...[
                        const SizedBox(height: 24),
                        Text('Chat', style: theme.textTheme.titleSmall),
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
                if (peer != null && !trade.phase.terminal)
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
                          icon: const Icon(Icons.send),
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
      accountName: _accountName.text,
      accountNumber: _accountNumber.text,
      note: _accountNote.text,
    );
    if (!mounted) return;
    setState(() => _error = error);
  }

  Future<void> _paid(TwineTrade trade, bool hasProof) async {
    final details = widget.market.book.paymentDetails(trade.id);
    if (details == null) return;
    final paid = await showModalBottomSheet<_PaidInput>(
      context: context,
      isScrollControlled: true,
      builder: (context) => _PaidSheet(
        amount: '${trade.fiatAmount ?? ''} ${trade.fiatCurrency ?? ''}',
        accountName: details.accountName ?? '',
        accountNumber: details.accountNumber ?? '',
        needsReceipt: !hasProof,
      ),
    );
    if (paid == null || !mounted) return;
    final error = await widget.market.markPaid(
      trade.id,
      invoice: paid.invoice,
      bankReference: paid.reference,
      image: paid.image,
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
    final confirmed = await _confirm(
      context,
      'Release the CKB?',
      'Do this after the money is in your account. The receipt is the buyer\'s claim.',
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
      'The CKB stays locked until someone decides. They can read this chat.',
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

class _AccountCard extends StatelessWidget {
  const _AccountCard({required this.details});

  final TradeNote details;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final number = details.accountNumber ?? '';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Pay this account', style: theme.textTheme.titleSmall),
        const SizedBox(height: 8),
        Text(details.accountName ?? ''),
        Row(
          children: [
            Expanded(child: SelectableText(number)),
            IconButton(
              onPressed: number.isEmpty
                  ? null
                  : () => Clipboard.setData(ClipboardData(text: number)),
              icon: const Icon(Icons.copy),
            ),
          ],
        ),
        if (details.note != null) Text(details.note!),
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
  const _PaidInput({
    required this.invoice,
    required this.reference,
    this.image,
  });

  final String invoice;
  final String reference;
  final String? image;
}

class _PaidSheet extends StatefulWidget {
  const _PaidSheet({
    required this.amount,
    required this.accountName,
    required this.accountNumber,
    required this.needsReceipt,
  });

  final String amount;
  final String accountName;
  final String accountNumber;
  final bool needsReceipt;

  @override
  State<_PaidSheet> createState() => _PaidSheetState();
}

class _PaidSheetState extends State<_PaidSheet> {
  final _invoice = TextEditingController();
  final _reference = TextEditingController();
  String? _image;
  String? _error;

  @override
  void dispose() {
    _invoice.dispose();
    _reference.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(24, 24, 24, 24 + bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Pay ${widget.amount} to ${widget.accountName}'),
          const SizedBox(height: 4),
          Text(widget.accountNumber),
          const SizedBox(height: 16),
          if (widget.needsReceipt) ...[
            TextField(
              controller: _reference,
              decoration: const InputDecoration(labelText: 'Bank reference'),
            ),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: _pick,
              child: Text(
                _image == null ? 'Attach receipt' : 'Receipt attached',
              ),
            ),
            const SizedBox(height: 12),
          ],
          TextField(
            controller: _invoice,
            minLines: 1,
            maxLines: 4,
            autocorrect: false,
            enableSuggestions: false,
            decoration: const InputDecoration(
              labelText: 'Fiber invoice for the CKB',
              helperText:
                  'Create this in your Fiber wallet. The CKB is sent to it.',
            ),
          ),
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
          FilledButton(onPressed: _submit, child: const Text("I've paid")),
        ],
      ),
    );
  }

  Future<void> _pick() async {
    final file = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 720,
      imageQuality: 35,
    );
    if (file == null || !mounted) return;
    final bytes = await file.readAsBytes();
    if (!mounted) return;
    if (bytes.length > maxReceiptBytes) {
      setState(() => _error = 'Crop the receipt and try a smaller picture.');
      return;
    }
    setState(() {
      _image = base64Encode(bytes);
      _error = null;
    });
  }

  void _submit() {
    final invoice = _invoice.text.trim();
    if (invoice.isEmpty) {
      setState(() => _error = 'Paste the Fiber invoice for the CKB.');
      return;
    }
    if (widget.needsReceipt) {
      if (_reference.text.trim().isEmpty) {
        setState(() => _error = 'Enter the bank reference.');
        return;
      }
      if (_image == null) {
        setState(() => _error = 'Attach the receipt.');
        return;
      }
    }
    Navigator.pop(
      context,
      _PaidInput(
        invoice: invoice,
        reference: _reference.text.trim(),
        image: _image,
      ),
    );
  }
}

String _paymentLine(TradeSide? side, TwineTrade trade) {
  final amount = '${trade.fiatAmount ?? ''} ${trade.fiatCurrency ?? ''}'.trim();
  final method = trade.paymentLabel ?? 'the named method';
  switch (side) {
    case TradeSide.buyer:
      return 'Pay $amount with $method.';
    case TradeSide.seller:
      return 'The buyer pays you $amount with $method.';
    case null:
      return 'This trade is for $amount with $method.';
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
