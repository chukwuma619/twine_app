/// Compile-time Firebase options. Empty dart-defines leave the native
/// `google-services.json` / `GoogleService-Info.plist` path.
class PushFirebaseOptions {
  const PushFirebaseOptions({
    required this.apiKey,
    required this.appId,
    required this.messagingSenderId,
    required this.projectId,
  });

  static const apiKeyDefine = String.fromEnvironment('FIREBASE_API_KEY');
  static const appIdDefine = String.fromEnvironment('FIREBASE_APP_ID');
  static const senderIdDefine = String.fromEnvironment(
    'FIREBASE_MESSAGING_SENDER_ID',
  );
  static const projectIdDefine = String.fromEnvironment('FIREBASE_PROJECT_ID');

  final String apiKey;
  final String appId;
  final String messagingSenderId;
  final String projectId;

  static PushFirebaseOptions? fromEnvironment() {
    if (apiKeyDefine.isEmpty ||
        appIdDefine.isEmpty ||
        senderIdDefine.isEmpty ||
        projectIdDefine.isEmpty) {
      return null;
    }
    return const PushFirebaseOptions(
      apiKey: apiKeyDefine,
      appId: appIdDefine,
      messagingSenderId: senderIdDefine,
      projectId: projectIdDefine,
    );
  }

  bool get usable =>
      apiKey.isNotEmpty &&
      appId.isNotEmpty &&
      messagingSenderId.isNotEmpty &&
      projectId.isNotEmpty;
}
