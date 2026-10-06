import 'package:flutter/material.dart';

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
        return Scaffold(
          appBar: AppBar(title: const Text('Take')),
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
                        '${order.side.label} · ${order.availableCkb} CKB',
                        style: theme.textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '${order.min}–${order.max} ${order.fiatCurrency} at ${order.pricePerCkb} per CKB',
                      ),
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
                          border: OutlineInputBorder(),
                        ),
                      ),
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
                        onPressed: _busy ? null : () => _submit(order),
                        child: const Text('Take'),
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

  Future<void> _submit(TwineOrder order) async {
    final methodId = _methodId;
    if (methodId == null) {
      setState(() => _error = 'Pick a payment method.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final error = await widget.market.take(
      TakeDraft(
        orderId: order.orderId,
        fiatAmount: _amount.text,
        fiberPubkey: _fiber.text,
        paymentMethodId: methodId,
      ),
    );
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
