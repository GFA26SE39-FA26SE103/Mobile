import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/providers.dart';
import '../features/auth/auth_controller.dart';
import 'demo_operations_repository.dart';
import 'models.dart';
import 'operations_repository.dart';

/// One repository per signed-in user, so a new account never sees the previous one's tasks.
final operationsRepositoryProvider = Provider<OperationsRepository>((ref) {
  // Keyed on the user id only: re-verifying the same account must not wipe today's state.
  ref.watch(authControllerProvider.select((s) => s.session?.user.userId));
  final fullName = ref.read(authControllerProvider).session?.user.fullName.trim() ?? '';
  // Vietnamese names put the given name last ("Nguyễn Linh" → "Linh").
  final firstName = fullName.isEmpty ? 'You' : fullName.split(RegExp(r'\s+')).last;
  final repo = DemoOperationsRepository(clock: ref.watch(clockProvider), staffName: firstName);
  ref.onDispose(repo.dispose);
  return repo;
});

/// Present only while running on the in-app demo backend.
final demoControlsProvider = Provider<DemoControls?>((ref) {
  final repo = ref.watch(operationsRepositoryProvider);
  return repo is DemoControls ? repo as DemoControls : null;
});

final shiftsProvider = StreamProvider<List<Shift>>((ref) => ref.watch(operationsRepositoryProvider).watchShifts());

final swapRequestsProvider = StreamProvider<List<ShiftSwapRequest>>(
  (ref) => ref.watch(operationsRepositoryProvider).watchSwapRequests(),
);

final eligibilityProvider = StreamProvider<Eligibility>((ref) => ref.watch(operationsRepositoryProvider).watchEligibility());

final openOffersProvider = StreamProvider<List<TaskOffer>>((ref) => ref.watch(operationsRepositoryProvider).watchOpenOffers());

final offerProvider = StreamProvider.family<TaskOffer?, String>(
  (ref, id) => ref.watch(operationsRepositoryProvider).watchOffer(id),
);

final tasksProvider = StreamProvider<List<StaffTask>>((ref) => ref.watch(operationsRepositoryProvider).watchTasks());

final notificationsProvider = StreamProvider<List<AppNotification>>(
  (ref) => ref.watch(operationsRepositoryProvider).watchNotifications(),
);

final unreadCountProvider = Provider<int>(
  (ref) => ref.watch(notificationsProvider).valueOrNull?.where((n) => !n.read).length ?? 0,
);

/// Today's shift, if the staff member has one.
final todayShiftProvider = Provider<Shift?>((ref) {
  final now = ref.watch(clockProvider)();
  final shifts = ref.watch(shiftsProvider).valueOrNull ?? const [];
  for (final s in shifts) {
    if (s.isTodayAt(now)) return s;
  }
  return null;
});

/// The latest swap request for each shift.
final swapByShiftProvider = Provider<Map<String, ShiftSwapRequest>>((ref) {
  final requests = ref.watch(swapRequestsProvider).valueOrNull ?? const [];
  final map = <String, ShiftSwapRequest>{};
  for (final r in requests) {
    map.putIfAbsent(r.shiftId, () => r);
  }
  return map;
});
