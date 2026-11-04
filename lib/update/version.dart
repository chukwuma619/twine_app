/// A published Twine version, `major.minor.patch`.
class AppVersion implements Comparable<AppVersion> {
  const AppVersion(this.major, this.minor, this.patch);

  final int major;
  final int minor;
  final int patch;

  /// Accepts `1.2.3` and `v1.2.3`. Build metadata after `+` is ignored.
  static AppVersion? parse(String raw) {
    var text = raw.trim();
    if (text.startsWith('v') || text.startsWith('V')) {
      text = text.substring(1);
    }
    final plus = text.indexOf('+');
    if (plus >= 0) text = text.substring(0, plus);
    final parts = text.split('.');
    if (parts.length != 3) return null;
    final major = int.tryParse(parts[0]);
    final minor = int.tryParse(parts[1]);
    final patch = int.tryParse(parts[2]);
    if (major == null || minor == null || patch == null) return null;
    if (major < 0 || minor < 0 || patch < 0) return null;
    return AppVersion(major, minor, patch);
  }

  bool isNewerThan(AppVersion other) => compareTo(other) > 0;

  @override
  int compareTo(AppVersion other) {
    if (major != other.major) return major.compareTo(other.major);
    if (minor != other.minor) return minor.compareTo(other.minor);
    return patch.compareTo(other.patch);
  }

  @override
  String toString() => '$major.$minor.$patch';
}

/// Where a tester build from the release workflow can be installed.
enum UpdateTarget { android, macos, windows, linux }

/// File name attached to a GitHub release by `.github/workflows/release.yml`.
String releaseAssetName(UpdateTarget target, String version) {
  switch (target) {
    case UpdateTarget.android:
      return 'Twine-$version-android.apk';
    case UpdateTarget.macos:
      return 'Twine-$version-macos.dmg';
    case UpdateTarget.windows:
      return 'Twine-$version-windows-x64.zip';
    case UpdateTarget.linux:
      return 'Twine-$version-linux-x64.tar.gz';
  }
}
