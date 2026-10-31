import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import 'push_notifications.dart';

/// Firebase client values are injected at build time. They identify the Firebase
/// app but must still be supplied per environment; no project config is committed.
class FirebasePushConfig {
  const FirebasePushConfig({
    required this.apiKey,
    required this.appId,
    required this.messagingSenderId,
    required this.projectId,
  });

  static const fromEnvironment = FirebasePushConfig(
    apiKey: String.fromEnvironment('FIREBASE_API_KEY'),
    appId: String.fromEnvironment('FIREBASE_APP_ID'),
    messagingSenderId: String.fromEnvironment('FIREBASE_MESSAGING_SENDER_ID'),
    projectId: String.fromEnvironment('FIREBASE_PROJECT_ID'),
  );

  final String apiKey;
  final String appId;
  final String messagingSenderId;
  final String projectId;

  bool get configured =>
      apiKey.isNotEmpty &&
      appId.isNotEmpty &&
      messagingSenderId.isNotEmpty &&
      projectId.isNotEmpty;

  FirebaseOptions get options => FirebaseOptions(
    apiKey: apiKey,
    appId: appId,
    messagingSenderId: messagingSenderId,
    projectId: projectId,
  );
}

Future<PushMessaging> createFirebasePushMessaging([
  FirebasePushConfig config = FirebasePushConfig.fromEnvironment,
]) async {
  if (!config.configured || kIsWeb) return const NoopPushMessaging();
  try {
    await Firebase.initializeApp(options: config.options);
    return FirebasePushMessaging(FirebaseMessaging.instance);
  } catch (error) {
    debugPrint('Firebase messaging unavailable: ${error.runtimeType}');
    return const NoopPushMessaging();
  }
}

class FirebasePushMessaging implements PushMessaging {
  FirebasePushMessaging(this._messaging);
  final FirebaseMessaging _messaging;

  @override
  bool get configured => true;

  @override
  Stream<String> get registrationRefreshes => _messaging.onRegistered;

  @override
  Stream<PushPayload> get foregroundMessages => FirebaseMessaging.onMessage
      .map(_payload)
      .where((payload) => payload != null)
      .cast<PushPayload>();

  @override
  Stream<String> get openedRoutes => FirebaseMessaging.onMessageOpenedApp
      .map((message) => _payload(message)?.route)
      .where((route) => route != null)
      .cast<String>();

  @override
  Future<void> requestPermission() => _messaging
      .requestPermission(alert: true, badge: true, sound: true)
      .then((_) {});

  @override
  Future<void> register() => _messaging.register();

  @override
  Future<String?> initialRoute() async =>
      _payload(await _messaging.getInitialMessage())?.route;

  static PushPayload? _payload(RemoteMessage? message) {
    if (message == null) return null;
    return PushPayload.tryParse(
      data: message.data,
      title: message.notification?.title,
      body: message.notification?.body,
    );
  }
}
