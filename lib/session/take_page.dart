import 'package:flutter/material.dart';

import '../market/amount.dart';
import '../market/role.dart';
import '../nostr/order.dart';
import '../nostr/request.dart';
import 'market.dart';

class TakePage extends StatefulWidget {
  const TakePage({
    super.key,
    required this.market,
    required this.orderId,
    this.fiberNode,
  });

  final TwineMarket market;
  final String orderId;
  final String? fiberNode;

  @override
  State<TakePage> createState() => _TakePageState();
}

class _TakePageState extends State<TakePage> {
  late final TextEditingController _fiber;
  late final TextEditingController _amount;
  String? _methodId;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _fiber = TextEditingController(text: widget.market.fiberPubkey ?? '');
    _amount = TextEditingController();
    _amount.addListener(() {
      if (mounted) setState(() {});
    });
    final order = widget.market.book.order(widget.orderId);
    final methods = order?.paymentMethods ?? const <TwinePaymentMethod>[];
    if (methods.isNotEmpty) _methodId = methods.first.id;
  }

  @override
  void dispose() {
    _fiber.dispose();
    _amount.dispose();
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
        final waitingNode = widget.fiberNode == null;
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
                      Text(
                        '${order.side.label} · ${order.availableCkb} CKB',
                      ),
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
                      TextField(
                        controller: _fiber,
                        enabled: !_busy,
                        autocorrect: false,
                        enableSuggestions: false,
                        decoration: const InputDecoration(
                          labelText: 'Your Fiber pubkey',
                          helperText:
                              'This is your Fiber node pubkey, not an npub.',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'Open a channel to the operator Fiber node in your wallet before you take.',
                      ),
                      if (waitingNode) ...[
                        const SizedBox(height: 8),
                        const Text('Waiting for the Fiber node.'),
                      ],
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        children: [
                          for (final method in order.paymentMethods)
                            ChoiceChip(
                              label: Text('${method.label} · ${method.kind}'),
                              selected: _methodId == method.id,
                              onSelected: _busy
                                  ? null
                                  : (selected) {
                                      if (selected) {
                                        setState(() => _methodId = method.id);
                                      }
                                    },
                            ),
                        ],
                      ),
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
                        onPressed: _busy || waitingNode
                            ? null
                            : () => _submit(order, role),
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
    final methodId = _methodId;
    if (methodId == null) {
      setState(() => _error = 'Pick a payment method.');
      return;
    }
    final draft = TakeDraft(
      orderId: order.orderId,
      fiatAmount: _amount.text,
      fiberPubkey: _fiber.text,
      paymentMethodId: methodId,
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
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(role == TradeSide.seller ? 'Sell CKB?' : 'Buy CKB?'),
          content: Text(
            estimate == null
                ? roleLine
                : '$roleLine About $estimate CKB at this price.',
          ),
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
