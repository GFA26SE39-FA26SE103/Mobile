import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/auth/auth_controller.dart';
import '../features/auth/auth_repository.dart';
import 'config.dart';
import 'device_notifications.dart';
import 'push_notifications.dart';

/// Wall clock, overridable in tests.
final clockProvider = Provider<DateTime Function()>((ref) => DateTime.now);

final dioProvider = Provider<Dio>((ref) {
  final dio = Dio(
    BaseOptions(
      baseUrl: AppConfig.apiUrl,
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 20),
      headers: {'Accept': 'application/json'},
    ),
  );
  dio.interceptors.add(
    InterceptorsWrapper(
      onRequest: (options, handler) {
        final token = ref.read(authControllerProvider).session?.accessToken;
        if (token != null && !options.headers.containsKey('Authorization')) {
          options.headers['Authorization'] = 'Bearer $token';
        }
        handler.next(options);
      },
      onError: (error, handler) {
        // An expired or revoked token ends the session; the router then shows Session expired.
        final isLogin = error.requestOptions.path.endsWith('/api/auth/login');
        if (error.response?.statusCode == 401 && !isLogin) {
          ref.read(authControllerProvider.notifier).expire();
        }
        handler.next(error);
      },
    ),
  );
  return dio;
});

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  if (AppConfig.mockAuth) {
    return MockAuthRepository(now: ref.watch(clockProvider));
  }
  return HttpAuthRepository(ref.watch(dioProvider));
});

final sessionStoreProvider = Provider<SessionStore>((ref) => SessionStore());

/// The phone's notification shade; tests replace it with [NoopDeviceNotifier].
final deviceNotifierProvider = Provider<DeviceNotifier>(
  (ref) => LocalDeviceNotifier(),
);

/// Overridden by [main] after Firebase is initialized. Missing configuration is
/// intentionally a no-op rather than a fake token or demo delivery path.
final pushMessagingProvider = Provider<PushMessaging>(
  (ref) => const NoopPushMessaging(),
);

final deviceRegistrationApiProvider = Provider<DeviceRegistrationApi>(
  (ref) => HttpDeviceRegistrationApi(ref.watch(dioProvider)),
);
final deviceIdentityStoreProvider = Provider<DeviceIdentityStore>(
  (ref) => SecureDeviceIdentityStore(),
);

final pushRegistrationProvider = Provider<PushRegistration>((ref) {
  final registration = PushRegistration(
    messaging: ref.watch(pushMessagingProvider),
    api: ref.watch(deviceRegistrationApiProvider),
    identityStore: ref.watch(deviceIdentityStoreProvider),
    platform: defaultTargetPlatform == TargetPlatform.iOS ? 'IOS' : 'ANDROID',
  );
  ref.onDispose(() => registration.dispose());
  return registration;
});
