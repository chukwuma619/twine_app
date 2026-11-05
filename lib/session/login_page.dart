import 'package:flutter/material.dart';
import 'package:twine_app/twine_logo.dart';

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
  bool _obscure = true;

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
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: TwineLogo(size: 40),
                  ),
                  const SizedBox(height: 12),
                  Text('Twine', style: theme.textTheme.headlineMedium),
                  const SizedBox(height: 8),
                  const Text(
                    'Your Nostr key is your account. CKB stays in your Fiber wallet.',
                  ),
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: widget.busy ? null : widget.onCreate,
                    child: widget.busy
                        ? const SizedBox(
                            height: 18,
                            width: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Create a key'),
                  ),
                  const SizedBox(height: 24),
                  TextField(
                    controller: _secret,
                    enabled: !widget.busy,
                    autocorrect: false,
                    enableSuggestions: false,
                    obscureText: _obscure,
                    decoration: InputDecoration(
                      labelText: 'nsec',
                      helperText: 'Paste an nsec or a 64-character hex secret.',
                      suffixIcon: IconButton(
                        tooltip: _obscure ? 'Show key' : 'Hide key',
                        onPressed: () => setState(() => _obscure = !_obscure),
                        icon: Icon(
                          _obscure
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                        ),
                      ),
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
