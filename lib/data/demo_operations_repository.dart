import 'dart:async';

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
/// reports become a routine Task or go through Incident qualification; shift swaps are
/// requested by Staff and decided by the Operator. Events behave like the backend's
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
  static const _replacementCandidate = 'Minh Anh';
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
        status: TaskStatus.done,
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
  Future<ShiftSwapRequest> requestShiftSwap(String shiftId, SwapReason reason, String note) async {
    await _wait(latency);
    final shift = _shifts.value.firstWhere((s) => s.shiftId == shiftId);
    if (!shift.canRequestSwapAt(clock())) {
      throw const SwapNotAllowed('This shift has already started and can no longer be changed.');
    }
    if (_swaps.value.any((r) => r.shiftId == shiftId && r.status == SwapStatus.pending)) {
      throw const SwapNotAllowed('You already have a pending swap request for this shift.');
    }
    if (reason == SwapReason.other && note.trim().isEmpty) {
      throw const SwapNotAllowed('Add a short note so the Operator understands the request.');
    }
    final request = ShiftSwapRequest(
      requestId: 'swap-${++_swapSequence}',
      shiftId: shiftId,
      reason: reason,
      note: note.trim(),
      submittedAt: clock(),
      status: SwapStatus.pending,
    );
    _swaps.value = [request, ..._swaps.value];
    _notify(NotificationKind.swapUpdated, 'Swap request sent', 'The Operator will review your ${shift.label.toLowerCase()} shift request.');
    return request;
  }

  @override
  String? decideLatestSwap({required bool approve}) {
    final pending = _swaps.value.where((r) => r.status == SwapStatus.pending).toList();
    if (pending.isEmpty) return 'There is no pending swap request.';
    final request = pending.first;
    final shift = _shifts.value.firstWhere((s) => s.shiftId == request.shiftId);
    final decided = ShiftSwapRequest(
      requestId: request.requestId,
      shiftId: request.shiftId,
      reason: request.reason,
      note: request.note,
      submittedAt: request.submittedAt,
      status: approve ? SwapStatus.approved : SwapStatus.rejected,
      replacement: approve ? _replacementCandidate : null,
      decisionNote: approve ? null : 'Zone B would drop below the minimum staff for that shift.',
    );
    _swaps.value = [for (final r in _swaps.value) r.requestId == request.requestId ? decided : r];
    if (approve) {
      _shifts.value = _shifts.value.where((s) => s.shiftId != shift.shiftId).toList();
      _notify(NotificationKind.swapUpdated, 'Swap approved', '$_replacementCandidate covers your ${shift.label.toLowerCase()} shift.');
    } else {
      _notify(NotificationKind.swapUpdated, 'Swap request declined', decided.decisionNote!);
    }
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
        recipients: ['$staffName (you)', ..._teammates],
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
      if (current.attempt >= TaskOffer.maxAttempts) {
        _replaceOffer(current.copyWith(status: OfferStatus.escalated));
        _cancelTimers(id);
        _notify(NotificationKind.offerEscalated, 'Offer passed to Operator',
            '${current.title} · nobody accepted after ${TaskOffer.maxAttempts} offers',
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

  @override
  void completeActiveTasks() {
    _tasks.value = [for (final t in _tasks.value) t.isActive ? t.copyWith(status: TaskStatus.done) : t];
    _refreshEligibility();
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
