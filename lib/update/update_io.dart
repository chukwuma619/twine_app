import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

import 'release.dart';
import 'update_client.dart';
import 'version.dart';

UpdateClient createPlatformUpdateClient() => _IoUpdateClient();

const _androidChannel = MethodChannel('twine/update');

class _IoUpdateClient implements UpdateClient {
  @override
  UpdateTarget? get target => _target();

  @override
  Future<String> currentVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      final version = AppVersion.parse(info.version);
      if (version == null) {
        throw UpdateException('This build has no version.');
      }
      return version.toString();
    } on UpdateException {
      rethrow;
    } catch (_) {
      throw UpdateException('Could not read this app\'s version.');
    }
  }

  @override
  Future<PublishedRelease?> latest() async {
    final body = await _get(latestReleaseUri(), api: true);
    return PublishedRelease.parse(body);
  }

  @override
  Future<String> download(
    ReleaseAsset asset,
    void Function(double? progress) onProgress,
  ) async {
    final directory = await getTemporaryDirectory();
    final folder = Directory('${directory.path}/updates');
    await folder.create(recursive: true);
    final file = File('${folder.path}/${asset.name}');
    if (file.existsSync()) await file.delete();
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 20);
    client.idleTimeout = const Duration(seconds: 60);
    IOSink? sink;
    try {
      final request = await client.getUrl(Uri.parse(asset.url));
      request.followRedirects = true;
      request.maxRedirects = 10;
      request.headers.set(HttpHeaders.userAgentHeader, 'Twine');
      final response = await request.close();
      if (response.statusCode != HttpStatus.ok) {
        throw UpdateException('The download stopped (${response.statusCode}).');
      }
      final total = response.contentLength;
      var received = 0;
      sink = file.openWrite();
      await for (final chunk in response) {
        received += chunk.length;
        sink.add(chunk);
        onProgress(total > 0 ? received / total : null);
      }
      await sink.flush();
      await sink.close();
      sink = null;
      onProgress(1);
      return file.path;
    } on UpdateException {
      rethrow;
    } catch (_) {
      throw UpdateException('Could not download the update.');
    } finally {
      final open = sink;
      if (open != null) await open.close();
      client.close(force: true);
    }
  }

  @override
  Future<void> install(UpdateTarget target, String path) async {
    switch (target) {
      case UpdateTarget.android:
        await _installAndroid(path);
      case UpdateTarget.macos:
        await _relaunch(_macosScript, path);
      case UpdateTarget.windows:
        await _relaunch(_windowsScript, path, powershell: true);
      case UpdateTarget.linux:
        await _relaunch(_linuxScript, path);
    }
  }
}

UpdateTarget? _target() {
  if (Platform.isAndroid) return UpdateTarget.android;
  if (Platform.isMacOS) return UpdateTarget.macos;
  if (Platform.isWindows) {
    if (Abi.current() != Abi.windowsX64) return null;
    return UpdateTarget.windows;
  }
  if (Platform.isLinux) {
    if (Abi.current() != Abi.linuxX64) return null;
    return UpdateTarget.linux;
  }
  return null;
}

Future<String> _get(Uri uri, {required bool api}) async {
  final client = HttpClient();
  client.connectionTimeout = const Duration(seconds: 20);
  try {
    final request = await client.getUrl(uri);
    request.followRedirects = true;
    request.maxRedirects = 5;
    request.headers.set(HttpHeaders.userAgentHeader, 'Twine');
    if (api) {
      request.headers.set(
        HttpHeaders.acceptHeader,
        'application/vnd.github+json',
      );
    }
    final response = await request.close();
    final body = await response.transform(utf8.decoder).join();
    if (response.statusCode == HttpStatus.notFound) {
      throw UpdateException('No release has been published yet.');
    }
    if (response.statusCode != HttpStatus.ok) {
      throw UpdateException(
        'Could not reach the release server (${response.statusCode}).',
      );
    }
    return body;
  } on UpdateException {
    rethrow;
  } on SocketException {
    throw UpdateException('Could not reach the release server.');
  } catch (_) {
    throw UpdateException('Could not reach the release server.');
  } finally {
    client.close(force: true);
  }
}

