import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supermarket_staff/core/providers.dart';
import 'package:supermarket_staff/features/auth/auth_controller.dart';
import 'package:supermarket_staff/features/auth/auth_models.dart';
import 'package:supermarket_staff/features/auth/auth_repository.dart';

import 'helpers.dart';

ProviderContainer containerWith(MemorySessionStore store) {
  final container = ProviderContainer(overrides: [
    sessionStoreProvider.overrideWithValue(store),
    authRepositoryProvider.overrideWithValue(MockAuthRepository()),
  ]);
  addTearDown(container.dispose);
  return container;
}

Future<AuthState> settled(ProviderContainer container) async {
  container.read(authControllerProvider);
  for (var i = 0; i < 20 && container.read(authControllerProvider) is AuthRestoring; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  return container.read(authControllerProvider);
}

void main() {
  test('a staff account signs in and the session is remembered', () async {
    final store = MemorySessionStore();
    final container = containerWith(store);
    expect(await settled(container), isA<SignedOut>());

    final stages = <SignInStage>[];
    await container.read(authControllerProvider.notifier).signIn(
          email: 'linh@store.test',
          password: MockAuthRepository.password,
          remember: true,
          onStage: stages.add,
        );

    expect(container.read(authControllerProvider), isA<SignedIn>());
    expect(stages, SignInStage.values);
    expect(store.saved?.user.role, 'STAFF');
  });

  test('a non-staff account is refused with a clear message and nothing is saved', () async {
    final store = MemorySessionStore();
    final container = containerWith(store);
    await settled(container);

    await expectLater(
      container.read(authControllerProvider.notifier).signIn(email: 'manager@store.test', password: MockAuthRepository.password, remember: true),
      throwsA(isA<SignInFailure>().having((e) => e.message, 'message', contains('Manager accounts use the web console'))),
    );
    expect(container.read(authControllerProvider), isA<SignedOut>());
    expect(store.saved, isNull);
  });

  test('a wrong password reads as incorrect credentials', () async {
    final container = containerWith(MemorySessionStore());
    await settled(container);
    await expectLater(
      container.read(authControllerProvider.notifier).signIn(email: 'linh@store.test', password: 'nope', remember: false),
      throwsA(isA<SignInFailure>().having((e) => e.message, 'message', 'Email or password is incorrect.')),
    );
  });

  test('a remembered session restores, and an expired one shows Session expired', () async {
    final valid = containerWith(MemorySessionStore(sessionFor(staffUser)));
    expect(await settled(valid), isA<SignedIn>());

    final expiredStore = MemorySessionStore(sessionFor(staffUser, validFor: const Duration(minutes: -1)));
    final expired = containerWith(expiredStore);
    final state = await settled(expired);
    expect(state, isA<SessionExpired>());
    expect((state as SessionExpired).user.email, staffUser.email);
    expect(expiredStore.saved, isNull);
  });

  test('a 401 during use ends the session but keeps who was signed in', () async {
    final container = containerWith(MemorySessionStore(sessionFor(staffUser)));
    await settled(container);
    container.read(authControllerProvider.notifier).expire();
    final state = container.read(authControllerProvider);
    expect(state, isA<SessionExpired>());
    expect((state as SessionExpired).user.fullName, 'Nguyễn Linh');
  });
}
