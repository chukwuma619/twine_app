import 'dart:async';

import 'package:flutter/material.dart';

import '../ui/twine_tokens.dart';

/// A refusal shown once at the top of the screen. It leaves on its own, and
/// the close control dismisses it sooner. The bottom navigation stays usable.
class DismissibleNotice extends StatefulWidget {
  const DismissibleNotice({
    super.key,
    required this.message,
    required this.onDismiss,
  });

  final String message;
  final VoidCallback onDismiss;

  @override
  State<DismissibleNotice> createState() => _DismissibleNoticeState();
}

class _DismissibleNoticeState extends State<DismissibleNotice> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _arm();
  }

  @override
  void didUpdateWidget(DismissibleNotice oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.message != widget.message) _arm();
  }

  void _arm() {
    _timer?.cancel();
    _timer = Timer(const Duration(seconds: 4), () {
      if (mounted) widget.onDismiss();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = theme.colorScheme.onErrorContainer;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        TwineTokens.md,
        TwineTokens.sm,
        TwineTokens.md,
        0,
      ),
      child: Material(
        color: theme.colorScheme.errorContainer,
        borderRadius: TwineTokens.smRadius,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            TwineTokens.sm,
            TwineTokens.xxs,
            TwineTokens.xxs,
            TwineTokens.xxs,
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  widget.message,
                  style: TwineTokens.body(theme).copyWith(color: color),
                ),
              ),
              IconButton(
                tooltip: 'Dismiss',
                onPressed: widget.onDismiss,
                icon: Icon(Icons.close, color: color),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
