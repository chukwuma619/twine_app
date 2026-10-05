import 'package:flutter/material.dart';
import 'package:twine_app/nostr/account.dart';

class SignedInPage extends StatelessWidget {
  const SignedInPage({
    super.key,
    required this.account,
    required this.onLogOut,
    this.relayStatus,
    this.error,
  });

  final TwineAccount account;
  final VoidCallback onLogOut;
  final Widget? relayStatus;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Twine')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Text('Signed in', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            SelectableText(account.npub),
            const SizedBox(height: 24),
            ?relayStatus,
            const SizedBox(height: 24),
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
      ),
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
