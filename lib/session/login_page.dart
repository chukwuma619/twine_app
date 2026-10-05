/// Create a key, or import an nsec.
library;

import 'package:flutter/material.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({
    super.key,
    required this.onCreate,
    required this.onImport,
    required this.busy,
    this.error,
  });

  final VoidCallback onCreate;
  final ValueChanged<String> onImport;
  final bool busy;
  final String? error;

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _secret = TextEditingController();

  @override
  void dispose() {
    _secret.dispose();
    super.dispose();
  }

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
                  Text('Twine', style: theme.textTheme.headlineMedium),
                  const SizedBox(height: 8),
                  const Text('Your Nostr key is your account.'),
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: widget.busy ? null : widget.onCreate,
                    child: const Text('Create a key'),
                  ),
                  const SizedBox(height: 24),
                  TextField(
                    controller: _secret,
                    enabled: !widget.busy,
                    minLines: 1,
                    maxLines: 3,
                    autocorrect: false,
                    enableSuggestions: false,
                    decoration: const InputDecoration(
                      labelText: 'nsec',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  if (widget.error != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      widget.error!,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.error,
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  OutlinedButton(
                    onPressed: widget.busy
                        ? null
                        : () => widget.onImport(_secret.text),
                    child: const Text('Import'),
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
