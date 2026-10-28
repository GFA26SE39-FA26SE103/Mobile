import 'dart:async';
import 'dart:io';

import 'models.dart';
import 'operations_repository.dart';

/// A value plus a broadcast stream that replays the current value to new listeners.
class _Store<T> {
  _Store(this._value);
  T _value;
  final _controller = StreamController<T>.broadcast();

  T get value => _value;
  set value(T next) {
    _value = next;
    _controller.add(next);
  }

  Stream<T> get stream async* {
    yield _value;
    yield* _controller.stream;
  }

  void close() => _controller.close();
}

class _EventTemplate {
  const _EventTemplate(this.code, this.title, this.priority, this.location, this.measurement, this.criticalMeasurement,
      this.instructions, this.camera);

  /// OperationalEventType code from Database V2.
  final String code;
  final String title;
  final Severity priority;
  final String location;
  final String measurement;

  /// What the measurement reads once the episode escalates to CRITICAL.
  final String criticalMeasurement;
  final String instructions;
  final String camera;
}

/// In-app stand-in for the MF-02 backend, following the 10/10/2026 baseline:
/// an OperationalEvent's response policy offers a Task to checked-in zone staff below the
/// 2-task limit; the first acceptance (Handle Now or Handle Later) wins; unanswered offers
/// re-notify every 60 s up to 3 times and then escalate to the Operator; confirmed staff
/// reports become a routine Task or go through Incident qualification; a shift swap goes to a
/// colleague first and then to the Manager. Events behave like the backend's
/// 11/10/2026 episodes: escalation updates the same offer or task, recovery clears it.
class DemoOperationsRepository implements OperationsRepository, DemoControls {
  DemoOperationsRepository({
    required this.clock,
    this.staffName = 'Linh',
    this.latency = const Duration(milliseconds: 450),
    this.extractLatency = const Duration(milliseconds: 1200),
    this.autoOfferAfterCheckIn = const Duration(seconds: 6),
    this.realertInterval = TaskOffer.realertInterval,
    this.otherStaffAcceptDelay = const Duration(seconds: 4),
  }) {
    _seed();
  }

  final DateTime Function() clock;
  final String staffName;
  final Duration latency;
  final Duration extractLatency;

  /// Null disables the automatic first offer after check-in (tests).
  final Duration? autoOfferAfterCheckIn;
  final Duration realertInterval;
  final Duration otherStaffAcceptDelay;

  final _shifts = _Store<List<Shift>>(const []);
  final _swaps = _Store<List<ShiftSwapRequest>>(const []);
  final _offers = _Store<List<TaskOffer>>(const []);
  final _tasks = _Store<List<StaffTask>>(const []);
  final _notifications = _Store<List<AppNotification>>(const []);
  final _eligibilityStore = _Store<Eligibility>(const Eligibility(checkedIn: false, activeTasks: 0));
  final _incoming = StreamController<TaskOffer>.broadcast();
  final _timers = <String, List<Timer>>{};
  Timer? _autoOffer;
  int _eventSequence = 1042;
  int _incidentSequence = 1012;
  int _reportSequence = 241;
  int _taskSequence = 2050;
  int _swapSequence = 7;
  int _template = 0;

  static const _teammates = ['Thảo', 'An Khương'];
  static const _templates = [
    _EventTemplate('LONG_QUEUE', 'Long queue at checkout', Severity.warning, 'Checkout 3', '7 people waiting · 3 min',
        '11 people waiting · 6 min', 'Open 1 more counter and redirect the queue', 'CAM-03'),
    _EventTemplate('CHECKOUT_CAPACITY', 'Not enough open counters', Severity.critical, 'Checkout 4–6',
        '2 of 6 counters open · 14 waiting', '2 of 6 counters open · 14 waiting', 'Open counter 5 and call a cashier from the floor', 'CAM-05'),
    _EventTemplate('CONGESTION', 'Congestion at checkout entrance', Severity.warning, 'Checkout entrance', '18 people in zone for 3 min',
        '26 people in zone for 5 min', 'Guide customers to open counters and keep the walkway clear', 'CAM-02'),
    _EventTemplate('EXCESSIVE_WAIT', 'Excessive waiting time', Severity.warning, 'Checkout 1–2', 'Average wait 5 min',
        'Average wait 9 min', 'Call a cashier to help at counters 1–2', 'CAM-04'),
  ];

  /// Template behind each raised event, keyed by EVT code.
  final _eventTemplates = <String, _EventTemplate>{};

  // ---------------------------------------------------------------- seed data

