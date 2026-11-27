import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../data/providers.dart';
import 'config.dart';
import '../features/alerts/alerts_screen.dart';
import '../features/alerts/incoming_alert.dart';
import '../features/alerts/notification_host.dart';
import '../features/auth/auth_controller.dart';
import '../features/auth/sign_in_screen.dart';
import '../features/me/me_screen.dart';
import '../features/report/report_screens.dart';
import '../features/shifts/shifts_screens.dart';
import '../features/shifts/swap_screens.dart';
import '../features/tasks/complete_task_screen.dart';
import '../features/tasks/tasks_screens.dart';

class _AuthListenable extends ChangeNotifier {
  _AuthListenable(Ref ref) {
    ref.listen(authControllerProvider, (_, _) => notifyListeners());
  }
}

final routerProvider = Provider<GoRouter>((ref) {
  final refresh = _AuthListenable(ref);
  ref.onDispose(refresh.dispose);

  return GoRouter(
    initialLocation: '/tasks',
    refreshListenable: refresh,
    redirect: (context, state) {
      final auth = ref.read(authControllerProvider);
      final path = state.matchedLocation;
      final onAuthPage = path == '/sign-in' || path == '/session-expired' || path == '/splash';
      return switch (auth) {
        AuthRestoring() => path == '/splash' ? null : '/splash',
        SignedOut() => path == '/sign-in' ? null : '/sign-in',
        // From Session expired the user may go on to the sign-in form.
        SessionExpired() => path == '/session-expired' || path == '/sign-in' ? null : '/session-expired',
        SignedIn() => onAuthPage ? '/tasks' : null,
      };
    },
    routes: [
      GoRoute(path: '/splash', builder: (_, _) => const _Splash()),
      GoRoute(
        path: '/sign-in',
        builder: (_, state) {
          final auth = ref.read(authControllerProvider);
          final email = state.uri.queryParameters['email'] ?? (auth is SignedOut ? auth.email : null);
          return SignInScreen(key: ValueKey(email), initialEmail: email);
        },
      ),
      GoRoute(
        path: '/session-expired',
        builder: (context, _) {
          final auth = ref.read(authControllerProvider);
          if (auth is! SessionExpired) return const _Splash();
          return SessionExpiredScreen(
            user: auth.user,
            onSignInAgain: () => context.go(Uri(path: '/sign-in', queryParameters: {'email': auth.user.email}).toString()),
            onSwitchAccount: () => ref.read(authControllerProvider.notifier).signOut(),
          );
        },
      ),
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) => _StaffShell(shell: shell),
        branches: [
          StatefulShellBranch(routes: [
            GoRoute(
              path: '/tasks',
              builder: (_, _) => const MyTasksScreen(),
              routes: [
                GoRoute(
                  path: ':taskId',
                  builder: (_, s) => TaskDetailScreen(taskId: s.pathParameters['taskId']!),
                  routes: [GoRoute(path: 'complete', builder: (_, s) => CompleteTaskScreen(taskId: s.pathParameters['taskId']!))],
                ),
              ],
            ),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
              path: '/report',
              builder: (_, _) => const ReportDescribeScreen(),
              routes: [
                GoRoute(path: 'review', builder: (_, _) => const ReportReviewScreen()),
                GoRoute(path: 'submitted', builder: (_, _) => const ReportSubmittedScreen()),
              ],
            ),
          ]),
          StatefulShellBranch(routes: [GoRoute(path: '/alerts', builder: (_, _) => const AlertsScreen())]),
          StatefulShellBranch(routes: [
            GoRoute(
              path: '/shifts',
              builder: (_, _) => const MyShiftsScreen(),
              routes: [
                GoRoute(path: 'checked-in', builder: (_, _) => const CheckedInScreen()),
                GoRoute(
                  path: 'swaps',
                  builder: (_, _) => const SwapInboxScreen(),
                  routes: [GoRoute(path: ':requestId', builder: (_, s) => SwapDetailScreen(requestId: s.pathParameters['requestId']!))],
                ),
                GoRoute(path: ':shiftId/swap', builder: (_, s) => SwapRequestScreen(shiftId: s.pathParameters['shiftId']!)),
                GoRoute(path: ':shiftId', builder: (_, s) => ShiftDetailScreen(shiftId: s.pathParameters['shiftId']!)),
              ],
            ),
          ]),
          StatefulShellBranch(routes: [GoRoute(path: '/me', builder: (_, _) => const MeScreen())]),
        ],
      ),
    ],
  );
});

class _Splash extends StatelessWidget {
  const _Splash();

  @override
  Widget build(BuildContext context) => const Scaffold(body: Center(child: CircularProgressIndicator()));
}

class _StaffShell extends ConsumerWidget {
  const _StaffShell({required this.shell});
  final StatefulNavigationShell shell;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unread = ref.watch(unreadCountProvider);
    final openOffers = ref.watch(openOffersProvider).valueOrNull?.length ?? 0;
    final badge = unread + openOffers;
    final swaps = ref.watch(swapsAwaitingMeProvider);
    return Scaffold(
      body: DeviceNotificationHost(
        child: TaskOfferHost(
          // Demo data must never pass for the real store.
          child: AppConfig.demoOperations
              ? Banner(message: 'DEMO DATA', location: BannerLocation.topEnd, child: shell)
              : shell,
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: shell.currentIndex,
        onDestinationSelected: (i) => shell.goBranch(i, initialLocation: i == shell.currentIndex),
        destinations: [
          const NavigationDestination(icon: Icon(Icons.format_list_bulleted), label: 'Tasks'),
          const NavigationDestination(icon: Icon(Icons.outlined_flag), selectedIcon: Icon(Icons.flag), label: 'Report'),
          NavigationDestination(
            icon: Badge(isLabelVisible: badge > 0, label: Text('$badge'), child: const Icon(Icons.notifications_none)),
            selectedIcon: Badge(isLabelVisible: badge > 0, label: Text('$badge'), child: const Icon(Icons.notifications)),
            label: 'Alerts',
          ),
          NavigationDestination(
            icon: Badge(isLabelVisible: swaps > 0, label: Text('$swaps'), child: const Icon(Icons.calendar_today_outlined)),
            selectedIcon: Badge(isLabelVisible: swaps > 0, label: Text('$swaps'), child: const Icon(Icons.calendar_today)),
            label: 'Shifts',
          ),
          const NavigationDestination(icon: Icon(Icons.person_outline), selectedIcon: Icon(Icons.person), label: 'Me'),
        ],
      ),
    );
  }
}
