import 'package:currency_picker/currency_picker.dart';
import 'package:flutter/material.dart';

import '../nostr/order.dart';
import '../nostr/request.dart';
import '../ui/twine_tokens.dart';

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
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final currency = CurrencyService().findByCode(code);
    final label = currency == null
        ? code
        : '${currency.code} · ${currency.name}';
    final foreground = enabled
        ? scheme.onSurface
        : scheme.onSurface.withValues(alpha: 0.38);
    return Material(
      color: scheme.surfaceContainerLow,
      shape: const RoundedRectangleBorder(borderRadius: TwineTokens.smRadius),
      child: InkWell(
        onTap: enabled ? onPick : null,
        borderRadius: TwineTokens.smRadius,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: TwineTokens.control),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: TwineTokens.md),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    label,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: foreground,
                      height: 1.2,
                    ),
                  ),
                ),
                Icon(
                  Icons.expand_more,
                  size: TwineTokens.iconMd,
                  color: scheme.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ),
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
    final scheme = theme.colorScheme;
    return Scaffold(
      resizeToAvoidBottomInset: true,
      appBar: AppBar(title: const Text('New post')),
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
                          'Locks in your Fiber wallet when someone takes it.',
                          style: TwineTokens.muted(theme),
                        ),
                        const SizedBox(height: TwineTokens.lg),
                        TextField(
                          controller: _price,
                          enabled: !_busy,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          autocorrect: false,
                          enableSuggestions: false,
                          style: TwineTokens.price(theme),
                          decoration: TwineTokens.field(
                            theme,
                            label: 'Price per CKB',
                          ),
                        ),
                        const SizedBox(height: TwineTokens.xs),
                        _CurrencyField(
                          code: _currency,
                          enabled: !_busy,
                          onPick: _pickCurrency,
                        ),
                        const SizedBox(height: TwineTokens.lg),
                        TextField(
                          controller: _available,
                          enabled: !_busy,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          autocorrect: false,
                          enableSuggestions: false,
                          decoration: TwineTokens.field(
                            theme,
                            label: 'CKB available',
                            suffix: 'CKB',
                          ),
                        ),
                        const SizedBox(height: TwineTokens.lg),
                        Text('Each trade', style: TwineTokens.section(theme)),
                        const SizedBox(height: TwineTokens.xs),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(child: _limit(_min, 'Minimum')),
                            const SizedBox(width: TwineTokens.sm),
                            Expanded(child: _limit(_max, 'Maximum')),
                          ],
                        ),
                        const SizedBox(height: TwineTokens.xs),
                        Text(
                          'At least $minPostCkb CKB.',
                          style: TwineTokens.muted(theme),
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
                          onPressed: _busy ? null : _submit,
                          child: _busy
                              ? SizedBox(
                                  height: 18,
                                  width: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: scheme.onPrimary,
                                  ),
                                )
                              : const Text('Post'),
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
  }

  Widget _limit(TextEditingController controller, String label) {
    return TextField(
      controller: controller,
      enabled: !_busy,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      autocorrect: false,
      enableSuggestions: false,
      decoration: TwineTokens.field(
        Theme.of(context),
        label: label,
        suffix: _currency.isEmpty ? null : _currency,
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
    final confirmed = await _confirmOffer();
    if (!confirmed || !mounted) return;
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

  Future<bool> _confirmOffer() async {
    final currency = _currency;
    final offered = _available.text.trim();
    final price = _price.text.trim();
    final low = _min.text.trim();
    final high = _max.text.trim();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Post this offer?'),
          content: Text(
            '$offered CKB at $price $currency per CKB.\n'
            'Trades from $low to $high $currency.\n\n'
            'You lock the CKB in your Fiber wallet when someone takes it.',
          ),
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
}
