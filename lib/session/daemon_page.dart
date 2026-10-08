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
    this.onLogOut,
  });

  final TwineDaemon? current;
  final bool busy;
  final String? error;
  final void Function(String pubkey, String relays) onSave;
  final VoidCallback? onCancel;
  final VoidCallback? onLogOut;

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
                        ? 'This switches the book. Posts and trades on the previous daemon stay with that daemon.'
                        : 'This operator coordinates the hold. It does not hold your Fiber key. Relays carry public orders. The key below is the daemon this install ships with.',
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
                    child: widget.busy
                        ? const SizedBox(
                            height: 18,
                            width: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(editing ? 'Save' : 'Connect'),
                  ),
                  if (widget.onCancel != null) ...[
                    const SizedBox(height: 12),
                    TextButton(
                      onPressed: widget.busy ? null : widget.onCancel,
                      child: const Text('Cancel'),
                    ),
                  ],
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
