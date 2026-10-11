import 'models.dart';

/// Everything the Staff app needs for Mainflow 2 (10/10/2026 baseline).
///
/// The backend has no Task / StaffReport / shift API yet, so [DemoOperationsRepository]
/// implements this contract in-app. An HTTP implementation replaces it once the endpoints
/// in `docs/API_CONTRACT.md` exist; screens only depend on this interface.
abstract class OperationsRepository {
  // Shifts, check-in and swaps
  Stream<List<Shift>> watchShifts();
  Future<Shift> checkIn(String shiftId);
  Stream<List<ShiftSwapRequest>> watchSwapRequests();

  /// Staff asks to swap a future shift; the Operator approves and picks a replacement.
  Future<ShiftSwapRequest> requestShiftSwap(String shiftId, SwapReason reason, String note);

  /// Dispatch eligibility: on shift + checked in + zone + below the task limit.
  Stream<Eligibility> watchEligibility();

  // Task offers (ResponsePolicy → Task → offer to eligible zone staff)
  /// Emits each time an offer should be put in front of the staff member,
  /// including re-notifications (every 60 s, up to 3 attempts).
  Stream<TaskOffer> incomingOffers();
  Stream<List<TaskOffer>> watchOpenOffers();
  Stream<TaskOffer?> watchOffer(String offerId);

  /// Handle Now / Accept and Handle Later accept responsibility; the first valid
  /// acceptance wins and others get [TaskAlreadyTaken]. Cannot Handle needs a reason.
  Future<StaffTask?> respondToOffer(String offerId, TaskResponse response, {Duration? handleAfter, DeclineReason? reason});

  // Tasks
  Stream<List<StaffTask>> watchTasks();

  /// Starts work on an accepted (possibly deferred) task.
  Future<StaffTask> startTask(String taskId);

  // Notifications
  Stream<List<AppNotification>> watchNotifications();
  Future<void> markAllRead();

  // StaffReport (Report → AI extract → Confirm → stored; routine Task or Incident qualification)
  Future<ReportDraft> extractReport(String note, List<String> photoPaths, {bool fromVoice = false});
  Future<ReportReceipt> submitReport(ReportDraft draft);
}

/// Controls that only exist in the in-app demo backend (Me → Demo tools).
abstract class DemoControls {
  /// Raises an OperationalEvent whose response policy offers a Task to this zone.
  /// Returns why nothing was delivered, or null when the offer went out.
  String? simulateEventTask({bool takenByOther = false});

  /// The latest WARNING event escalates to CRITICAL on the same episode, so its open offer or
  /// task is updated rather than a new one created. Returns why nothing changed, or null.
  String? escalateLatestEvent();

  /// The latest active event recovers (`CLEARED`): an open offer is withdrawn, an accepted
  /// task stays with the staff member. Returns why nothing changed, or null.
  String? clearLatestEvent();
  void completeActiveTasks();

  /// Plays the Operator's decision on the latest pending swap request.
  String? decideLatestSwap({required bool approve});
}
