/// The account, the daemon, and the Fiber node, after sign-in.
library;

import 'package:flutter/material.dart';
import 'package:twine_app/nostr/account.dart';
import 'package:twine_app/nostr/daemon.dart';

class SignedInPage extends StatelessWidget {
  const SignedInPage({
    super.key,
    required this.account,
    required this.daemon,
    required this.onLogOut,
    required this.onChangeDaemon,
    this.onClose,
    this.inShell = false,
    this.connecting = false,
    this.connectedRelays = const [],
    this.fiberNode,
    this.relayError,
    this.error,
  });

  final TwineAccount account;
  final TwineDaemon daemon;
  final VoidCallback onLogOut;
  final VoidCallback onChangeDaemon;
  final VoidCallback? onClose;
  final bool inShell;
  final bool connecting;
  final List<String> connectedRelays;
  final String? fiberNode;
  final String? relayError;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final body = SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text('Signed in', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          SelectableText(account.npub),
          const SizedBox(height: 24),
          Text('Daemon', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          SelectableText(daemon.npub),
          const SizedBox(height: 16),
          Text('Relays', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          for (final relay in daemon.relays) Text(relay),
          if (!connecting &&
              relayError == null &&
              connectedRelays.isNotEmpty &&
              connectedRelays.length != daemon.relays.length) ...[
            const SizedBox(height: 8),
            Text('Connected', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            for (final relay in connectedRelays) Text(relay),
          ],
          if (connecting) ...[
            const SizedBox(height: 8),
            const Text('Connecting to relays…'),
          ],
          if (relayError != null) ...[
            const SizedBox(height: 8),
            Text(
              relayError!,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          ],
          if (fiberNode != null) ...[
            const SizedBox(height: 24),
            Text('Fiber node', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            SelectableText(fiberNode!),
            const SizedBox(height: 8),
            const Text('Open a channel to this node in your Fiber wallet.'),
          ] else if (!connecting &&
              relayError == null &&
              connectedRelays.isNotEmpty) ...[
            const SizedBox(height: 24),
            const Text('Waiting for the Fiber node…'),
          ],
          const SizedBox(height: 24),
          OutlinedButton(
            onPressed: onChangeDaemon,
            child: const Text('Change daemon'),
          ),
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: () => _showSecret(context),
            child: const Text('Show secret'),
          ),
          const SizedBox(height: 12),
          TextButton(
            onPressed: () => _confirmLogOut(context),
            child: const Text('Log out'),
          ),
          if (error != null) ...[
            const SizedBox(height: 12),
            Text(
              error!,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          ],
        ],
      ),
    );
    if (inShell) return body;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Twine'),
        leading: onClose == null ? null : BackButton(onPressed: onClose),
      ),
      body: body,
    );
  }

  void _showSecret(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Secret key'),
          content: SelectableText(account.nsec),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _confirmLogOut(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Log out?'),
          content: const Text('This removes the key from this device.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Log out'),
            ),
          ],
        );
      },
    );
    if (confirmed == true) onLogOut();
  }
}
