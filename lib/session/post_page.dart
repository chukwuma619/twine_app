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
    this.fiberNode,
  });

  final String? fiberPubkey;
  final List<CatalogMethod> catalog;
  final String? fiberNode;
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
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
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
                  Text(
                    'You lock CKB in your Fiber wallet when someone takes this.',
                    style: theme.textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 16),
                  _field(
                    _fiber,
                    'Your Fiber pubkey',
                    helper: 'This is your Fiber node pubkey, not an npub.',
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Open a channel to the operator Fiber node in your wallet before you post.',
                  ),
                  if (widget.fiberNode == null) ...[
                    const SizedBox(height: 8),
                    const Text('Waiting for the Fiber node.'),
                  ],
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
                  _field(
                    _min,
                    'Minimum',
                    number: true,
                    suffix: _currency.isEmpty ? null : _currency,
                  ),
                  const SizedBox(height: 12),
                  _field(
                    _max,
                    'Maximum',
                    number: true,
                    suffix: _currency.isEmpty ? null : _currency,
                  ),
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
                    child: _busy
                        ? const SizedBox(
                            height: 18,
                            width: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Post'),
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
    String? helper,
    String? suffix,
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
        helperText: helper,
        suffixText: suffix,
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
    final draft = NewOrderDraft(
      side: OrderSide.sell,
      fiberPubkey: _fiber.text,
      availableCkb: _available.text,
      fiatCurrency: _currency,
      pricePerCkb: _price.text,
      min: _min.text,
      max: _max.text,
      methodIds: _methodIds.toList(),
    );
    final invalid = draft.validate(widget.catalog);
    if (invalid != null) {
      setState(() => _error = invalid);
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Sell CKB?'),
          content: const Text(
            'You lock CKB in your Fiber wallet when someone takes this.',
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
    final error = await widget.onSubmit(draft);
    if (!mounted) return;
    if (error == null) {
      Navigator.of(context).pop(OrderSide.sell);
      return;
    }
    setState(() {
      _busy = false;
      _error = error;
    });
  }
}
