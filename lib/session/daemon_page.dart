/// The public key and relays of the daemon this install uses.
library;

import 'package:flutter/material.dart';
import 'package:twine_app/nostr/daemon.dart';

class DaemonPage extends StatefulWidget {
  const DaemonPage({
    super.key,
    required this.onSave,
    required this.busy,
    this.current,
    this.error,
    this.onCancel,
  });

  final TwineDaemon? current;
  final bool busy;
  final String? error;
  final void Function(String pubkey, String relays) onSave;
  final VoidCallback? onCancel;

  @override
  State<DaemonPage> createState() => _DaemonPageState();
}

class _DaemonPageState extends State<DaemonPage> {
  late final TextEditingController _pubkey;
  late final TextEditingController _relays;

  @override
  void initState() {
    super.initState();
    _pubkey = TextEditingController(
      text: widget.current?.npub ?? officialDaemonNpub,
    );
    _relays = TextEditingController(
      text:
          widget.current?.relays.join(', ') ?? officialDaemonRelays.join(', '),
    );
  }

  @override
  void dispose() {
    _pubkey.dispose();
    _relays.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final editing = widget.current != null;
    return Scaffold(
      appBar: AppBar(title: const Text('Twine')),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    editing ? 'Change daemon' : 'Connect to a daemon',
                    style: theme.textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    editing
                        ? 'Replace the public key and relays to use another daemon.'
                        : 'The official daemon is filled in. Replace it to use another one.',
                  ),
                  const SizedBox(height: 24),
                  TextField(
                    controller: _pubkey,
                    enabled: !widget.busy,
                    minLines: 1,
                    maxLines: 3,
                    autocorrect: false,
                    enableSuggestions: false,
                    decoration: const InputDecoration(
                      labelText: 'Daemon public key',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _relays,
                    enabled: !widget.busy,
                    minLines: 1,
                    maxLines: 4,
                    autocorrect: false,
                    enableSuggestions: false,
                    decoration: const InputDecoration(
                      labelText: 'Relays',
                      hintText: 'wss://relay.example.com',
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
                  FilledButton(
                    onPressed: widget.busy
                        ? null
                        : () => widget.onSave(_pubkey.text, _relays.text),
                    child: Text(editing ? 'Save' : 'Connect'),
                  ),
                  if (widget.onCancel != null) ...[
                    const SizedBox(height: 12),
                    TextButton(
                      onPressed: widget.busy ? null : widget.onCancel,
                      child: const Text('Cancel'),
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
