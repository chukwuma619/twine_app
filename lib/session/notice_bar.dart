import 'dart:async';

import 'package:flutter/material.dart';

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
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Material(
        color: theme.colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  widget.message,
                  style: theme.textTheme.bodyMedium?.copyWith(color: color),
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
