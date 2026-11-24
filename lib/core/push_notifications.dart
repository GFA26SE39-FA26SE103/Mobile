import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Validated data shared by foreground, background-tap and cold-start push flows.
class PushPayload {
  const PushPayload({
    required this.notificationId,
    required this.type,
    required this.route,
    required this.title,
    required this.body,
  });

  final String notificationId;
  final String type;
  final String route;
  final String title;
  final String body;

  String get channelId {
    if (type == 'TASK_OFFER' || type == 'EVENT_ESCALATED') {
      return 'task_offers';
    }
    if (type.startsWith('SHIFT_') || type.startsWith('SWAP_')) {
      return 'shifts_swaps';
    }
    return 'task_updates';
  }

  static PushPayload? tryParse({
    required Map<String, dynamic> data,
    required String? title,
    required String? body,
  }) {
    final id = data['notificationId']?.toString().trim() ?? '';
    final type = data['type']?.toString().trim().toUpperCase() ?? '';
    final route = data['route']?.toString().trim() ?? '';
    if (id.isEmpty || type.isEmpty || !route.startsWith('/')) return null;
    // Data-only task offers carry their text in data so the app can build a wake-screen notification.
    title ??= data['title']?.toString();
    body ??= data['body']?.toString();
    return PushPayload(
      notificationId: id,
      type: type,
      route: route,
      title: (title?.trim().isNotEmpty ?? false)
          ? title!.trim()
          : 'Supermarket update',
      body: body?.trim() ?? '',
    );
  }
}

/// Provider-neutral messaging surface. The default implementation is a no-op,
/// so builds without Firebase configuration remain safe and testable.
abstract class PushMessaging {
  bool get configured;
  Stream<String> get registrationRefreshes;
  Stream<PushPayload> get foregroundMessages;
  Stream<String> get openedRoutes;
  Future<void> requestPermission();
  Future<void> register();
  Future<String?> initialRoute();
}

class NoopPushMessaging implements PushMessaging {
  const NoopPushMessaging();

  @override
  bool get configured => false;
  @override
  Stream<String> get registrationRefreshes => const Stream.empty();
  @override
  Stream<PushPayload> get foregroundMessages => const Stream.empty();
  @override
  Stream<String> get openedRoutes => const Stream.empty();
  @override
  Future<void> register() async {}
  @override
  Future<String?> initialRoute() async => null;
  @override
  Future<void> requestPermission() async {}
}

/// The server does not know the stored device id (another server or another account).
class DeviceRegistrationNotFound implements Exception {
  const DeviceRegistrationNotFound();
}

abstract class DeviceRegistrationApi {
  Future<String> register({
    required String fcmToken,
    required String platform,
    String? deviceId,
  });
  Future<void> revoke(String deviceId);
}

class HttpDeviceRegistrationApi implements DeviceRegistrationApi {
  HttpDeviceRegistrationApi(this._dio);
  final Dio _dio;

  @override
  Future<String> register({
    required String fcmToken,
    required String platform,
    String? deviceId,
  }) async {
    final Response<Map<String, dynamic>> response;
    try {
      response = await _dio.post<Map<String, dynamic>>(
        '/api/me/devices',
        data: {'fcmToken': fcmToken, 'platform': platform, 'deviceId': ?deviceId},
      );
    } on DioException catch (error) {
      if (deviceId != null && error.response?.statusCode == 404) throw const DeviceRegistrationNotFound();
      rethrow;
    }
    final registered = response.data?['deviceId']?.toString();
    if (registered == null || registered.isEmpty) {
      throw const FormatException(
        'Device registration response has no deviceId.',
      );
    }
    return registered;
  }

  @override
  Future<void> revoke(String deviceId) =>
      _dio.delete<void>('/api/me/devices/$deviceId');
}

/// Keeps the backend device id (per signed-in account) and the last push target this
/// installation received from Firebase (per installation, kept across sign-outs).
abstract class DeviceIdentityStore {
  Future<String?> read();
  Future<void> write(String value);
  Future<void> clear();
  Future<String?> readToken();
  Future<void> writeToken(String value);
}