  void _seed() {
    final now = clock();
    final hourStart = DateTime(now.year, now.month, now.day, now.hour);
    final today = DateTime(now.year, now.month, now.day);
    Shift shift(String id, DateTime start, int hours) => Shift(
          shiftId: id,
          start: start,
          end: start.add(Duration(hours: hours)),
          label: start.hour < 12 ? 'Morning' : 'Evening',
          zoneName: 'Zone B · Checkout',
          zoneDetail: 'Counters 1–6',
          floorName: 'Floor 1',
          storeName: 'Central Q1',
          teammates: const ['Thảo'],
        );
    _shifts.value = [
      // Today's shift started at the top of this hour, so check-in is open in the demo.
      shift('shift-today', hourStart, 8),
      shift('shift-1', today.add(const Duration(days: 1, hours: 6)), 8),
      shift('shift-3', today.add(const Duration(days: 3, hours: 14)), 8),
      shift('shift-4', today.add(const Duration(days: 4, hours: 14)), 8),
    ];
    _tasks.value = [
      StaffTask(
        taskId: 'task-2031',
        origin: TaskOrigin.staffReport,
        sourceCode: 'RPT-0238',
        title: 'Restock snack rack near Checkout 2',
        priority: Severity.info,
        zoneName: 'Zone B · Checkout',
        location: 'Checkout 2',
        instructions: 'Refill the impulse-buy rack before the evening rush.',
        createdAt: now.subtract(const Duration(minutes: 18)),
        acceptedAt: now.subtract(const Duration(minutes: 15)),
        status: TaskStatus.accepted,
        plannedStartAt: now.add(const Duration(minutes: 20)),
      ),
      StaffTask(
        taskId: 'task-2012',
        origin: TaskOrigin.incident,
        sourceCode: 'INC-1012',
        title: 'Clean spill at entrance',
        priority: Severity.warning,
        zoneName: 'Zone A · Entrance',
        location: 'Entrance door',
        instructions: 'Place a warning sign, then mop the wet floor.',
        createdAt: now.subtract(const Duration(hours: 2, minutes: 10)),
        acceptedAt: now.subtract(const Duration(hours: 2, minutes: 8)),
        startedAt: now.subtract(const Duration(hours: 2, minutes: 8)),
        status: TaskStatus.verified,
        cameraCode: 'CAM-01',
      ),
    ];
    _notifications.value = [
      AppNotification(
        id: 'n-seed',
        kind: NotificationKind.taskAccepted,
        title: 'Task completed',
        body: 'Clean spill at entrance · Zone A',
        createdAt: now.subtract(const Duration(hours: 2)),
        read: true,
      ),
    ];
  }

  // ------------------------------------------------------------------ helpers

  Future<void> _wait(Duration d) => d == Duration.zero ? Future<void>.value() : Future<void>.delayed(d);

  Shift? get _todayShift {
    final now = clock();
    for (final s in _shifts.value) {
      if (s.isTodayAt(now)) return s;
    }
    return null;
  }

  Eligibility get _eligibility {
    final shift = _todayShift;
    final checkedIn = shift != null && shift.isCheckedIn && shift.isActiveAt(clock());
    return Eligibility(
      checkedIn: checkedIn,
      activeTasks: _tasks.value.where((t) => t.isActive).length,
      zoneName: checkedIn ? shift.zoneName : null,
      shiftEndsAt: checkedIn ? shift.end : null,
    );
  }

  void _refreshEligibility() => _eligibilityStore.value = _eligibility;

  void _notify(NotificationKind kind, String title, String body, {Severity? severity, String? taskId}) {
    final note = AppNotification(
      id: 'n-${clock().microsecondsSinceEpoch}-${_notifications.value.length}',
      kind: kind,
      title: title,
      body: body,
      createdAt: clock(),
      severity: severity,
      taskId: taskId,
    );
    _notifications.value = [note, ..._notifications.value];
  }

  TaskOffer? _offer(String id) {
    for (final o in _offers.value) {
      if (o.offerId == id) return o;
    }
    return null;
  }

  void _replaceOffer(TaskOffer next) => _offers.value = [for (final o in _offers.value) o.offerId == next.offerId ? next : o];

  void _cancelTimers(String id) {
    for (final t in _timers.remove(id) ?? const <Timer>[]) {
      t.cancel();
    }
  }

  // ------------------------------------------------------------------- shifts

  @override
  Stream<List<Shift>> watchShifts() => _shifts.stream;

  @override
  Stream<Eligibility> watchEligibility() {
    _refreshEligibility();
    return _eligibilityStore.stream;
  }

  @override
  Future<Shift> checkIn(String shiftId) async {
    await _wait(latency);
    final shift = _shifts.value.firstWhere((s) => s.shiftId == shiftId);
    final now = clock();
    if (shift.isCheckedIn) return shift;
    if (now.isBefore(shift.checkInOpensAt)) throw CheckInTooEarly(shift.checkInOpensAt);
    if (!now.isBefore(shift.end)) throw StateError('This shift has already ended.');
    final checkedIn = shift.copyWith(checkedInAt: now);
    _shifts.value = [for (final s in _shifts.value) s.shiftId == shiftId ? checkedIn : s];
    _refreshEligibility();
    _notify(NotificationKind.shiftStarted, 'Shift started', 'You are on ${shift.zoneName}. Task offers for this zone are on.');
    final delay = autoOfferAfterCheckIn;
    if (delay != null) {
      _autoOffer?.cancel();
      _autoOffer = Timer(delay, simulateEventTask);
    }
    return checkedIn;
  }

  @override
  Stream<List<ShiftSwapRequest>> watchSwapRequests() => _swaps.stream;

  @override
  Future<void> refresh() async {}

  static const _me = 'me';
  static const _colleagues = [('u-lan', 'Hoàng Lan'), ('u-duc', 'Minh Đức'), ('u-quang', 'Quang')];

  SwapShift _swapShiftOf(Shift s) =>
      SwapShift(shiftId: s.shiftId, ownerId: _me, label: s.label, start: s.start, end: s.end, zoneName: s.zoneName);

  Shift _shiftOf(SwapShift s) => Shift(shiftId: s.shiftId, start: s.start, end: s.end, label: s.label, zoneName: s.zoneName);

