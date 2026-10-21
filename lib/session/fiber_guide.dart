import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../market/channel.dart';

class FiberConnectGuide extends StatelessWidget {
  const FiberConnectGuide({
    super.key,
    this.fiberNode,
    this.fiberAddresses = const [],
  });

  final String? fiberNode;
  final List<String> fiberAddresses;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pubkey = fiberNode;
    final steps = fiberConnectSteps(
      announced: pubkey != null,
      hasMultiaddr: fiberAddresses.isNotEmpty,
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Connect your Fiber node', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        const Text(
          'Do this once before you post or take. The daemon coordinates the hold. It does not hold your Fiber key.',
        ),
        const SizedBox(height: 12),
        for (var i = 0; i < steps.length; i++) ...[
          Text('${i + 1}. ${steps[i]}'),
          if (i == 1 && pubkey != null) ...[
            const SizedBox(height: 8),
            Text('Daemon Fiber pubkey', style: theme.textTheme.labelLarge),
            const SizedBox(height: 4),
            SelectableText(pubkey),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: () => _copy(context, pubkey),
                child: const Text('Copy pubkey'),
              ),
            ),
            if (fiberAddresses.isEmpty)
              const Text(
                'Waiting for this daemon to broadcast a public multiaddr.',
              )
            else
              for (final address in fiberAddresses) ...[
                Text('Multiaddr', style: theme.textTheme.labelLarge),
                const SizedBox(height: 4),
                SelectableText(address),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    onPressed: () => _copy(context, address),
                    child: const Text('Copy multiaddr'),
                  ),
                ),
              ],
          ] else
            const SizedBox(height: 8),
        ],
      ],
    );
  }

  Future<void> _copy(BuildContext context, String value) async {
    await Clipboard.setData(ClipboardData(text: value));
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Copied')));
  }
}
