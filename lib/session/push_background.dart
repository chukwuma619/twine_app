import 'package:firebase_messaging/firebase_messaging.dart';

import 'push_wake.dart';

/// FCM background isolate. No Rust, no DB, no decrypt.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  onPushWake();
}

void onPushWake() {
  pushWake.note();
}