Future<void> _installAndroid(String path) async {
  try {
    await _androidChannel.invokeMethod<void>('installApk', {'path': path});
  } on MissingPluginException {
    throw UpdateException('This build cannot open the installer.');
  } on PlatformException catch (error) {
    if ((error.message ?? '').contains('Allow installs')) {
      throw UpdateException(
        'Allow installs from Twine, then try the update again.',
      );
    }
    throw UpdateException('Could not open the installer.');
  } catch (_) {
    throw UpdateException('Could not open the installer.');
  }
}

Future<void> _relaunch(
  String script,
  String archive, {
  bool powershell = false,
}) async {
  final directory = await getTemporaryDirectory();
  final file = File(
    '${directory.path}/updates/twine-update.${powershell ? 'ps1' : 'sh'}',
  );
  await file.parent.create(recursive: true);
  await file.writeAsString(script);
  if (!powershell) {
    final chmod = await Process.run('chmod', ['700', file.path]);
    if (chmod.exitCode != 0) {
      throw UpdateException('Could not prepare the installer.');
    }
  }
  final exe = Platform.resolvedExecutable;
  try {
    await Process.start(
      powershell ? 'powershell' : '/bin/sh',
      powershell
          ? [
              '-NoProfile',
              '-ExecutionPolicy',
              'Bypass',
              '-File',
              file.path,
              '$pid',
              exe,
              archive,
            ]
          : [file.path, '$pid', exe, archive],
      mode: ProcessStartMode.detached,
    );
  } catch (_) {
    throw UpdateException('Could not start the installer.');
  }
  exit(0);
}

const _linuxScript = r'''#!/bin/sh
set -eu
wait_pid=$1
exe=$2
archive=$3
while kill -0 "$wait_pid" 2>/dev/null; do
  sleep 0.4
done
dir=$(dirname "$exe")
tmp=$(mktemp -d)
tar -xzf "$archive" -C "$tmp"
if [ -d "$tmp/Twine" ]; then
  cp -a "$tmp/Twine/." "$dir/"
else
  cp -a "$tmp/." "$dir/"
fi
rm -rf "$tmp"
"$exe" >/dev/null 2>&1 &
''';

const _macosScript = r'''#!/bin/sh
set -eu
wait_pid=$1
exe=$2
dmg=$3
while kill -0 "$wait_pid" 2>/dev/null; do
  sleep 0.4
done
xattr -d com.apple.quarantine "$dmg" 2>/dev/null || true
app=$(cd "$(dirname "$exe")/../.." && pwd)
parent=$(dirname "$app")
mountpoint=$(mktemp -d)
if hdiutil attach "$dmg" -nobrowse -mountpoint "$mountpoint"; then
  if cp -R "$mountpoint/Twine.app" "$parent/"; then
    hdiutil detach "$mountpoint" || true
    rmdir "$mountpoint" 2>/dev/null || true
    open "$parent/Twine.app"
    exit 0
  fi
  hdiutil detach "$mountpoint" || true
fi
rmdir "$mountpoint" 2>/dev/null || true
open "$dmg"
''';

const _windowsScript = r'''
param(
  [Parameter(Mandatory=$true)][int]$WaitPid,
  [Parameter(Mandatory=$true)][string]$Exe,
  [Parameter(Mandatory=$true)][string]$Zip
)
while (Get-Process -Id $WaitPid -ErrorAction SilentlyContinue) {
  Start-Sleep -Milliseconds 400
}
Unblock-File -Path $Zip -ErrorAction SilentlyContinue
$dir = Split-Path -Parent $Exe
tar -xf $Zip -C $dir
Start-Process -FilePath $Exe
''';
