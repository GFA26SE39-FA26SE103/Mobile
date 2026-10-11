import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supermarket_staff/app.dart';
import 'package:supermarket_staff/core/providers.dart';
import 'package:supermarket_staff/data/demo_operations_repository.dart';
import 'package:supermarket_staff/data/providers.dart';
import 'package:supermarket_staff/features/auth/auth_models.dart';
import 'package:supermarket_staff/features/auth/auth_repository.dart';

/// Session storage without the platform keystore.
class MemorySessionStore extends SessionStore {
  MemorySessionStore([this.saved]);
  AuthSession? saved;

  @override
  Future<AuthSession?> read() async => saved;
  @override
  Future<void> write(AuthSession session) async => saved = session;
  @override
  Future<void> clear() async => saved = null;
}

final staffUser = const AuthUser(
  userId: 'staff-1',
  email: 'linh@store.test',
  fullName: 'Nguyễn Linh',
  role: 'STAFF',
  status: 'ACTIVE',
);

AuthSession sessionFor(AuthUser user, {Duration validFor = const Duration(hours: 8)}) => AuthSession(
      accessToken: 'demo-token-${user.email}',
      expiresAt: DateTime.now().toUtc().add(validFor),
      user: user,
    );

DemoOperationsRepository fastDemoRepo() => DemoOperationsRepository(
      clock: DateTime.now,
      latency: Duration.zero,
      extractLatency: Duration.zero,
      autoOfferAfterCheckIn: null,
    );

/// Pumps the whole app. With [signedIn] the remembered session restores straight into the shell.
Future<({ProviderContainer container, DemoOperationsRepository repo, MemorySessionStore store})> pumpApp(
  WidgetTester tester, {
  bool signedIn = true,
}) async {
  final store = MemorySessionStore(signedIn ? sessionFor(staffUser) : null);
  final repo = fastDemoRepo();
  final container = ProviderContainer(overrides: [
    sessionStoreProvider.overrideWithValue(store),
    authRepositoryProvider.overrideWithValue(MockAuthRepository()),
    operationsRepositoryProvider.overrideWith((ref) {
      ref.onDispose(repo.dispose);
      return repo;
    }),
  ]);
  await tester.pumpWidget(UncontrolledProviderScope(container: container, child: const StaffApp()));
  await settle(tester);
  return (container: container, repo: repo, store: store);
}

/// pumpAndSettle with a cap, for screens with progress indicators.
Future<void> settle(WidgetTester tester, [Duration step = const Duration(milliseconds: 100), int times = 15]) async {
  for (var i = 0; i < times; i++) {
    await tester.pump(step);
  }
}

Finder text(String value) => find.text(value);

typedef App = ({ProviderContainer container, DemoOperationsRepository repo, MemorySessionStore store});

/// A widget test over the whole app that disposes the app (and its timers) before
/// the framework checks for pending timers.
void appTest(String description, Future<void> Function(WidgetTester tester, App app) body, {bool signedIn = true}) {
  testWidgets(description, (tester) async {
    // A common Android phone viewport (logical 390×844).
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final app = await pumpApp(tester, signedIn: signedIn);
    try {
      await body(tester, app);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      app.container.dispose();
    }
  });
}

/// Scrolls [finder] into view before tapping it, so taps never land off-screen.
Future<void> tapVisible(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pump();
  await tester.tap(finder);
}
