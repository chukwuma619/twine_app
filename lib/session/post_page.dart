import 'package:currency_picker/currency_picker.dart';
import 'package:flutter/material.dart';

import '../nostr/order.dart';
import '../nostr/request.dart';

class _CurrencyField extends StatelessWidget {
  const _CurrencyField({
    required this.code,
    required this.enabled,
    required this.onPick,
  });

  final String code;
  final bool enabled;
  final VoidCallback onPick;

  @override
  Widget build(BuildContext context) {
    final currency = CurrencyService().findByCode(code);
    final label = currency == null
        ? code
        : '${currency.code} · ${currency.name}';
    return InkWell(
      onTap: enabled ? onPick : null,
      child: InputDecorator(
        decoration: const InputDecoration(
          labelText: 'Currency',
          border: OutlineInputBorder(),
          suffixIcon: Icon(Icons.arrow_drop_down),
        ),
        child: Text(label),
      ),
    );
  }
}

class PostPage extends StatefulWidget {
  const PostPage({super.key, required this.onSubmit});

  final Future<String?> Function(NewOrderDraft draft) onSubmit;

  @override
  State<PostPage> createState() => _PostPageState();
}

class _PostPageState extends State<PostPage> {
  late final TextEditingController _available;
  late final TextEditingController _price;
  late final TextEditingController _min;
  late final TextEditingController _max;
  late String _currency;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _available = TextEditingController();
    _price = TextEditingController();
    _min = TextEditingController();
    _max = TextEditingController();
    _currency = 'NGN';
  }

  @override
  void dispose() {
    _available.dispose();
    _price.dispose();
    _min.dispose();
    _max.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
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
                    _available,
                    'CKB available',
                    number: true,
                    helper: 'At least $minPostCkb CKB.',
                  ),
                  const SizedBox(height: 12),
                  _CurrencyField(
                    code: _currency,
                    enabled: !_busy,
                    onPick: _pickCurrency,
                  ),
                  const SizedBox(height: 12),
                  _field(_price, 'Price per CKB', number: true),
                  const SizedBox(height: 12),
                  _field(
                    _min,
                    'Minimum',
                    number: true,
                    suffix: _currency.isEmpty ? null : _currency,
                    helper: 'At least $minPostCkb CKB at this price.',
                  ),
                  const SizedBox(height: 12),
                  _field(
                    _max,
                    'Maximum',
                    number: true,
                    suffix: _currency.isEmpty ? null : _currency,
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
                    onPressed: _busy ? null : _submit,
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

  void _pickCurrency() {
    showCurrencyPicker(
      context: context,
      showDragHandle: true,
      onSelect: (currency) => setState(() => _currency = currency.code),
    );
  }

  Future<void> _submit() async {
    final draft = NewOrderDraft(
      side: OrderSide.sell,
      availableCkb: _available.text,
      fiatCurrency: _currency,
      pricePerCkb: _price.text,
      min: _min.text,
      max: _max.text,
    );
    final invalid = draft.validate();
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
