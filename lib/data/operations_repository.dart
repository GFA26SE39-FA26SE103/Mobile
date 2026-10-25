import 'models.dart';

/// Everything the Staff app needs for Mainflow 2 (10/10/2026 baseline) and shift swaps (MF-04).
///
/// [HttpOperationsRepository] talks to the backend; [DemoOperationsRepository] runs the same
/// contract in-app for demos and tests. Screens only depend on this interface.
abstract class OperationsRepository {
  // Shifts, check-in and swaps
  Stream<List<Shift>> watchShifts();
  Future<Shift> checkIn(String shiftId);

  /// Requests I sent and requests colleagues sent me, newest first.
  Stream<List<ShiftSwapRequest>> watchSwapRequests();

  /// Colleagues who pass every swap rule for one of my future shifts.
  Future<SwapCandidates> swapCandidates(String shiftId, SwapType type);

  /// Asks a colleague to swap ([targetShiftId] required) or cover my shift. The colleague
  /// answers first, then a Manager decides. Refusals throw [SwapNotAllowed].
  Future<ShiftSwapRequest> requestShiftSwap({
    required String shiftId,
    required SwapType type,
    required String targetUserId,
    String? targetShiftId,
    SwapReason? reason,
    String note = '',
  });

  /// The colleague's answer to a request sent to them.
  Future<ShiftSwapRequest> respondToSwap(String requestId, {required bool accept});

  /// The requester cancels while pending; the colleague can withdraw while the Manager decides.
  Future<ShiftSwapRequest> cancelSwap(String requestId, {String? reason});

  /// Reloads everything now (pull to refresh, after a notification).
  Future<void> refresh();

  /// The app came to the front (reload now and keep polling) or went to the background (stop).
  void setForeground(bool foreground);

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

  /// Moves the latest open swap request one step: the colleague answers my request, or the
  /// Manager decides a request the colleague accepted.
  String? advanceLatestSwap({required bool approve});

  /// A colleague asks to swap one of my upcoming shifts.
  String? receiveSwapRequest();
}
