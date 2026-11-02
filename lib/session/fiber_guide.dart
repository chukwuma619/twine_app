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
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Pay with any Fiber wallet', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        const Text(
          'Create the payout invoice in the wallet that should receive the CKB, and pay the hold invoice from the wallet that is sending it. Twine does not ask which wallet that is.',
        ),
        const SizedBox(height: 12),
        Text('Desk Fiber node', style: theme.textTheme.titleSmall),
        const SizedBox(height: 8),
        Text(deskNodeSummary()),
        const SizedBox(height: 8),
        if (pubkey == null)
          const Text(
            'This daemon has not announced a Fiber node yet. A wallet that already has a route does not need one.',
          )
        else ...[
          Text('Pubkey', style: theme.textTheme.labelLarge),
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
            const Text('This daemon has not announced a public multiaddr yet.')
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
