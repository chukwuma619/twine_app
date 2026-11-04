import 'release.dart';
import 'update_client.dart';
import 'version.dart';

UpdateClient createPlatformUpdateClient() => const _StubUpdateClient();

class _StubUpdateClient implements UpdateClient {
  const _StubUpdateClient();

  @override
  UpdateTarget? get target => null;

  @override
  Future<String> currentVersion() {
    throw UpdateException('Updates are not available here.');
  }

  @override
  Future<PublishedRelease?> latest() async => null;

  @override
  Future<String> download(
    ReleaseAsset asset,
    void Function(double? progress) onProgress,
  ) {
    throw UpdateException('Updates are not available here.');
  }

  @override
  Future<void> install(UpdateTarget target, String path) {
    throw UpdateException('Updates are not available here.');
  }
}
