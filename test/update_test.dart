import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twine_app/update/release.dart';
import 'package:twine_app/update/update_client.dart';
import 'package:twine_app/update/update_controller.dart';
import 'package:twine_app/update/update_panel.dart';
import 'package:twine_app/update/version.dart';

void main() {
  test('versions compare major minor and patch', () {
    final current = AppVersion.parse('v1.0.8');
    final same = AppVersion.parse('1.0.8+10');
    final next = AppVersion.parse('1.0.9');
    final older = AppVersion.parse('1.0.7');
    expect(current, isNotNull);
    expect(same, isNotNull);
    expect(next, isNotNull);
    expect(current!.isNewerThan(same!), isFalse);
    expect(same.isNewerThan(current), isFalse);
    expect(next!.isNewerThan(current), isTrue);
    expect(older!.isNewerThan(current), isFalse);
    expect(AppVersion.parse('1.0'), isNull);
    expect(AppVersion.parse('preview-1.0.8-3'), isNull);
  });

  test('a release offers the asset for this computer', () {
    final release = PublishedRelease.parse(_releaseJson);
    expect(release?.version, '1.0.9');
    expect(release?.prerelease, isFalse);
    expect(
      release?.assetFor(UpdateTarget.android)?.name,
      'Twine-1.0.9-android.apk',
    );
    expect(
      release?.assetFor(UpdateTarget.macos)?.url,
      'https://example.com/Twine-1.0.9-macos.dmg',
    );
    expect(release?.assetFor(UpdateTarget.linux), isNotNull);
    expect(PublishedRelease.parse('not json'), isNull);
  });

  test('a newer release is offered and an older one is not', () async {
    final newer = UpdateController(
      client: _Client(PublishedRelease.parse(_releaseJson)),
    );
    await newer.check();
    expect(newer.phase, UpdatePhase.available);
    expect(newer.offer, isTrue);
    expect(newer.version, '1.0.8');

    final current = UpdateController(
      client: _Client(PublishedRelease.parse(_releaseJson), version: '1.0.9'),
    );
    await current.check();
    expect(current.phase, UpdatePhase.upToDate);
    expect(current.offer, isFalse);
  });

  test('a missing build is reported when the check is manual', () async {
    final release = PublishedRelease(
      version: '1.2.0',
      tag: 'v1.2.0',
      prerelease: false,
      assets: const [],
    );
    final controller = UpdateController(client: _Client(release));
    await controller.check();
    expect(controller.phase, UpdatePhase.idle);

    await controller.check(manual: true);
    expect(controller.phase, UpdatePhase.failed);
    expect(controller.error, 'This release has no build for this computer.');
  });

  testWidgets('the update bar can be dismissed', (tester) async {
    final controller = UpdateController(
      client: _Client(PublishedRelease.parse(_releaseJson)),
    );
    await controller.check();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: UpdateBanner(controller: controller)),
      ),
    );

    expect(find.text('Twine 1.0.9 is available.'), findsOneWidget);
    await tester.tap(find.text('Later'));
    await tester.pump();
    expect(find.text('Twine 1.0.9 is available.'), findsNothing);
    expect(controller.dismissed, isTrue);
  });
}

const _releaseJson = '''
{
  "tag_name": "v1.0.9",
  "prerelease": false,
  "draft": false,
  "body": "Fixes",
  "assets": [
    {
      "name": "Twine-1.0.9-android.apk",
      "browser_download_url": "https://example.com/Twine-1.0.9-android.apk",
      "size": 10
    },
    {
      "name": "Twine-1.0.9-macos.dmg",
      "browser_download_url": "https://example.com/Twine-1.0.9-macos.dmg",
      "size": 10
    },
    {
      "name": "Twine-1.0.9-windows-x64.zip",
      "browser_download_url": "https://example.com/Twine-1.0.9-windows-x64.zip",
      "size": 10
    },
    {
      "name": "Twine-1.0.9-linux-x64.tar.gz",
      "browser_download_url": "https://example.com/Twine-1.0.9-linux-x64.tar.gz",
      "size": 10
    }
  ]
}
''';

class _Client implements UpdateClient {
  _Client(
    this.release, {
    this.version = '1.0.8',
    this.platform = UpdateTarget.macos,
  });

  final String version;
  final UpdateTarget? platform;
  final PublishedRelease? release;

  @override
  UpdateTarget? get target => platform;

  @override
  Future<String> currentVersion() async => version;

  @override
  Future<PublishedRelease?> latest() async => release;

  @override
  Future<String> download(
    ReleaseAsset asset,
    void Function(double? progress) onProgress,
  ) async {
    onProgress(1);
    return '/tmp/${asset.name}';
  }

  @override
  Future<void> install(UpdateTarget target, String path) async {}
}