  /// The shift colleague [index] would give back: same hours, [index] + 1 days after mine.
  SwapShift _colleagueShift(Shift mine, int index) {
    final start = mine.start.add(Duration(days: index + 1));
    return SwapShift(
      shiftId: 'c-${_colleagues[index].$1}-${mine.shiftId}',
      ownerId: _colleagues[index].$1,
      label: mine.label,
      start: start,
      end: start.add(mine.end.difference(mine.start)),
      zoneName: mine.zoneName,
    );
  }

  /// Requests must be decided 24 h before the earliest affected shift.
  static DateTime _deadline(DateTime start) => start.subtract(const Duration(hours: 24));

  Shift _ownShift(String shiftId) {
    final shift = _shifts.value.where((s) => s.shiftId == shiftId).firstOrNull;
    if (shift == null) throw const SwapNotAllowed('This shift is no longer on your schedule.');
    return shift;
  }

  void _checkOpenForSwap(Shift shift) {
    if (!shift.canRequestSwapAt(clock())) throw const SwapNotAllowed('This shift has already started and can no longer be changed.');
    if (!clock().isBefore(_deadline(shift.start))) {
      throw const SwapNotAllowed('Swap requests close 24 hours before the shift. Talk to the Manager on duty.');
    }
  }

  bool _hasOpenSwap(String shiftId) =>
      _swaps.value.any((r) => r.status.isOpen && (r.shiftId == shiftId || r.targetShift?.shiftId == shiftId));

  @override
  Future<SwapCandidates> swapCandidates(String shiftId, SwapType type) async {
    await _wait(latency);
    final shift = _ownShift(shiftId);
    _checkOpenForSwap(shift);
    return SwapCandidates(
      shiftId: shiftId,
      type: type,
      deadline: _deadline(shift.start),
      hiddenCount: 1,
      candidates: [
        for (var i = 0; i < _colleagues.length; i++)
          SwapCandidate(
            userId: _colleagues[i].$1,
            fullName: _colleagues[i].$2,
            shift: type == SwapType.swap ? _colleagueShift(shift, i) : null,
            weeklyHoursAfter: 32.0 + 4 * i + (type == SwapType.cover ? 8 : 0),
          ),
      ],
    );
  }

  ShiftSwapRequest _withStatus(ShiftSwapRequest r, SwapStatus status,
      {DateTime? respondedAt, String? decisionNote, String? cancelledBy, String? cancellationReason}) {
    final decided = status == SwapStatus.approved || status == SwapStatus.rejected;
    return ShiftSwapRequest(
      requestId: r.requestId,
      type: r.type,
      status: status,
      requesterId: r.requesterId,
      requesterName: r.requesterName,
      requesterShift: r.requesterShift,
      targetId: r.targetId,
      targetName: r.targetName,
      targetShift: r.targetShift,
      reason: r.reason,
      note: r.note,
      submittedAt: r.submittedAt,
      expiresAt: r.expiresAt,
      sentByMe: r.sentByMe,
      targetRespondedAt: respondedAt ?? r.targetRespondedAt,
      decidedBy: decided ? 'Trần Minh' : null,
      decidedAt: decided ? clock() : null,
      decisionNote: decisionNote,
      cancelledBy: cancelledBy,
      cancelledAt: cancelledBy == null ? null : clock(),
      cancellationReason: cancellationReason,
      // A can cancel while pending; B can withdraw only while the Manager decides.
      canCancel: status == SwapStatus.pendingManager || (status == SwapStatus.pendingPeer && r.sentByMe),
      canRespond: status == SwapStatus.pendingPeer && !r.sentByMe,
    );
  }

  void _replaceSwap(ShiftSwapRequest next) => _swaps.value = [for (final r in _swaps.value) r.requestId == next.requestId ? next : r];

  ShiftSwapRequest _swap(String requestId) {
    final request = _swaps.value.where((r) => r.requestId == requestId).firstOrNull;
    if (request == null) throw const SwapNotAllowed('This request no longer exists.');
    return request;
  }

  @override
  Future<ShiftSwapRequest> requestShiftSwap({
    required String shiftId,
    required SwapType type,
    required String targetUserId,
    String? targetShiftId,
    SwapReason? reason,
    String note = '',
  }) async {
    await _wait(latency);
    final shift = _ownShift(shiftId);
    _checkOpenForSwap(shift);
    if (_hasOpenSwap(shiftId)) throw const SwapNotAllowed('This shift already has a pending swap request.');
    final index = _colleagues.indexWhere((c) => c.$1 == targetUserId);
    if (index < 0) throw const SwapNotAllowed('Choose a colleague from the list.');
    if (type == SwapType.swap && targetShiftId == null) throw const SwapNotAllowed('Choose which of their shifts you take.');
    if (reason == SwapReason.other && note.trim().isEmpty) {
      throw const SwapNotAllowed('Add a short note so your colleague and the Manager understand the request.');
    }
    final theirs = type == SwapType.swap ? _colleagueShift(shift, index) : null;
    final earliest = theirs != null && theirs.start.isBefore(shift.start) ? theirs.start : shift.start;
    final request = ShiftSwapRequest(
      requestId: 'swap-${++_swapSequence}',
      type: type,
      status: SwapStatus.pendingPeer,
      requesterId: _me,
      requesterName: staffName,
      requesterShift: _swapShiftOf(shift),
      targetId: targetUserId,
      targetName: _colleagues[index].$2,
      targetShift: theirs,
      reason: reason,
      note: note.trim(),
      submittedAt: clock(),
      expiresAt: _deadline(earliest),
      sentByMe: true,
      canCancel: true,
    );
    _swaps.value = [request, ..._swaps.value];
    _notify(NotificationKind.swapUpdated, 'Swap request sent',
        '${request.targetName} answers first, then the Manager decides on your ${shift.label.toLowerCase()} shift.');
    return request;
  }

