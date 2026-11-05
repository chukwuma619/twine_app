import 'package:currency_picker/currency_picker.dart';
import 'package:flutter/material.dart';

import '../market/amount.dart';
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
            padding: const EdgeInsets.symmetric(
              horizontal: TwineTokens.md,
              vertical: TwineTokens.xs,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Fiat currency',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        label,
                        style: theme.textTheme.bodyLarge?.copyWith(
                          color: foreground,
                          height: 1.2,
                        ),
                      ),
                    ],
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
    _available = TextEditingController()..addListener(_onChanged);
    _price = TextEditingController()..addListener(_onChanged);
    _min = TextEditingController()..addListener(_onChanged);
    _max = TextEditingController()..addListener(_onChanged);
    _currency = 'NGN';
  }

  void _onChanged() {
    if (!mounted) return;
    setState(() {
      _error = null;
    });
  }

  @override
  void dispose() {
    _available
      ..removeListener(_onChanged)
      ..dispose();
    _price
      ..removeListener(_onChanged)
      ..dispose();
    _min
      ..removeListener(_onChanged)
      ..dispose();
    _max
      ..removeListener(_onChanged)
      ..dispose();
    super.dispose();
  }

  String? get _minFiatFloor {
    final price = double.tryParse(_price.text.trim());
    if (price == null || price <= 0) return null;
    return _formatFiat(minPostCkb * price);
  }

  String? get _maxFiatCeiling {
    final price = double.tryParse(_price.text.trim());
    final available = double.tryParse(_available.text.trim());
    if (price == null || price <= 0 || available == null || available <= 0) {
      return null;
    }
    return _formatFiat(available * price);
  }

  static String _formatFiat(double value) {
    final rounded = value.toStringAsFixed(2);
    if (rounded.endsWith('.00')) {
      return rounded.substring(0, rounded.length - 3);
    }
    if (rounded.endsWith('0')) {
      return rounded.substring(0, rounded.length - 1);
    }
    return rounded;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final muted = TwineTokens.muted(theme);
    final suffixCurrency = _currency.isEmpty ? null : _currency;
    final minFloor = _minFiatFloor;
    final totalFiat = _maxFiatCeiling;
    final minCkb = aboutCkb(_min.text, _price.text);
    final maxCkb = aboutCkb(_max.text, _price.text);

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
                          style: muted,
                        ),
                        const SizedBox(height: TwineTokens.lg),
                        Text('Offer', style: TwineTokens.section(theme)),
                        const SizedBox(height: TwineTokens.xs),
                        _CurrencyField(
                          code: _currency,
                          enabled: !_busy,
                          onPick: _pickCurrency,
                        ),
                        const SizedBox(height: TwineTokens.sm),
                        TextField(
                          controller: _price,
                          enabled: !_busy,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          textInputAction: TextInputAction.next,
                          autocorrect: false,
                          enableSuggestions: false,
                          style: TwineTokens.price(theme),
                          decoration: TwineTokens.field(
                            theme,
                            label: 'Price per CKB',
                            suffix: suffixCurrency,
                          ),
                        ),
                        const SizedBox(height: TwineTokens.sm),
                        TextField(
                          controller: _available,
                          enabled: !_busy,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          textInputAction: TextInputAction.next,
                          autocorrect: false,
                          enableSuggestions: false,
                          decoration: TwineTokens.field(
                            theme,
                            label: 'CKB available',
                            suffix: 'CKB',
                            helper: totalFiat == null
                                ? 'At least $minPostCkb CKB.'
                                : 'Total offer value: $totalFiat $_currency',
                          ),
                        ),
                        const SizedBox(height: TwineTokens.lg),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Each trade',
                              style: TwineTokens.section(theme),
                            ),
                            if (minFloor != null || totalFiat != null)
                              Wrap(
                                spacing: TwineTokens.xs,
                                children: [
                                  if (minFloor != null)
                                    ActionChip(
                                      visualDensity: VisualDensity.compact,
                                      label: const Text('Min $minPostCkb CKB'),
                                      onPressed: _busy
                                          ? null
                                          : () => _min.text = minFloor,
                                    ),
                                  if (totalFiat != null)
                                    ActionChip(
                                      visualDensity: VisualDensity.compact,
                                      label: const Text('Full amount'),
                                      onPressed: _busy
                                          ? null
                                          : () => _max.text = totalFiat,
                                    ),
                                ],
                              ),
                          ],
                        ),
                        const SizedBox(height: TwineTokens.xs),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: _limit(
                                _min,
                                'Minimum',
                                helper: minCkb == null ? null : '≈ $minCkb CKB',
                                action: TextInputAction.next,
                              ),
                            ),
                            const SizedBox(width: TwineTokens.sm),
                            Expanded(
                              child: _limit(
                                _max,
                                'Maximum',
                                helper: maxCkb == null ? null : '≈ $maxCkb CKB',
                                action: TextInputAction.done,
                                onSubmitted: (_) {
                                  if (!_busy) _submit();
                                },
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: TwineTokens.xs),
                        Text(
                          minFloor == null
                              ? 'At least $minPostCkb CKB.'
                              : 'At least $minPostCkb CKB ($minFloor $_currency).',
                          style: muted,
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

  Widget _limit(
    TextEditingController controller,
    String label, {
    String? helper,
    TextInputAction? action,
    ValueChanged<String>? onSubmitted,
  }) {
    return TextField(
      controller: controller,
      enabled: !_busy,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      textInputAction: action,
      onSubmitted: onSubmitted,
      autocorrect: false,
      enableSuggestions: false,
      decoration: TwineTokens.field(
        Theme.of(context),
        label: label,
        suffix: _currency.isEmpty ? null : _currency,
        helper: helper,
      ),
    );
  }

  void _pickCurrency() {
    showCurrencyPicker(
      context: context,
      showDragHandle: true,
      onSelect: (currency) => setState(() {
        _currency = currency.code;
        _error = null;
      }),
    );
  }

  Future<void> _submit() async {
    final draft = NewOrderDraft(
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
      Navigator.of(context).pop();
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
