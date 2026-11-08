import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:twine_app/nostr/daemon.dart';
import 'package:twine_app/nostr/twine_nostr.dart';

import 'push_background.dart';
import 'push_options.dart';

/// Registers this device with twine-push. The FID handoff is content-free.
class PushService {
  static const pushUrl = officialPushUrl;

  /// Firebase Installation ID uploaded to twine-push for FCM `fid` targeting.
  static String? token;
  static TwineNostr? _nostr;
  static var _started = false;
  static void Function()? onForegroundWake;

  /// Asks Firebase for an installation id, then registers it. No-ops in tests
  /// and on builds that have no Firebase project files or dart-defines.
  static Future<void> start(TwineNostr nostr) async {
    _nostr = nostr;
    if (!_started) {
      _started = true;
      await _initFirebase();
    }
    await attach(nostr);
  }

  static Future<void> attach(TwineNostr nostr) async {
    _nostr = nostr;
    final current = token;
    if (pushUrl.isEmpty || current == null || current.isEmpty) return;
    try {
      await nostr.setPushToken(url: pushUrl, token: current);
    } catch (_) {}
  }

  static Future<void> detach(TwineNostr nostr) async {
    _nostr = nostr;
    if (pushUrl.isEmpty) return;
    try {
      await nostr.setPushToken(url: pushUrl, token: '');
    } catch (_) {}
  }

  static Future<void> _initFirebase() async {
    if (kIsWeb) return;
    try {
      await _ensureFirebase();
      FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
      final messaging = FirebaseMessaging.instance;
      await messaging.requestPermission(
        alert: false,
        badge: false,
        sound: false,
        announcement: false,
        carPlay: false,
        criticalAlert: false,
        provisional: true,
      );
      // FCM targets a Firebase Installation ID. Listen before register() so the
      // first onRegistered delivery is not missed.
      messaging.onRegistered.listen(_onToken);
      await messaging.register();
      FirebaseMessaging.onMessage.listen(_onForeground);
      FirebaseMessaging.onMessageOpenedApp.listen(_onForeground);
      if (await messaging.getInitialMessage() != null) {
        onPushWake();
      }
    } catch (_) {}
  }

  static Future<void> _ensureFirebase() async {
    if (Firebase.apps.isNotEmpty) return;
    final defined = PushFirebaseOptions.fromEnvironment();
    if (defined != null) {
      await Firebase.initializeApp(
        options: FirebaseOptions(
          apiKey: defined.apiKey,
          appId: defined.appId,
          messagingSenderId: defined.messagingSenderId,
          projectId: defined.projectId,
        ),
      );
      return;
    }
    await Firebase.initializeApp();
  }

  static void _onToken(String value) {
    token = value;
    final nostr = _nostr;
    if (nostr != null) unawaited(attach(nostr));
  }

  static void _onForeground(RemoteMessage message) {
    onPushWake();
    onForegroundWake?.call();
  }
}
