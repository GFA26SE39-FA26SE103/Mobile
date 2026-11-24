import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/config.dart';
import '../core/providers.dart';
import '../features/auth/auth_controller.dart';
import 'demo_operations_repository.dart';
import 'http_operations_repository.dart';
import 'models.dart';
import 'operations_repository.dart';

/// One repository per signed-in user, so a new account never sees the previous one's tasks.
final operationsRepositoryProvider = Provider<OperationsRepository>((ref) {
  // Keyed on the user id only: re-verifying the same account must not wipe today's state.
  final userId = ref.watch(authControllerProvider.select((s) => s.session?.user.userId));
  final fullName = ref.read(authControllerProvider).session?.user.fullName.trim() ?? '';
  // Vietnamese names put the given name last ("Nguyễn Linh" → "Linh").
  final firstName = fullName.isEmpty ? 'You' : fullName.split(RegExp(r'\s+')).last;
  final clock = ref.watch(clockProvider);
  if (AppConfig.demoOperations) {
    final repo = DemoOperationsRepository(clock: clock, staffName: firstName);
    ref.onDispose(repo.dispose);
    return repo;
  }
  // Signed out there is nothing to poll; the next sign-in builds a new repository.
  final repo = HttpOperationsRepository(ref.watch(dioProvider), clock: clock, staffName: firstName, poll: userId != null);
  // Poll only while the app is in front; reload as soon as it comes back.
  final lifecycle = AppLifecycleListener(
    onShow: () => repo.setForeground(true),
    onHide: () => repo.setForeground(false),
  );
  ref.onDispose(() {
    lifecycle.dispose();
    repo.dispose();
  });
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

/// Evidence of one task; reloaded whenever the task itself changes (submitted, verified, rejected).
final taskEvidenceProvider = FutureProvider.autoDispose.family<TaskEvidenceState, String>((ref, taskId) {
  ref.watch(tasksProvider.select((tasks) => tasks.valueOrNull?.where((t) => t.taskId == taskId).firstOrNull?.status));
  return ref.watch(operationsRepositoryProvider).taskEvidence(taskId);
});

/// Bytes of a stored evidence photo, cached while a screen shows it.
final evidenceImageProvider = FutureProvider.autoDispose.family<List<int>, String>(
  (ref, url) => ref.watch(operationsRepositoryProvider).evidenceImage(url),
);

final notificationsProvider = StreamProvider<List<AppNotification>>(
  (ref) => ref.watch(operationsRepositoryProvider).watchNotifications(),
);

final unreadCountProvider = Provider<int>(
  (ref) => ref.watch(notificationsProvider).valueOrNull?.where((n) => !n.read).length ?? 0,
);

/// Prefer an active checked-in shift, then any active shift or open check-in
/// window, including shifts that start on a different calendar date.
Shift? primaryShiftForToday(Iterable<Shift> shifts, DateTime now) {
  final ordered = shifts.toList()..sort((a, b) => a.start.compareTo(b.start));
  final remaining = ordered.where((s) => now.isBefore(s.end));
  final active = remaining.where((s) => s.isActiveAt(now));
  final today = ordered.where((s) => s.isTodayAt(now));
  return active.where((s) => s.isCheckedIn).firstOrNull ??
      active.firstOrNull ??
      remaining.where((s) => !now.isBefore(s.checkInOpensAt)).firstOrNull ??
      today.where((s) => now.isBefore(s.end)).firstOrNull ??
      today.lastOrNull;
}

/// The shift selected for check-in and other staff actions.
final todayShiftProvider = Provider<Shift?>((ref) {
  final now = ref.watch(clockProvider)();
  final shifts = ref.watch(shiftsProvider).valueOrNull ?? const [];
  return primaryShiftForToday(shifts, now);
});

/// The latest request I sent for each of my shifts.
final swapByShiftProvider = Provider<Map<String, ShiftSwapRequest>>((ref) {
  final requests = ref.watch(swapRequestsProvider).valueOrNull ?? const [];
  final map = <String, ShiftSwapRequest>{};
  for (final r in requests) {
    if (r.sentByMe) map.putIfAbsent(r.shiftId, () => r);
  }
  return map;
});

/// Requests colleagues sent me that still wait for my answer.
final swapsAwaitingMeProvider = Provider<int>(
  (ref) => ref.watch(swapRequestsProvider).valueOrNull?.where((r) => r.canRespond).length ?? 0,
);

/// Colleagues who can take one of my shifts; reloaded each time the screen asks.
final swapCandidatesProvider = FutureProvider.autoDispose.family<SwapCandidates, (String, SwapType)>(
  (ref, key) => ref.watch(operationsRepositoryProvider).swapCandidates(key.$1, key.$2),
);
