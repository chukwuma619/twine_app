import 'package:flutter/material.dart';

import '../nostr/catalog.dart';
import '../nostr/order.dart';
import '../nostr/request.dart';

class PostPage extends StatefulWidget {
  const PostPage({
    super.key,
    required this.onSubmit,
    this.fiberPubkey,
    this.catalog = const [],
    this.initialSide = OrderSide.sell,
  });

  final String? fiberPubkey;
  final List<CatalogMethod> catalog;
  final OrderSide initialSide;
  final Future<String?> Function(NewOrderDraft draft) onSubmit;

  @override
  State<PostPage> createState() => _PostPageState();
}

class _PostPageState extends State<PostPage> {
  late final TextEditingController _fiber;
  late final TextEditingController _available;
  late final TextEditingController _price;
  late final TextEditingController _min;
  late final TextEditingController _max;
  late String _currency;
  late Set<String> _methodIds;
  late OrderSide _side;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _side = widget.initialSide;
    _fiber = TextEditingController(text: widget.fiberPubkey ?? '');
    _available = TextEditingController();
    _price = TextEditingController();
    _min = TextEditingController();
    _max = TextEditingController();
    final currencies = catalogCurrencies(widget.catalog);
    _currency = currencies.isEmpty ? '' : currencies.first;
    _methodIds = {
      for (final method in methodsForCurrency(widget.catalog, _currency))
        method.id,
    };
  }

  @override
  void didUpdateWidget(PostPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    final currencies = catalogCurrencies(widget.catalog);
    if (currencies.isEmpty || currencies.contains(_currency)) return;
    _currency = currencies.first;
    _methodIds
      ..clear()
      ..addAll(
        methodsForCurrency(
          widget.catalog,
          _currency,
        ).map((method) => method.id),
      );
  }

  @override
  void dispose() {
    _fiber.dispose();
    _available.dispose();
    _price.dispose();
    _min.dispose();
    _max.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final currencies = catalogCurrencies(widget.catalog);
    final methods = methodsForCurrency(widget.catalog, _currency);
    return Scaffold(
      appBar: AppBar(title: const Text('New post')),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Wrap(
                    spacing: 8,
                    children: [
                      for (final side in OrderSide.values)
                        ChoiceChip(
                          label: Text(
                            side == OrderSide.sell ? 'Sell CKB' : 'Buy CKB',
                          ),
                          selected: _side == side,
                          onSelected: _busy
                              ? null
                              : (selected) {
                                  if (selected) setState(() => _side = side);
                                },
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _field(_fiber, 'Your Fiber pubkey'),
                  const SizedBox(height: 12),
                  _field(_available, 'CKB available', number: true),
                  const SizedBox(height: 12),
                  if (currencies.isEmpty)
                    const Text('Waiting for payment methods.')
                  else
                    DropdownButtonFormField<String>(
                      initialValue: _currency,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Currency',
                        border: OutlineInputBorder(),
                      ),
                      items: [
                        for (final currency in currencies)
                          DropdownMenuItem(
                            value: currency,
                            child: Text(currency),
                          ),
                      ],
                      onChanged: _busy
                          ? null
                          : (currency) {
                              if (currency != null) _chooseCurrency(currency);
                            },
                    ),
                  const SizedBox(height: 12),
                  _field(_price, 'Price per CKB', number: true),
                  const SizedBox(height: 12),
                  _field(_min, 'Minimum', number: true),
                  const SizedBox(height: 12),
                  _field(_max, 'Maximum', number: true),
                  const SizedBox(height: 8),
                  for (final method in methods)
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(method.label),
                      subtitle: Text(method.kind),
                      value: _methodIds.contains(method.id),
                      onChanged: _busy
                          ? null
                          : (checked) => _toggle(method.id, checked ?? false),
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
                    onPressed: _busy || currencies.isEmpty ? null : _submit,
                    child: const Text('Post'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _field(
    TextEditingController controller,
    String label, {
    bool number = false,
  }) {
    return TextField(
      controller: controller,
      enabled: !_busy,
      keyboardType: number
          ? const TextInputType.numberWithOptions(decimal: true)
          : TextInputType.text,
      autocorrect: false,
      enableSuggestions: false,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
      ),
    );
  }

  void _chooseCurrency(String currency) {
    setState(() {
      _currency = currency;
      _methodIds
        ..clear()
        ..addAll(
          methodsForCurrency(
            widget.catalog,
            currency,
          ).map((method) => method.id),
        );
    });
  }

  void _toggle(String id, bool selected) {
    setState(() {
      if (selected) {
        _methodIds.add(id);
      } else {
        _methodIds.remove(id);
      }
    });
  }

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final error = await widget.onSubmit(
      NewOrderDraft(
        side: _side,
        fiberPubkey: _fiber.text,
        availableCkb: _available.text,
        fiatCurrency: _currency,
        pricePerCkb: _price.text,
        min: _min.text,
        max: _max.text,
        methodIds: _methodIds.toList(),
      ),
    );
    if (!mounted) return;
    if (error == null) {
      Navigator.of(context).pop(_side);
      return;
    }
    setState(() {
      _busy = false;
      _error = error;
    });
  }
}
