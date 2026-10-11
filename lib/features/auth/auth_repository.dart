import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../core/api/api_exception.dart';
import 'auth_models.dart';

abstract class AuthRepository {
  Future<AuthSession> login(String email, String password);

  /// Re-reads the account behind [accessToken] (`GET /api/auth/me`).
  Future<AuthUser> me(String accessToken);
}

class HttpAuthRepository implements AuthRepository {
  HttpAuthRepository(this._dio);
  final Dio _dio;

  @override
  Future<AuthSession> login(String email, String password) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>('/api/auth/login', data: {'email': email, 'password': password});
      return AuthSession.fromJson(response.data!);
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  @override
  Future<AuthUser> me(String accessToken) async {
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        '/api/auth/me',
        options: Options(headers: {'Authorization': 'Bearer $accessToken'}),
      );
      return AuthUser.fromJson(response.data!);
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }
}

/// Offline sign-in for demos (`--dart-define=MOCK_AUTH=true`).
/// Password `staff123`; an email containing "manager" signs in as MANAGER so
/// the wrong-role path can be shown.
class MockAuthRepository implements AuthRepository {
  MockAuthRepository({DateTime Function()? now}) : _now = now ?? DateTime.now;
  final DateTime Function() _now;
  static const password = 'staff123';

  AuthUser _userFor(String email) => AuthUser(
        userId: 'demo-${email.hashCode.abs()}',
        email: email,
        fullName: email.contains('manager') ? 'Trần Minh' : 'Nguyễn Linh',
        role: email.contains('manager') ? 'MANAGER' : 'STAFF',
        status: 'ACTIVE',
      );

  @override
  Future<AuthSession> login(String email, String password) async {
    await Future<void>.delayed(const Duration(milliseconds: 500));
    if (password != MockAuthRepository.password) {
      throw const ApiException(status: 401, code: 'INVALID_CREDENTIALS', message: 'Invalid email or password.');
    }
    return AuthSession(
      accessToken: 'demo-token-$email',
      expiresAt: _now().toUtc().add(const Duration(hours: 8)),
      user: _userFor(email),
    );
  }

  @override
  Future<AuthUser> me(String accessToken) async {
    await Future<void>.delayed(const Duration(milliseconds: 300));
    return _userFor(accessToken.replaceFirst('demo-token-', ''));
  }
}

/// Keeps a remembered session in the platform keystore, never in plain prefs.
class SessionStore {
  SessionStore([FlutterSecureStorage? storage]) : _storage = storage ?? const FlutterSecureStorage();
  final FlutterSecureStorage _storage;
  static const _key = 'auth.session';

  Future<AuthSession?> read() async {
    try {
      final raw = await _storage.read(key: _key);
      return raw == null ? null : AuthSession.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      await clear();
      return null;
    }
  }

  Future<void> write(AuthSession session) => _storage.write(key: _key, value: jsonEncode(session.toJson()));

  Future<void> clear() async {
    try {
      await _storage.delete(key: _key);
    } catch (_) {
      // Nothing to clear when the keystore is unavailable.
    }
  }
}