class SecureDeviceIdentityStore implements DeviceIdentityStore {
  SecureDeviceIdentityStore([FlutterSecureStorage? storage])
    : _storage = storage ?? const FlutterSecureStorage();
  final FlutterSecureStorage _storage;
  static const _key = 'push.device-id';
  static const _tokenKey = 'push.target';

  @override
  Future<String?> read() => _read(_key);

  @override
  Future<void> write(String value) => _write(_key, value);

  @override
  Future<String?> readToken() => _read(_tokenKey);

  @override
  Future<void> writeToken(String value) => _write(_tokenKey, value);

  Future<String?> _read(String key) async {
    try {
      return await _storage.read(key: key);
    } catch (_) {
      return null;
    }
  }

  Future<void> _write(String key, String value) async {
    try {
      await _storage.write(key: key, value: value);
    } catch (_) {
      // Registration can retry after the next token refresh or app launch.
    }
  }

  @override
  Future<void> clear() async {
    try {
      await _storage.delete(key: _key);
    } catch (_) {
      // Nothing local to clear when the keystore is unavailable.
    }
  }
}

/// Registers the installation after authentication, serializes token rotation,
/// and revokes only on explicit logout.
class PushRegistration {
  PushRegistration({
    required this.messaging,
    required this.api,
    required this.identityStore,
    required this.platform,
  });

  final PushMessaging messaging;
  final DeviceRegistrationApi api;
  final DeviceIdentityStore identityStore;
  final String platform;
  StreamSubscription<String>? _refresh;
  Future<void> _pending = Future.value();
  bool _started = false;

  /// What the Me screen shows, so a tester can see whether this phone can receive push.
  final status = ValueNotifier<PushStatus>(PushStatus.idle);

  Future<void> start() async {
    if (!messaging.configured) {
      status.value = PushStatus.notConfigured;
      return;
    }
    if (_started) return;
    _started = true;
    status.value = PushStatus.registering;
    try {
      _refresh = messaging.registrationRefreshes.listen(_queueRegistration);
      // Firebase reports the push target only when it changes, so an installation that was
      // registered before (another account, an earlier launch) would never be sent again.
      // Re-send the last known target for whoever is signed in now.
      final known = await identityStore.readToken();
      if (known != null && known.isNotEmpty) _queueRegistration(known);
      await messaging.requestPermission();
      await messaging.register();
    } catch (error) {
      debugPrint('Push registration unavailable: ${error.runtimeType}');
      status.value = PushStatus.failed;
    }
  }

  void _queueRegistration(String token) {
    _pending = _pending.then((_) => _register(token)).then((_) {
      status.value = PushStatus.registered;
    }).catchError((Object error) {
      debugPrint('Push token refresh failed: ${error.runtimeType}');
      status.value = PushStatus.failed;
    });
  }

  Future<void> _register(String token) async {
    await identityStore.writeToken(token);
    final existing = await identityStore.read();
    String deviceId;
    try {
      deviceId = await api.register(fcmToken: token, platform: platform, deviceId: existing);
    } on DeviceRegistrationNotFound {
      // The stored id belongs to another server (e.g. an earlier build on the dev API) or to
      // another account. Forget it and register this installation afresh.
      await identityStore.clear();
      deviceId = await api.register(fcmToken: token, platform: platform);
    }
    await identityStore.write(deviceId);
  }

  Future<void> revoke() async {
    final deviceId = await identityStore.read();
    try {
      if (deviceId != null) await api.revoke(deviceId);
    } catch (error) {
      // Logout must still complete when the network is unavailable. The server
      // also revokes invalid registration tokens after provider rejection.
      debugPrint('Push device revoke failed: ${error.runtimeType}');
    } finally {
      await identityStore.clear();
    }
  }

  Future<void> dispose() async {
    _started = false;
    await _refresh?.cancel();
    _refresh = null;
    await _pending;
    if (status.value != PushStatus.notConfigured) status.value = PushStatus.idle;
  }
}

enum PushStatus {
  idle('Starts after sign-in'),
  notConfigured('Off: this build has no Firebase configuration'),
  registering('Registering this phone with the server…'),
  registered('On: this phone receives task offers when the app is closed'),
  failed('Not registered: notifications appear only while the app runs');

  const PushStatus(this.label);
  final String label;
}
