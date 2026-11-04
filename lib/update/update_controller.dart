import 'package:flutter/foundation.dart';

import 'release.dart';
import 'update_client.dart';
import 'version.dart';

enum UpdatePhase {
  idle,
  checking,
  upToDate,
  available,
  downloading,
  installing,
  ready,
  failed,
  unsupported,
}

/// Checks GitHub for a newer tester build and installs it.
class UpdateController extends ChangeNotifier {
  UpdateController({required this.client});

  final UpdateClient client;

  UpdatePhase phase = UpdatePhase.idle;
  String? version;
  PublishedRelease? release;
  ReleaseAsset? asset;
  double? progress;
  String? error;
  bool dismissed = false;
  DateTime? _checkedAt;
  bool _disposed = false;

  static const quietFor = Duration(hours: 6);

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  @override
  void notifyListeners() {
    if (_disposed) return;
    super.notifyListeners();
  }

  bool get offer {
    switch (phase) {
      case UpdatePhase.available:
      case UpdatePhase.downloading:
      case UpdatePhase.installing:
      case UpdatePhase.ready:
        return !dismissed;
      case UpdatePhase.idle:
      case UpdatePhase.checking:
      case UpdatePhase.upToDate:
      case UpdatePhase.failed:
      case UpdatePhase.unsupported:
        return false;
    }
  }

  UpdateTarget? get target => client.target;

  /// [manual] reports a failure. A background check stays quiet when offline.
  Future<void> check({bool manual = false}) async {
    if (phase == UpdatePhase.downloading || phase == UpdatePhase.installing) {
      return;
    }
    final checked = _checkedAt;
    if (!manual &&
        checked != null &&
        DateTime.now().difference(checked) < quietFor &&
        phase != UpdatePhase.failed) {
      return;
    }
    final platform = client.target;
    if (platform == null) {
      phase = UpdatePhase.unsupported;
      error = null;
      notifyListeners();
      return;
    }
    final previous = phase;
    phase = UpdatePhase.checking;
    if (manual) error = null;
    notifyListeners();
    try {
      version = await client.currentVersion();
      final published = await client.latest();
      if (published == null) {
        throw UpdateException('Could not read the latest release.');
      }
      if (published.prerelease) {
        _checkedAt = DateTime.now();
        release = null;
        asset = null;
        phase = UpdatePhase.upToDate;
        error = null;
        return;
      }
      final current = AppVersion.parse(version!);
      final next = AppVersion.parse(published.version);
      if (current == null || next == null || !next.isNewerThan(current)) {
        _checkedAt = DateTime.now();
        release = published;
        asset = null;
        phase = UpdatePhase.upToDate;
        error = null;
        return;
      }
      final file = published.assetFor(platform);
      if (file == null) {
        throw UpdateException('This release has no build for this computer.');
      }
      _checkedAt = DateTime.now();
      release = published;
      asset = file;
      dismissed = false;
      phase = UpdatePhase.available;
      error = null;
    } on UpdateException catch (failure) {
      _keepOrFail(manual, previous, failure.message);
    } catch (_) {
      _keepOrFail(manual, previous, 'Could not check for an update.');
    } finally {
      notifyListeners();
    }
  }

  Future<void> downloadAndInstall() async {
    final file = asset;
    final platform = client.target;
    final published = release;
    if (file == null || platform == null || published == null) return;
    if (phase == UpdatePhase.downloading || phase == UpdatePhase.installing) {
      return;
    }
    phase = UpdatePhase.downloading;
    progress = null;
    error = null;
    notifyListeners();
    var last = -1.0;
    try {
      final path = await client.download(file, (value) {
        if (value != null && value < 1 && value - last < 0.02) return;
        last = value ?? last;
        progress = value;
        notifyListeners();
      });
      phase = UpdatePhase.installing;
      progress = 1;
      notifyListeners();
      await client.install(platform, path);
      phase = UpdatePhase.ready;
      error = null;
    } on UpdateException catch (failure) {
      phase = UpdatePhase.available;
      error = failure.message;
    } catch (_) {
      phase = UpdatePhase.available;
      error = 'Could not install the update.';
    } finally {
      notifyListeners();
    }
  }

  void dismiss() {
    dismissed = true;
    notifyListeners();
  }

  void _keepOrFail(bool manual, UpdatePhase previous, String message) {
    if (asset != null &&
        (previous == UpdatePhase.available || previous == UpdatePhase.ready)) {
      phase = previous;
      error = manual ? message : null;
      return;
    }
    if (manual) {
      phase = UpdatePhase.failed;
      error = message;
      return;
    }
    phase = UpdatePhase.idle;
    error = null;
  }
}
