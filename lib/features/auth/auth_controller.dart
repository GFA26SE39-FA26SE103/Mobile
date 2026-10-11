import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_exception.dart';
import '../../core/providers.dart';
import 'auth_models.dart';

sealed class AuthState {
  const AuthState();
  AuthSession? get session => null;
}

/// Reading a remembered session from the keystore at launch.
class AuthRestoring extends AuthState {
  const AuthRestoring();
}

class SignedOut extends AuthState {
  const SignedOut({this.email});
  final String? email;
}

class SignedIn extends AuthState {
  const SignedIn(this._session);
  final AuthSession _session;
  @override
  AuthSession get session => _session;
}

/// The token expired or was rejected; the user can sign in again as the same person.
class SessionExpired extends AuthState {
  const SessionExpired(this.user);
  final AuthUser user;
}

/// The three real steps behind the "Signing in…" screen.
enum SignInStage { credentials, permissions, session }

final authControllerProvider = NotifierProvider<AuthController, AuthState>(AuthController.new);

class AuthController extends Notifier<AuthState> {
  Timer? _expiryTimer;

  @override
  AuthState build() {
    ref.onDispose(() => _expiryTimer?.cancel());
    Future.microtask(_restore);
    return const AuthRestoring();
  }

  DateTime _now() => ref.read(clockProvider)().toUtc();

  Future<void> _restore() async {
    final saved = await ref.read(sessionStoreProvider).read();
    if (saved == null) {
      state = const SignedOut();
      return;
    }
    if (saved.isExpiredAt(_now())) {
      await ref.read(sessionStoreProvider).clear();
      state = SessionExpired(saved.user);
      return;
    }
    _enter(saved);
    // Re-check the account in the background; a 401 ends the session via the API interceptor.
    try {
      final user = await ref.read(authRepositoryProvider).me(saved.accessToken);
      if (state is! SignedIn) return;
      if (!user.isStaff || !user.isActive) {
        await signOut();
      } else {
        state = SignedIn(saved.withUser(user));
      }
    } on ApiException catch (e) {
      if (e.status == 401) expire();
    }
  }

  /// Signs in and reports each stage so the UI can show real progress.
  Future<void> signIn({
    required String email,
    required String password,
    required bool remember,
    void Function(SignInStage stage)? onStage,
  }) async {
    final repo = ref.read(authRepositoryProvider);
    try {
      onStage?.call(SignInStage.credentials);
      final session = await repo.login(email.trim(), password);
      onStage?.call(SignInStage.permissions);
      final user = await repo.me(session.accessToken);
      if (!user.isActive) throw const SignInFailure('This account is disabled. Contact your shift manager.');
      if (!user.isStaff) {
        throw SignInFailure('This app is for store staff. ${_roleName(user.role)} accounts use the web console.');
      }
      onStage?.call(SignInStage.session);
      final verified = session.withUser(user);
      final store = ref.read(sessionStoreProvider);
      if (remember) {
        await store.write(verified);
      } else {
        await store.clear();
      }
      _enter(verified);
    } on ApiException catch (e) {
      throw SignInFailure(_messageFor(e));
    }
  }

  void expire() {
    final current = state;
    if (current is! SignedIn) return;
    _expiryTimer?.cancel();
    unawaited(ref.read(sessionStoreProvider).clear());
    state = SessionExpired(current.session.user);
  }

  Future<void> signOut() async {
    _expiryTimer?.cancel();
    final email = state is SignedIn ? state.session!.user.email : null;
    await ref.read(sessionStoreProvider).clear();
    state = SignedOut(email: email);
  }

  void _enter(AuthSession session) {
    _expiryTimer?.cancel();
    final left = session.expiresAt.difference(_now());
    _expiryTimer = Timer(left.isNegative ? Duration.zero : left, expire);
    state = SignedIn(session);
  }

  static String _roleName(String role) => role.isEmpty ? role : role[0] + role.substring(1).toLowerCase();

  static String _messageFor(ApiException e) {
    if (e.isNetwork) return e.message;
    if (e.status == 429) return 'Too many attempts. Wait a few minutes, then try again.';
    if (e.code == 'ACCOUNT_DISABLED') return 'This account is disabled. Contact your shift manager.';
    if (e.status == 401 || e.code == 'INVALID_CREDENTIALS') return 'Email or password is incorrect.';
    if (e.status == 400) return 'Enter a valid email and password.';
    return 'Sign-in failed (${e.status}). Try again in a moment.';
  }
}