  @override
  Future<ShiftSwapRequest> respondToSwap(String requestId, {required bool accept}) async {
    await _wait(latency);
    final request = _swap(requestId);
    if (!request.canRespond) throw const SwapNotAllowed('This request is no longer waiting for your answer.');
    final next = _withStatus(request, accept ? SwapStatus.pendingManager : SwapStatus.declinedByPeer, respondedAt: clock());
    _replaceSwap(next);
    return next;
  }

  @override
  Future<ShiftSwapRequest> cancelSwap(String requestId, {String? reason}) async {
    await _wait(latency);
    final request = _swap(requestId);
    if (!request.canCancel) throw const SwapNotAllowed('This request can no longer be cancelled.');
    final next = _withStatus(request, SwapStatus.cancelled, cancelledBy: staffName, cancellationReason: reason);
    _replaceSwap(next);
    return next;
  }

  @override
  String? advanceLatestSwap({required bool approve}) {
    final request = _swaps.value.where((r) => r.status.isOpen).firstOrNull;
    if (request == null) return 'There is no pending swap request.';
    if (request.status == SwapStatus.pendingPeer) {
      if (!request.sentByMe) return 'This request is waiting for your answer. Open it under Shifts → Swap requests.';
      _replaceSwap(_withStatus(request, approve ? SwapStatus.pendingManager : SwapStatus.declinedByPeer, respondedAt: clock()));
      _notify(NotificationKind.swapUpdated, approve ? '${request.otherName} accepted' : '${request.otherName} declined',
          approve ? 'Your swap request now waits for the Manager.' : 'You keep your shift.');
      return null;
    }
    if (!approve) {
      _replaceSwap(_withStatus(request, SwapStatus.rejected, decisionNote: 'Zone B would drop below the minimum staff for that shift.'));
      _notify(NotificationKind.swapUpdated, 'Swap request rejected', 'The Manager kept the schedule as it is.');
      return null;
    }
    _replaceSwap(_withStatus(request, SwapStatus.approved));
    final give = request.iGive!;
    final get = request.iGet;
    _shifts.value = [
      for (final s in _shifts.value)
        if (s.shiftId != give.shiftId) s,
      if (get != null) _shiftOf(get),
    ]..sort((a, b) => a.start.compareTo(b.start));
    _notify(
      NotificationKind.swapUpdated,
      'Swap approved',
      get == null ? '${request.otherName} now covers your ${give.label.toLowerCase()} shift.' : 'Your schedule now has the shift from ${request.otherName}.',
    );
    return null;
  }

  @override
  String? receiveSwapRequest() {
    final now = clock();
    final mine = _shifts.value.where((s) => now.isBefore(_deadline(s.start)) && !_hasOpenSwap(s.shiftId)).firstOrNull;
    if (mine == null) return 'None of your shifts can still be swapped.';
    final (id, name) = _colleagues.last;
    final theirs = _colleagueShift(mine, 0);
    final request = ShiftSwapRequest(
      requestId: 'swap-${++_swapSequence}',
      type: SwapType.swap,
      status: SwapStatus.pendingPeer,
      requesterId: id,
      requesterName: name,
      requesterShift: SwapShift(shiftId: theirs.shiftId, ownerId: id, label: theirs.label, start: theirs.start, end: theirs.end, zoneName: theirs.zoneName),
      targetId: _me,
      targetName: staffName,
      targetShift: _swapShiftOf(mine),
      reason: SwapReason.study,
      note: 'Exam that day. Can you take my shift?',
      submittedAt: now,
      expiresAt: _deadline(mine.start),
      sentByMe: false,
      canRespond: true,
    );
    _swaps.value = [request, ..._swaps.value];
    _notify(NotificationKind.swapUpdated, 'Swap request from $name', 'Swap your ${mine.label.toLowerCase()} shift on ${mine.start.day}/${mine.start.month}?');
    return null;
  }

  // ------------------------------------------------------------------- offers

  @override
  Stream<TaskOffer> incomingOffers() => _incoming.stream;

  @override
  Stream<List<TaskOffer>> watchOpenOffers() => _offers.stream.map((all) => all.where((o) => o.isOpen).toList());

  @override
  Stream<TaskOffer?> watchOffer(String offerId) => _offers.stream.map((_) => _offer(offerId));

  void _publish(TaskOffer offer, {bool takenByOther = false}) {
    _offers.value = [offer, ..._offers.value];
    _incoming.add(offer);
    _notify(NotificationKind.taskOffered, 'New task offer', '${offer.title} · ${offer.location}', severity: offer.priority);
    _scheduleRealert(offer.offerId);
    if (takenByOther) {
      (_timers[offer.offerId] ??= []).add(Timer(otherStaffAcceptDelay, () => _takenByOther(offer.offerId, _teammates.last)));
    }
  }

