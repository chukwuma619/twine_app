import 'package:flutter/material.dart';

class RelayStatus extends StatelessWidget {
  const RelayStatus({
    super.key,
    required this.connecting,
    required this.relays,
    this.error,
  });

  final bool connecting;
  final List<String> relays;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodyMedium;
    if (connecting) {
      return Text('Connecting to relays…', style: style);
    }
    if (error != null) {
      return Text(
        error!,
        style: style?.copyWith(color: Theme.of(context).colorScheme.error),
      );
    }
    if (relays.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [for (final relay in relays) Text(relay, style: style)],
    );
  }
}
