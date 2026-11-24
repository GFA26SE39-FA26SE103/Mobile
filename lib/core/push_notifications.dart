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
    final response = await _dio.post<Map<String, dynamic>>(
      '/api/me/devices',
      data: {'fcmToken': fcmToken, 'platform': platform, 'deviceId': ?deviceId},
    );
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

abstract class DeviceIdentityStore {
  Future<String?> read();
  Future<void> write(String value);
  Future<void> clear();
}

class SecureDeviceIdentityStore implements DeviceIdentityStore {
  SecureDeviceIdentityStore([FlutterSecureStorage? storage])
    : _storage = storage ?? const FlutterSecureStorage();
  final FlutterSecureStorage _storage;
  static const _key = 'push.device-id';

  @override
  Future<String?> read() async {
    try {
      return await _storage.read(key: _key);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> write(String value) async {
    try {
      await _storage.write(key: _key, value: value);
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

  Future<void> start() async {
    if (_started || !messaging.configured) return;
    _started = true;
    try {
      _refresh = messaging.registrationRefreshes.listen(_queueRegistration);
      await messaging.requestPermission();
      await messaging.register();
    } catch (error) {
      debugPrint('Push registration unavailable: ${error.runtimeType}');
    }
  }

  void _queueRegistration(String token) {
    _pending = _pending.then((_) => _register(token)).catchError((
      Object error,
    ) {
      debugPrint('Push token refresh failed: ${error.runtimeType}');
    });
  }

  Future<void> _register(String token) async {
    final existing = await identityStore.read();
    final deviceId = await api.register(
      fcmToken: token,
      platform: platform,
      deviceId: existing,
    );
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
  }
}
