import 'dart:convert';

import 'version.dart';

class UpdateException implements Exception {
  UpdateException(this.message);

  final String message;

  @override
  String toString() => message;
}

class ReleaseAsset {
  const ReleaseAsset({required this.name, required this.url, this.size = 0});

  final String name;
  final String url;
  final int size;
}

/// One GitHub release, reduced to the fields the updater needs.
class PublishedRelease {
  const PublishedRelease({
    required this.version,
    required this.tag,
    required this.prerelease,
    required this.assets,
    this.notes,
  });

  final String version;
  final String tag;
  final bool prerelease;
  final String? notes;
  final List<ReleaseAsset> assets;

  ReleaseAsset? assetFor(UpdateTarget target) {
    final name = releaseAssetName(target, version);
    for (final asset in assets) {
      if (asset.name == name) return asset;
    }
    return null;
  }

  /// Parses the body of `GET /repos/{owner}/{repo}/releases/latest`.
  static PublishedRelease? parse(String body) {
    final Object? decoded;
    try {
      decoded = jsonDecode(body);
    } catch (_) {
      return null;
    }
    if (decoded is! Map) return null;
    final map = decoded.map((key, value) => MapEntry('$key', value));
    if (map['draft'] == true) return null;
    final tag = _text(map['tag_name']);
    if (tag == null) return null;
    final version = AppVersion.parse(tag);
    if (version == null) return null;
    final assets = <ReleaseAsset>[];
    final listed = map['assets'];
    if (listed is List) {
      for (final item in listed) {
        if (item is! Map) continue;
        final asset = item.map((key, value) => MapEntry('$key', value));
        final name = _text(asset['name']);
        final url = _text(asset['browser_download_url']);
        if (name == null || url == null) continue;
        final size = asset['size'];
        assets.add(
          ReleaseAsset(name: name, url: url, size: size is int ? size : 0),
        );
      }
    }
    final notes = _text(map['body']);
    return PublishedRelease(
      version: version.toString(),
      tag: tag,
      prerelease: map['prerelease'] == true,
      notes: notes,
      assets: assets,
    );
  }
}

String? _text(Object? value) {
  if (value is! String) return null;
  final trimmed = value.trim();
  if (trimmed.isEmpty) return null;
  return trimmed;
}
