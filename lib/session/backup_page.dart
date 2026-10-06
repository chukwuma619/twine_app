import 'package:flutter/material.dart';

class BackupPage extends StatelessWidget {
  const BackupPage({super.key, required this.nsec, required this.onContinue});

  final String nsec;
  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Save this key', style: theme.textTheme.headlineSmall),
                  const SizedBox(height: 8),
                  const Text(
                    'It is the only way back into this account. Twine does not keep a copy.',
                  ),
                  const SizedBox(height: 16),
                  SelectableText(nsec),
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: onContinue,
                    child: const Text('Continue'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