  @override
  String? simulateEventTask({bool takenByOther = false}) {
    final eligibility = _eligibility;
    if (!eligibility.checkedIn) return 'Check in to a shift first. Task offers only reach checked-in staff.';
    if (eligibility.atWorkloadLimit) {
      return 'You already have ${Eligibility.workloadLimit} active tasks. New offers go to other staff until you finish one.';
    }
    final template = _templates[_template++ % _templates.length];
    final now = clock();
    final code = 'EVT-${++_eventSequence}';
    _eventTemplates[code] = template;
    _publish(
      TaskOffer(
        offerId: 'offer-${++_taskSequence}',
        origin: TaskOrigin.operationalEvent,
        sourceCode: code,
        eventTypeCode: template.code,
        title: template.title,
        priority: template.priority,
        zoneName: eligibility.zoneName!,
        location: template.location,
        measurement: template.measurement,
        instructions: template.instructions,
        createdAt: now,
        recipients: 1 + _teammates.length,
        attempt: 1,
        nextAlertAt: now.add(realertInterval),
        cameraCode: template.camera,
      ),
      takenByOther: takenByOther,
    );
    return null;
  }

  void _scheduleRealert(String id) {
    (_timers[id] ??= []).add(Timer(realertInterval, () {
      final current = _offer(id);
      if (current == null || !current.isOpen) return;
      if (current.attempt >= current.maxAttempts) {
        _replaceOffer(current.copyWith(status: OfferStatus.escalated));
        _cancelTimers(id);
        _notify(NotificationKind.offerEscalated, 'Offer passed to Operator',
            '${current.title} · nobody accepted after ${current.maxAttempts} offers',
            severity: current.priority);
        return;
      }
      final next = current.copyWith(attempt: current.attempt + 1, nextAlertAt: clock().add(realertInterval));
      _replaceOffer(next);
      _incoming.add(next);
      _scheduleRealert(id);
    }));
  }

  void _takenByOther(String id, String by) {
    final current = _offer(id);
    if (current == null || !current.isOpen) return;
    _cancelTimers(id);
    _replaceOffer(current.copyWith(status: OfferStatus.takenByOther, takenBy: by, takenAt: clock()));
    _notify(NotificationKind.offerTaken, 'Taken by $by', '${current.title} · offer withdrawn', severity: current.priority);
  }

  // ------------------------------------------------ OperationalEvent episodes

  /// The newest event still active for this staff member: an open offer or an unfinished task
  /// from an OperationalEvent whose episode has not cleared.
  ({TaskOffer? offer, StaffTask? task})? _latestActiveEvent({Severity? withPriority}) {
    final offers = _offers.value.where((o) =>
        o.isOpen && o.origin == TaskOrigin.operationalEvent && (withPriority == null || o.priority == withPriority));
    final tasks = _tasks.value.where((t) =>
        t.isActive &&
        t.origin == TaskOrigin.operationalEvent &&
        t.eventClearedAt == null &&
        (withPriority == null || t.priority == withPriority));
    final candidates = [
      for (final o in offers) (at: o.createdAt, offer: o, task: null as StaffTask?),
      for (final t in tasks) (at: t.createdAt, offer: null as TaskOffer?, task: t),
    ]..sort((a, b) => b.at.compareTo(a.at));
    if (candidates.isEmpty) return null;
    return (offer: candidates.first.offer, task: candidates.first.task);
  }

  void _replaceTask(StaffTask next) => _tasks.value = [for (final t in _tasks.value) t.taskId == next.taskId ? next : t];

  @override
  String? escalateLatestEvent() {
    final latest = _latestActiveEvent(withPriority: Severity.warning);
    if (latest == null) {
      return _latestActiveEvent() == null
          ? 'No active AI event. Raise an AI event task first.'
          : 'The active events are already CRITICAL. Raise a new AI event task to try escalation.';
    }
    final offer = latest.offer;
    final task = latest.task;
    if (offer != null) {
      final raised = offer.copyWith(
        priority: Severity.critical,
        raisedFrom: offer.priority,
        measurement: _eventTemplates[offer.sourceCode]?.criticalMeasurement,
      );
      _replaceOffer(raised);
      // Put the updated offer back in front of the staff member; no new offer is created.
      _incoming.add(raised);
      _notify(NotificationKind.eventEscalated, 'Priority raised to CRITICAL', '${offer.title} · ${offer.sourceCode}',
          severity: Severity.critical);
    } else {
      _replaceTask(task!.copyWith(priority: Severity.critical, raisedFrom: task.priority));
      _notify(NotificationKind.eventEscalated, 'Priority raised to CRITICAL', '${task.title} · your task is now urgent',
          severity: Severity.critical, taskId: task.taskId);
    }
    return null;
  }

  @override
  String? clearLatestEvent() {
    final latest = _latestActiveEvent();
    if (latest == null) return 'No active AI event to clear.';
    final now = clock();
    final offer = latest.offer;
    final task = latest.task;
    if (offer != null) {
      _cancelTimers(offer.offerId);
      _replaceOffer(offer.copyWith(status: OfferStatus.eventCleared, eventClearedAt: now));
      _notify(NotificationKind.eventCleared, 'Event cleared', '${offer.title} · back to normal, offer withdrawn');
    } else {
      _replaceTask(task!.copyWith(eventClearedAt: now));
      _notify(NotificationKind.eventCleared, 'Event cleared', '${task.title} · check the area, then finish your task',
          taskId: task.taskId);
    }
    return null;
  }

