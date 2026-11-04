import 'package:flutter/material.dart';

import 'update_controller.dart';
import 'version.dart';

/// A bar on the market shell when a newer release is ready.
class UpdateBanner extends StatelessWidget {
  const UpdateBanner({super.key, required this.controller});

  final UpdateController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        if (!controller.offer) return const SizedBox.shrink();
        final theme = Theme.of(context);
        final version = controller.release?.version ?? '';
        final busy =
            controller.phase == UpdatePhase.downloading ||
            controller.phase == UpdatePhase.installing;
        return Material(
          color: theme.colorScheme.primaryContainer,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  _bannerText(controller, version),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onPrimaryContainer,
                  ),
                ),
                if (busy) ...[
                  const SizedBox(height: 8),
                  LinearProgressIndicator(value: controller.progress),
                ],
                if (controller.error != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    controller.error!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.error,
                    ),
                  ),
                ],
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: busy ? null : controller.dismiss,
                      child: const Text('Later'),
                    ),
                    const SizedBox(width: 4),
                    FilledButton(
                      onPressed: busy
                          ? null
                          : () => confirmAndInstall(context, controller),
                      child: Text(busy ? 'Installing' : 'Install'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Version and update controls on the account screen.
class UpdateSection extends StatelessWidget {
  const UpdateSection({super.key, required this.controller});

  final UpdateController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        if (controller.phase == UpdatePhase.unsupported) {
          return const SizedBox.shrink();
        }
        final theme = Theme.of(context);
        final version = controller.version;
        final busy =
            controller.phase == UpdatePhase.checking ||
            controller.phase == UpdatePhase.downloading ||
            controller.phase == UpdatePhase.installing;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('App', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(version == null ? 'Twine' : 'Twine $version'),
            const SizedBox(height: 8),
            Text(_sectionText(controller)),
            if (controller.phase == UpdatePhase.downloading ||
                controller.phase == UpdatePhase.installing) ...[
              const SizedBox(height: 8),
              LinearProgressIndicator(value: controller.progress),
            ],
            if (controller.error != null) ...[
              const SizedBox(height: 8),
              Text(
                controller.error!,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ],
            const SizedBox(height: 12),
            if (controller.phase == UpdatePhase.available ||
                controller.phase == UpdatePhase.downloading ||
                controller.phase == UpdatePhase.installing ||
                controller.phase == UpdatePhase.ready)
              FilledButton(
                onPressed: busy
                    ? null
                    : () => confirmAndInstall(context, controller),
                child: const Text('Install update'),
              )
            else
              OutlinedButton(
                onPressed: busy ? null : () => controller.check(manual: true),
                child: Text(busy ? 'Checking…' : 'Check for updates'),
              ),
          ],
        );
      },
    );
  }
}

String _bannerText(UpdateController controller, String version) {
  switch (controller.phase) {
    case UpdatePhase.downloading:
      return 'Downloading Twine $version.';
    case UpdatePhase.installing:
      return controller.target == UpdateTarget.android
          ? 'Opening the installer for Twine $version.'
          : 'Installing Twine $version. The app will reopen.';
    case UpdatePhase.ready:
      return 'Confirm the install for Twine $version.';
    case UpdatePhase.available:
    case UpdatePhase.idle:
    case UpdatePhase.checking:
    case UpdatePhase.upToDate:
    case UpdatePhase.failed:
    case UpdatePhase.unsupported:
      return 'Twine $version is available.';
  }
}

String _sectionText(UpdateController controller) {
  final next = controller.release?.version;
  switch (controller.phase) {
    case UpdatePhase.idle:
      return 'Tester builds install from GitHub.';
    case UpdatePhase.checking:
      return 'Checking for an update…';
    case UpdatePhase.upToDate:
      return 'This is the latest release.';
    case UpdatePhase.available:
      return 'Twine $next is available.';
    case UpdatePhase.downloading:
      return 'Downloading Twine $next.';
    case UpdatePhase.installing:
      return controller.target == UpdateTarget.android
          ? 'Opening the installer.'
          : 'Twine will close and reopen.';
    case UpdatePhase.ready:
      return 'Confirm the install prompt. If Android blocked it, allow installs from Twine and try again.';
    case UpdatePhase.failed:
      return 'The update check did not finish.';
    case UpdatePhase.unsupported:
      return '';
  }
}

Future<void> confirmAndInstall(
  BuildContext context,
  UpdateController controller,
) async {
  if (controller.phase == UpdatePhase.ready) {
    await controller.downloadAndInstall();
    return;
  }
  final version = controller.release?.version ?? 'the new version';
  final android = controller.target == UpdateTarget.android;
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) {
      return AlertDialog(
        title: Text('Install Twine $version?'),
        content: Text(
          android
              ? 'Twine downloads the release and opens the Android installer. The Nostr key stays on this phone.'
              : 'Twine downloads the release, closes, and opens the new version. The Nostr key stays on this device.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Back'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Install'),
          ),
        ],
      );
    },
  );
  if (confirmed != true) return;
  await controller.downloadAndInstall();
}
