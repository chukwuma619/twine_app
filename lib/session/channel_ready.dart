import 'package:flutter/material.dart';

import '../market/channel.dart';

class ChannelReady extends StatelessWidget {
  const ChannelReady({
    super.key,
    required this.role,
    this.fiberNode,
    this.fiberAddresses = const [],
    this.ready,
    this.onReadyChanged,
    this.enabled = true,
  });

  final ChannelRole role;
  final String? fiberNode;
  final List<String> fiberAddresses;
  final bool? ready;
  final ValueChanged<bool>? onReadyChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final waiting = fiberNode == null;
    final showReady = onReadyChanged != null && ready != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Fiber channel', style: theme.textTheme.titleSmall),
        const SizedBox(height: 8),
        if (waiting)
          const Text('Waiting for the Fiber node.')
        else ...[
          SelectableText(fiberNode!),
          const SizedBox(height: 8),
          SelectableText(channelConnectCommand(fiberNode!, fiberAddresses)),
          const SizedBox(height: 8),
          for (final step in channelChecklist(role)) ...[
            Text('• $step'),
            const SizedBox(height: 4),
          ],
          if (showReady) ...[
            const SizedBox(height: 4),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              title: Text(channelReadyLabel(role)),
              value: ready,
              onChanged: enabled
                  ? (checked) => onReadyChanged!(checked ?? false)
                  : null,
            ),
          ],
        ],
      ],
    );
  }
}