  @override
  Future<StaffTask?> respondToOffer(String offerId, TaskResponse response, {Duration? handleAfter, DeclineReason? reason}) async {
    if (response == TaskResponse.cannotHandle && reason == null) {
      throw ArgumentError('Cannot Handle needs a reason (BR-24).');
    }
    await _wait(latency);
    final offer = _offer(offerId);
    if (offer == null) throw const OfferNoLongerOpen();
    if (offer.status == OfferStatus.takenByOther) throw TaskAlreadyTaken(takenBy: offer.takenBy!, takenAt: offer.takenAt!);
    if (!offer.isOpen) throw const OfferNoLongerOpen();

    if (response == TaskResponse.cannotHandle) {
      // Other recipients keep being offered the task; this staff member is out of it.
      _cancelTimers(offerId);
      _replaceOffer(offer.copyWith(status: OfferStatus.declined));
      return null;
    }
    if (_eligibility.atWorkloadLimit) throw const WorkloadLimitReached();
    _cancelTimers(offerId);
    final now = clock();
    final later = response == TaskResponse.handleLater;
    _replaceOffer(offer.copyWith(status: OfferStatus.accepted));
    final task = StaffTask(
      taskId: offer.offerId.replaceFirst('offer-', 'task-'),
      origin: offer.origin,
      sourceCode: offer.sourceCode,
      title: offer.title,
      priority: offer.priority,
      zoneName: offer.zoneName,
      location: offer.location,
      instructions: offer.instructions,
      createdAt: offer.createdAt,
      acceptedAt: now,
      status: later ? TaskStatus.accepted : TaskStatus.inProgress,
      plannedStartAt: later ? now.add(handleAfter ?? const Duration(minutes: 10)) : null,
      startedAt: later ? null : now,
      cameraCode: offer.cameraCode,
      eventTypeCode: offer.eventTypeCode,
      raisedFrom: offer.raisedFrom,
    );
    _tasks.value = [task, ..._tasks.value];
    _refreshEligibility();
    _notify(
      NotificationKind.taskAccepted,
      later ? 'Task accepted for later' : 'Task started',
      '${offer.title} · ${offer.location}',
      severity: offer.priority,
      taskId: task.taskId,
    );
    return task;
  }

  // -------------------------------------------------------------------- tasks

  @override
  Stream<List<StaffTask>> watchTasks() => _tasks.stream;

  @override
  Future<StaffTask> startTask(String taskId) async {
    await _wait(latency);
    final task = _tasks.value.firstWhere((t) => t.taskId == taskId);
    if (task.status != TaskStatus.accepted) return task;
    final started = task.copyWith(status: TaskStatus.inProgress, startedAt: clock());
    _tasks.value = [for (final t in _tasks.value) t.taskId == taskId ? started : t];
    return started;
  }

  /// Demo timers keep running in the background so a demo stays on schedule.
  @override
  void setForeground(bool foreground) {}

  @override
  void completeActiveTasks() {
    // Submitted, not verified: verification belongs to the Operator.
    _tasks.value = [for (final t in _tasks.value) t.isActive ? t.copyWith(status: TaskStatus.submitted) : t];
    _refreshEligibility();
  }

  // --------------------------------------------------------------- completion

  /// Evidence per task: the draft photos and the submissions, newest first.
  final _evidence = <String, TaskEvidenceState>{};
  int _evidenceSequence = 0;

  /// Incident corrective work needs before and after photos in the demo (a cleanliness Incident); other tasks only the note.
  TaskEvidenceState _evidenceFor(StaffTask task) => _evidence[task.taskId] ??= TaskEvidenceState(
        taskId: task.taskId,
        requiresBefore: task.origin == TaskOrigin.incident,
        requiresAfter: task.origin == TaskOrigin.incident,
      );

  StaffTask _ownTask(String taskId) =>
      _tasks.value.where((t) => t.taskId == taskId).firstOrNull ?? (throw const OperationFailed('This task is no longer yours.'));

  void _requireInProgress(StaffTask task) {
    if (task.status != TaskStatus.inProgress) {
      throw OperationFailed(task.status == TaskStatus.accepted
          ? 'Start the task before adding evidence or submitting it.'
          : 'Only a task in progress can take evidence or be submitted.');
    }
  }

  TaskEvidenceState _withEvidence(TaskEvidenceState e, {List<EvidencePhoto>? drafts, List<TaskSubmission>? submissions, int? rejectionCount}) =>
      _evidence[e.taskId] = TaskEvidenceState(
        taskId: e.taskId,
        requiresBefore: e.requiresBefore,
        requiresAfter: e.requiresAfter,
        rejectionCount: rejectionCount ?? e.rejectionCount,
        drafts: drafts ?? e.drafts,
        submissions: submissions ?? e.submissions,
      );

  @override
  Future<TaskEvidenceState> taskEvidence(String taskId) async {
    await _wait(latency);
    final task = _tasks.value.where((t) => t.taskId == taskId).firstOrNull;
    return _evidence[taskId] ?? (task == null ? TaskEvidenceState(taskId: taskId, requiresBefore: false, requiresAfter: false) : _evidenceFor(task));
  }

  @override
  Future<TaskEvidenceState> uploadEvidence(String taskId, EvidenceKind kind, String filePath) async {
    await _wait(latency);
    final task = _ownTask(taskId);
    _requireInProgress(task);
    final e = _evidenceFor(task);
    final photo = EvidencePhoto(evidenceId: 'ev-${++_evidenceSequence}', kind: kind, imageUrl: filePath, capturedAt: clock());
    return _withEvidence(e, drafts: [for (final d in e.drafts) if (d.kind != kind) d, photo]);
  }

