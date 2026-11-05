import 'package:flutter/material.dart';

import '../market/amount.dart';
import '../nostr/order.dart';
import '../nostr/request.dart';
import '../ui/twine_tokens.dart';
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
        final scheme = theme.colorScheme;
        final muted = TwineTokens.muted(theme);
        final estimate = aboutCkb(_amount.text, order.pricePerCkb);
        return Scaffold(
          resizeToAvoidBottomInset: true,
          appBar: AppBar(title: const Text('Buy CKB')),
          body: SafeArea(
            child: Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(
                          TwineTokens.md,
                          TwineTokens.sm,
                          TwineTokens.md,
                          TwineTokens.lg,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              'You pay by mobile transfer after the seller locks.',
                              style: theme.textTheme.titleMedium,
                            ),
                            const SizedBox(height: TwineTokens.sm),
                            Card(
                              color: scheme.surfaceContainerLow,
                              child: Padding(
                                padding: const EdgeInsets.all(TwineTokens.md),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '${order.availableCkb} CKB',
                                      style: TwineTokens.price(theme),
                                    ),
                                    const SizedBox(height: TwineTokens.xxs),
                                    Text(
                                      '${order.min}–${order.max} ${order.fiatCurrency} at ${order.pricePerCkb} ${order.fiatCurrency} per CKB',
                                      style: muted,
                                    ),
                                    if (estimate != null) ...[
                                      const SizedBox(height: TwineTokens.xs),
                                      Text(
                                        'About $estimate CKB',
                                        style: theme.textTheme.titleSmall
                                            ?.copyWith(
                                              color: scheme.primary,
                                              fontWeight: FontWeight.w600,
                                            ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: TwineTokens.lg),
                            TextField(
                              controller: _amount,
                              enabled: !_busy,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                              autocorrect: false,
                              enableSuggestions: false,
                              decoration: TwineTokens.field(
                                theme,
                                label: 'Fiat amount',
                                suffix: order.fiatCurrency,
                              ),
                            ),
                            const SizedBox(height: TwineTokens.sm),
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
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    DecoratedBox(
                      decoration: TwineTokens.dock(scheme),
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
                            if (_error != null) ...[
                              Text(_error!, style: TwineTokens.error(theme)),
                              const SizedBox(height: TwineTokens.sm),
                            ],
                            FilledButton(
                              style: TwineTokens.filled,
                              onPressed: _busy
                                  ? null
                                  : () => _submit(order),
                              child: _busy
                                  ? SizedBox(
                                      height: 18,
                                      width: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: scheme.onPrimary,
                                      ),
                                    )
                                  : const Text('Take'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _submit(TwineOrder order) async {
    final draft = TakeDraft(
      orderId: order.orderId,
      fiatAmount: _amount.text,
      invoice: _invoice.text,
      requireInvoice: true,
    );
    final invalid = draft.validate(order: order);
    if (invalid != null) {
      setState(() => _error = invalid);
      return;
    }
    final estimate = aboutCkb(_amount.text, order.pricePerCkb);
    const roleLine = 'You pay by mobile transfer after the seller locks.';
    final confirmBody = estimate == null
        ? roleLine
        : '$roleLine About $estimate CKB at this price.';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Buy CKB?'),
          content: Text(confirmBody),
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
