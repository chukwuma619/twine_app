import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class BackupPage extends StatefulWidget {
  const BackupPage({
    super.key,
    required this.nsec,
    required this.onContinue,
    this.onLogOut,
    this.busy = false,
  });

  final String nsec;
  final VoidCallback onContinue;
  final VoidCallback? onLogOut;
  final bool busy;

  @override
  State<BackupPage> createState() => _BackupPageState();
}

class _BackupPageState extends State<BackupPage> {
  bool _saved = false;

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
                  SelectableText(widget.nsec),
                  const SizedBox(height: 12),
                  OutlinedButton(
                    onPressed: widget.busy
                        ? null
                        : () async {
                            await Clipboard.setData(
                              ClipboardData(text: widget.nsec),
                            );
                            if (!context.mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Copied')),
                            );
                          },
                    child: const Text('Copy'),
                  ),
                  const SizedBox(height: 12),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: _saved,
                    onChanged: widget.busy
                        ? null
                        : (value) => setState(() => _saved = value ?? false),
                    title: const Text('I saved this somewhere safe'),
                  ),
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: widget.busy || !_saved ? null : widget.onContinue,
                    child: widget.busy
                        ? const SizedBox(
                            height: 18,
                            width: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Continue'),
                  ),
                  if (widget.onLogOut != null) ...[
                    const SizedBox(height: 12),
                    TextButton(
                      onPressed: widget.busy ? null : widget.onLogOut,
                      child: const Text('Use a different key'),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