  @override
  Future<TaskEvidenceState> removeEvidence(String taskId, String evidenceId) async {
    await _wait(latency);
    final e = _evidenceFor(_ownTask(taskId));
    return _withEvidence(e, drafts: [for (final d in e.drafts) if (d.evidenceId != evidenceId) d]);
  }

  @override
  Future<StaffTask> submitTask(String taskId, String note) async {
    await _wait(latency);
    final task = _ownTask(taskId);
    if (task.status == TaskStatus.submitted) return task;
    _requireInProgress(task);
    if (note.trim().isEmpty) throw const OperationFailed('Completion note is required.');
    final e = _evidenceFor(task);
    for (final kind in EvidenceKind.values) {
      if (e.requires(kind) && e.draft(kind) == null) throw OperationFailed('This task needs ${kind == EvidenceKind.before ? 'a before photo' : 'an after photo taken when the work is done'}.');
    }
    final submission = TaskSubmission(
      submissionId: 'sub-${++_evidenceSequence}',
      note: note.trim(),
      submittedAt: clock(),
      status: ReviewStatus.pending,
      photos: e.drafts,
    );
    _withEvidence(e, drafts: const [], submissions: [submission, ...e.submissions]);
    final submitted = task.copyWith(status: TaskStatus.submitted);
    _replaceTask(submitted);
    _refreshEligibility();
    return submitted;
  }

  @override
  Future<List<int>> evidenceImage(String imageUrl) => File(imageUrl).readAsBytes();

  @override
  String? reviewLatestSubmission({required bool approve}) {
    final pending = [
      for (final t in _tasks.value)
        if (t.status == TaskStatus.submitted && _evidence[t.taskId]?.latest?.status == ReviewStatus.pending) t,
    ];
    if (pending.isEmpty) return 'No submitted task is waiting for verification. Submit one from its task detail first.';
    final task = pending.reduce((a, b) => _evidence[a.taskId]!.latest!.submittedAt.isAfter(_evidence[b.taskId]!.latest!.submittedAt) ? a : b);
    final e = _evidence[task.taskId]!;
    final latest = e.latest!;
    const reason = 'The area still needs attention. Check it again and add a clearer after photo.';
    final decided = TaskSubmission(
      submissionId: latest.submissionId,
      note: latest.note,
      submittedAt: latest.submittedAt,
      status: approve ? ReviewStatus.verified : ReviewStatus.rejected,
      rejectReason: approve ? null : reason,
      photos: latest.photos,
    );
    final rejections = e.rejectionCount + (approve ? 0 : 1);
    _withEvidence(e, submissions: [decided, ...e.submissions.skip(1)], rejectionCount: rejections);
    if (approve) {
      _replaceTask(task.copyWith(status: TaskStatus.verified));
      _notify(NotificationKind.general, 'Task verified', '${task.title}: the Operator confirmed the work.', taskId: task.taskId);
    } else if (rejections < 2) {
      _replaceTask(task.copyWith(status: TaskStatus.inProgress));
      _notify(NotificationKind.general, 'Rework needed', '${task.title}: $reason', taskId: task.taskId);
    } else {
      // BR-28: rejected twice, so the Operator gives it to someone else.
      _tasks.value = [for (final t in _tasks.value) if (t.taskId != task.taskId) t];
      _notify(NotificationKind.general, 'Task reassigned', '${task.title}: rejected twice. The Operator will assign it to someone else.');
    }
    _refreshEligibility();
    return null;
  }

  // ------------------------------------------------------------ notifications

  @override
  Stream<List<AppNotification>> watchNotifications() => _notifications.stream;

  @override
  Future<void> markAllRead() async {
    _notifications.value = [for (final n in _notifications.value) n.read ? n : n.markRead()];
  }

  // ------------------------------------------------------------------ reports

  static bool _any(String text, List<String> words) => words.any(text.contains);

