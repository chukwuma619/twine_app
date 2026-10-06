import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Keychain on Apple platforms, Keystore-backed storage on Android.
FlutterSecureStorage twineSecureStorage() {
  if (defaultTargetPlatform == TargetPlatform.macOS) {
    return const FlutterSecureStorage(
      mOptions: MacOsOptions(usesDataProtectionKeychain: false),
    );
  }
  return const FlutterSecureStorage();
}
