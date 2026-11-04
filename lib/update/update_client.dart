import 'release.dart';
import 'version.dart';

/// Reads the current build and installs a newer GitHub release.
abstract class UpdateClient {
  UpdateTarget? get target;

  Future<String> currentVersion();

  Future<PublishedRelease?> latest();

  /// Downloads [asset] and returns the local file path.
  Future<String> download(
    ReleaseAsset asset,
    void Function(double? progress) onProgress,
  );

  /// Hands [path] to the operating system. Desktop installs quit the app.
  Future<void> install(UpdateTarget target, String path);
}

/// Repository that publishes tester builds. See `tool/release.sh`.
const updateRepository = 'chukwuma619/twine_app';

Uri latestReleaseUri([String repository = updateRepository]) {
  return Uri.https('api.github.com', '/repos/$repository/releases/latest');
}
