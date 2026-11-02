import 'package:flutter/material.dart';

import '../market/amount.dart';
import '../market/role.dart';
import '../nostr/order.dart';
import '../nostr/request.dart';
import 'market.dart';

class TakePage extends StatefulWidget {
  const TakePage({super.key, required this.market, required this.orderId});

  final TwineMarket market;
  final String orderId;

  @override
  State<TakePage> createState() => _TakePageState();
}

class _TakePageState extends State<TakePage> {
  late final TextEditingController _amount;
  late final TextEditingController _invoice;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _amount = TextEditingController();
    _invoice = TextEditingController();
    _amount.addListener(() {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _amount.dispose();
    _invoice.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.market,
      builder: (context, _) {
        final order = widget.market.book.order(widget.orderId);
        if (order == null) {
          return Scaffold(
            appBar: AppBar(title: const Text('Take')),
            body: const SafeArea(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text('This post is no longer on the book.'),
              ),
            ),
          );
        }
        final theme = Theme.of(context);
        final role = tradeSide(order, widget.market.accountPubkey);
        final title = role == TradeSide.seller ? 'Sell CKB' : 'Buy CKB';
        final estimate = aboutCkb(_amount.text, order.pricePerCkb);
        return Scaffold(
          appBar: AppBar(title: Text(title)),
          body: SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        role == TradeSide.seller
                            ? 'You lock CKB in your Fiber wallet.'
                            : 'You pay by mobile transfer after the seller locks.',
                        style: theme.textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      Text('${order.availableCkb} CKB'),
                      const SizedBox(height: 8),
                      Text(
                        '${order.min}–${order.max} ${order.fiatCurrency} at ${order.pricePerCkb} ${order.fiatCurrency} per CKB',
                      ),
                      if (estimate != null) ...[
                        const SizedBox(height: 8),
                        Text('About $estimate CKB'),
                      ],
                      const SizedBox(height: 16),
                      TextField(
                        controller: _amount,
                        enabled: !_busy,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        autocorrect: false,
                        enableSuggestions: false,
                        decoration: InputDecoration(
                          labelText: 'Fiat amount',
                          suffixText: order.fiatCurrency,
                          border: const OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      if (role == TradeSide.buyer) ...[
                        TextField(
                          controller: _invoice,
                          enabled: !_busy,
                          minLines: 1,
                          maxLines: 4,
                          autocorrect: false,
                          enableSuggestions: false,
                          decoration: const InputDecoration(
                            labelText: 'Fiber invoice for the CKB',
                            helperText:
                                'Paste the invoice from the wallet that should receive the CKB. The hold uses this invoice\'s payment hash.',
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 12),
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
                      const SizedBox(height: 12),
                      FilledButton(
                        onPressed: _busy ? null : () => _submit(order, role),
                        child: _busy
                            ? const SizedBox(
                                height: 18,
                                width: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Text('Take'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _submit(TwineOrder order, TradeSide role) async {
    final draft = TakeDraft(
      orderId: order.orderId,
      fiatAmount: _amount.text,
      invoice: role == TradeSide.buyer ? _invoice.text : null,
      requireInvoice: role == TradeSide.buyer,
    );
    final invalid = draft.validate();
    if (invalid != null) {
      setState(() => _error = invalid);
      return;
    }
    final estimate = aboutCkb(_amount.text, order.pricePerCkb);
    final roleLine = role == TradeSide.seller
        ? 'You lock CKB in your Fiber wallet.'
        : 'You pay by mobile transfer after the seller locks.';
    final confirmBody = estimate == null
        ? roleLine
        : '$roleLine About $estimate CKB at this price.';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(role == TradeSide.seller ? 'Sell CKB?' : 'Buy CKB?'),
          content: Text(confirmBody),
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
    if (confirmed != true || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final error = await widget.market.take(draft);
    if (!mounted) return;
    if (error == null) {
      Navigator.of(context).pop();
      return;
    }
    setState(() {
      _busy = false;
      _error = error;
    });
  }
}