  @override
  Future<ReportDraft> extractReport(String note, List<String> photoPaths, {bool fromVoice = false}) async {
    await _wait(extractLatency);
    final text = note.toLowerCase();
    // Only a checked-in shift says where the staff member is; otherwise they type the location.
    final shift = _todayShift;
    final zone = shift != null && shift.isCheckedIn ? shift.zoneName.split(' · ').first : null;
    final hasText = text.trim().isNotEmpty;

    String type = 'Other';
    if (_any(text, ['cháy', 'khói', 'chập điện', 'fire', 'smoke', 'hazard', 'nguy hiểm'])) {
      type = 'Safety hazard';
    } else if (_any(text, ['máy', 'hỏng', 'không hoạt động', 'equipment', 'scanner', 'not working', 'out of order'])) {
      type = 'Equipment fault';
    } else if (_any(text, ['vỡ', 'đổ', 'tràn', 'ướt', 'trơn', 'rò', 'spill', 'broke', 'wet', 'leak'])) {
      type = 'Spill / broken item';
    } else if (_any(text, ['chắn', 'chặn lối', 'block', 'obstruct', 'pallet'])) {
      type = 'Pathway obstruction';
    } else if (_any(text, ['bẩn', 'rác', 'dirty', 'trash', 'smell'])) {
      type = 'Cleanliness problem';
    } else if (_any(text, ['xếp hàng', 'hàng dài', 'chờ lâu', 'queue', 'line', 'waiting'])) {
      type = 'Checkout needs support';
    } else if (_any(text, ['kệ trống', 'hết hàng', 'empty shelf', 'out of stock', 'restock'])) {
      type = 'Restock or shelf tidy';
    } else if (_any(text, ['khách cần', 'lạc', 'hỗ trợ', 'help', 'assist'])) {
      type = 'Customer needs help';
    }
    final kind = kindOf(type);

    final injury = _any(text, ['ngã', 'té', 'bị thương', 'máu', 'fall', 'fell', 'injur', 'blood', 'cháy', 'fire']);
    final severity = injury ? ReportSeverity.high : (kind == ReportKind.potentialIncident ? ReportSeverity.medium : ReportSeverity.low);

    String? spot;
    final aisle = RegExp(r'(?:kệ(?: số)?|aisle)\s*(\d+)').firstMatch(text);
    final counter = RegExp(r'(?:quầy(?: số)?|counter|checkout)\s*(\d+)').firstMatch(text);
    if (aisle != null) spot = 'Aisle ${aisle.group(1)}';
    if (counter != null) spot = 'Checkout ${counter.group(1)}';
    final location = [?zone, ?spot].join(' · ');

    const titles = {
      'Spill / broken item': 'Broken item, wet floor',
      'Equipment fault': 'Equipment not working',
      'Pathway obstruction': 'Pathway blocked',
      'Cleanliness problem': 'Area needs cleaning',
      'Safety hazard': 'Safety hazard',
      'Checkout needs support': 'Long queue, checkout needs support',
      'Restock or shelf tidy': 'Shelf needs restocking',
      'Customer needs help': 'Customer needs help',
    };
    const actions = {
      'Spill / broken item': 'Place a warning sign first, then clean up the area',
      'Equipment fault': 'Switch to a working unit and report the fault',
      'Pathway obstruction': 'Clear the pathway and move the items to storage',
      'Cleanliness problem': 'Clean the area and empty nearby bins',
      'Safety hazard': 'Keep customers away and call the manager on duty',
      'Checkout needs support': 'Open another counter or call a cashier to help',
      'Restock or shelf tidy': 'Restock the shelf and face the products',
      'Customer needs help': 'Go to the customer and assist',
      'Other': 'Check the area and resolve the issue',
    };
    final firstSentence = note.trim().split(RegExp(r'[.!?\n]')).first.trim();
    final title = titles[type] != null
        ? '${titles[type]}${spot != null ? ' at ${spot.toLowerCase()}' : ''}'
        : (firstSentence.length > 60 ? '${firstSentence.substring(0, 57)}…' : firstSentence);

    return ReportDraft(
      note: note.trim(),
      photoPaths: photoPaths,
      kind: kind,
      type: type,
      location: location,
      severity: severity,
      title: title,
      suggestedAction: actions[type]!,
      fromVoice: fromVoice,
      aiFields: {
        if (hasText) ...[ReportField.kind, ReportField.type, ReportField.severity, ReportField.title, ReportField.suggestedAction],
        if (location.isNotEmpty) ReportField.location,
      },
    );
  }

  @override
  Future<ReportReceipt> submitReport(ReportDraft draft) async {
    final problem = draft.validate();
    if (problem != null) throw ArgumentError(problem);
    await _wait(latency);
    final now = clock();
    final code = 'RPT-${(_reportSequence++).toString().padLeft(4, '0')}';
    final shift = _todayShift;
    final zone = shift != null && shift.isCheckedIn ? shift.zoneName : draft.location.split(' · ').first;

    // BR-16: routine requests may create a Task without an OperationalEvent or Incident.
    // A potential incident becomes an Incident only when it meets the qualification policy
    // (demo policy: Medium or High severity); dispatch needs no Operator pre-review.
    final ReportOutcome outcome;
    if (draft.kind == ReportKind.routineRequest) {
      outcome = ReportOutcome.routineTask;
    } else if (draft.severity == ReportSeverity.low) {
      outcome = ReportOutcome.awaitingQualification;
    } else {
      outcome = ReportOutcome.incidentQualified;
    }
    final incidentCode = outcome == ReportOutcome.incidentQualified ? 'INC-${++_incidentSequence}' : null;
    final receipt = ReportReceipt(
      reportCode: code,
      outcome: outcome,
      incidentCode: incidentCode,
      title: draft.title.trim(),
      location: draft.location.trim(),
      zoneName: zone,
      offeredTo: outcome == ReportOutcome.awaitingQualification ? 0 : _teammates.length,
      submittedAt: now,
      edited: draft.edited,
    );
    _notify(
      NotificationKind.reportSent,
      switch (outcome) {
        ReportOutcome.routineTask => 'Request sent',
        ReportOutcome.incidentQualified => 'Incident $incidentCode opened',
        ReportOutcome.awaitingQualification => 'Report recorded',
      },
      switch (outcome) {
        ReportOutcome.awaitingQualification => '${receipt.title} · waiting for incident qualification',
        _ => '${receipt.title} · task offered to ${receipt.offeredTo} staff in $zone',
      },
      severity: draft.severity.severity,
    );
    return receipt;
  }

  void dispose() {
    _autoOffer?.cancel();
    for (final id in _timers.keys.toList()) {
      _cancelTimers(id);
    }
    _incoming.close();
    _shifts.close();
    _swaps.close();
    _offers.close();
    _tasks.close();
    _notifications.close();
    _eligibilityStore.close();
  }
}
