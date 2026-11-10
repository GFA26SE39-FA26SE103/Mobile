import 'dart:async';
import 'dart:math';

import 'package:dio/dio.dart';

import '../core/api/api_exception.dart';
import 'models.dart';
import 'operations_repository.dart';

/// A server list that is polled, keeps its last good value, and replays it to new listeners.
class _Feed<T> {
  _Feed(this._load);
  final Future<T> Function() _load;
  final _controller = StreamController<T>.broadcast();
  T? _value;
  Object? _error;
  Future<void>? _loading;

  T? get value => _value;

  set value(T next) {
    _value = next;
    _error = null;
    if (!_controller.isClosed) _controller.add(next);
  }

  Stream<T> get stream async* {
    final current = _value;
    if (current != null) {
      yield current;
    } else if (_error != null) {
      yield* Stream<T>.error(_error!);
    }
    yield* _controller.stream;
  }

  /// Loads once at a time. A failure after a good load keeps the old value on screen.
  Future<void> refresh() => _loading ??= () async {
        try {
          value = await _load();
        } catch (e, s) {
          _error = e;
          if (_value == null && !_controller.isClosed) _controller.addError(e, s);
        } finally {
          _loading = null;
        }
      }();

  void close() => _controller.close();
}

/// [OperationsRepository] over the backend API (`docs/API.md`, MF-02 staff tasks and MF-04 swaps).
///
/// The API has no push channel yet (FCM is not built), so while the app is in front offers,
/// tasks, eligibility and notifications are polled every [fastPoll], shifts and swap requests
/// every [slowPoll]. Polling stops in the background and everything reloads on resume.
/// Staff reports use the real Backend API; AI suggestions remain editable until Staff confirms.
class HttpOperationsRepository implements OperationsRepository {
  HttpOperationsRepository(
    this._dio, {
    required this.clock,
    String staffName = 'You',
    bool poll = true,
    this.fastPoll = const Duration(seconds: 5),
    this.slowPoll = const Duration(seconds: 30),
  })  : _poll = poll {
    _shifts = _Feed(_loadShifts);
    _eligibility = _Feed(() async => _eligibilityOf(await _get('/api/me/eligibility')));
    _offers = _Feed(() async => [for (final o in await _get('/api/me/task-offers', {'status': 'ALL'}) as List) _offerOf(o as Map)]);
    _tasks = _Feed(() async => [
          for (final t in await _get('/api/me/tasks', {'status': 'ACCEPTED,IN_PROGRESS,SUBMITTED,VERIFIED,CANCELLED'}) as List) _taskOf(t as Map),
        ]);
    _notifications = _Feed(() async => [for (final n in await _get('/api/me/notifications') as List) _notificationOf(n as Map)]);
    _swaps = _Feed(() async => [for (final r in await _get('/api/me/swap-requests') as List) _swapOf(r as Map)]);
    _offersSub = _offers._controller.stream.listen(_deliverOffers);
    _notesSub = _notifications._controller.stream.listen(_followNotifications);
    if (poll) {
      unawaited(refresh());
      _startTimers();
    }
  }

  final bool _poll;
  final Dio _dio;
  final DateTime Function() clock;
  final Duration fastPoll;
  final Duration slowPoll;

  late final _Feed<List<Shift>> _shifts;
  late final _Feed<Eligibility> _eligibility;
  late final _Feed<List<TaskOffer>> _offers;
  late final _Feed<List<StaffTask>> _tasks;
  late final _Feed<List<AppNotification>> _notifications;
  late final _Feed<List<ShiftSwapRequest>> _swaps;
  final _incoming = StreamController<TaskOffer>.broadcast();
  final _timers = <Timer>[];
  late final StreamSubscription<List<TaskOffer>> _offersSub;
  late final StreamSubscription<List<AppNotification>> _notesSub;

  /// Last delivered attempt and priority per open offer, so a re-offer or escalation alerts again.
  final _alerted = <String, String>{};
  Set<String>? _seenNotes;

  // ------------------------------------------------------------------ plumbing

  Future<Object?> _get(String path, [Map<String, Object?>? query]) => _call(() => _dio.get<Object?>(path, queryParameters: query));

  Future<Object?> _post(String path, [Object? body]) => _call(() => _dio.post<Object?>(path, data: body ?? const <String, Object?>{}));

  /// Runs a request; failures surface as [ApiException] whose [toString] is the server's message.
  Future<Object?> _call(Future<Response<Object?>> Function() send) async {
    try {
      return (await send()).data;
    } on DioException catch (e) {
      throw _Failure(ApiException.fromDio(e));
    }
  }

  void _refreshFast() {
    _offers.refresh();
    _eligibility.refresh();
    _tasks.refresh();
    _notifications.refresh();
  }

  void _startTimers() {
    _timers.add(Timer.periodic(fastPoll, (_) => _refreshFast()));
    _timers.add(Timer.periodic(slowPoll, (_) {
      _shifts.refresh();
      _swaps.refresh();
    }));
  }

  void _stopTimers() {
    for (final t in _timers) {
      t.cancel();
    }
    _timers.clear();
  }

  bool _disposed = false;

  @override
  void setForeground(bool foreground) {
    if (!_poll || _disposed) return;
    _stopTimers();
    if (!foreground) return;
    unawaited(refresh());
    _startTimers();
  }

  @override
  Future<void> refresh() => Future.wait([
        _shifts.refresh(),
        _eligibility.refresh(),
        _offers.refresh(),
        _tasks.refresh(),
        _notifications.refresh(),
        _swaps.refresh(),
      ]);

  /// Puts an offer in front of the staff member when it first arrives, is offered again, or escalates.
  void _deliverOffers(List<TaskOffer> offers) {
    for (final o in offers) {
      if (!o.isOpen) {
        _alerted.remove(o.offerId);
        continue;
      }
      final key = '${o.attempt}|${o.priority.name}';
      if (_alerted[o.offerId] == key) continue;
      _alerted[o.offerId] = key;
      _incoming.add(o);
    }
  }

  /// Shift and swap notifications mean the schedule changed: reload it now instead of in 30 s.
  void _followNotifications(List<AppNotification> notes) {
    final seen = _seenNotes;
    _seenNotes = {for (final n in notes) n.id};
    if (seen == null) return;
    final fresh = notes.where((n) => !seen.contains(n.id));
    if (fresh.any((n) => n.kind == NotificationKind.swapUpdated || n.kind == NotificationKind.shiftChanged)) {
      _shifts.refresh();
      _swaps.refresh();
    }
  }

  static String _date(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<List<Shift>> _loadShifts() async {
    final now = clock();
    final today = DateTime(now.year, now.month, now.day);
    // From Monday, so the week strip shows earlier days of this week, to two weeks ahead.
    final from = today.subtract(Duration(days: now.weekday - 1));
    final data = await _get('/api/me/shifts', {'from': _date(from), 'to': _date(today.add(const Duration(days: 14)))});
    // A shift the Manager cancelled cannot be checked into or swapped; its notification says so.
    return [
      for (final s in data as List)
        if ((s as Map)['status'] != 'CANCELLED') _shiftOf(s),
    ]..sort((a, b) => a.start.compareTo(b.start));
  }

  // ------------------------------------------------------------------- mapping

  /// The API returns UTC; a value without an offset is UTC too. Screens work in local time.
  static DateTime _time(Object? value) {
    final text = value as String;
    final hasOffset = RegExp(r'(Z|[+-]\d\d:?\d\d)$').hasMatch(text);
    return DateTime.parse(hasOffset ? text : '${text}Z').toLocal();
  }

  static DateTime? _timeOrNull(Object? value) => value == null ? null : _time(value);

  static Severity _severity(Object? value) => switch ('$value'.toUpperCase()) {
        'CRITICAL' || 'HIGH' => Severity.critical,
        'WARNING' || 'MEDIUM' => Severity.warning,
        _ => Severity.info,
      };

  static TaskOrigin _origin(Object? value) => switch (value) {
        'INCIDENT' => TaskOrigin.incident,
        'STAFF_REPORT' => TaskOrigin.staffReport,
        'MANUAL' => TaskOrigin.manual,
        _ => TaskOrigin.operationalEvent,
      };

  static String _zones(Object? zones) {
    final names = [for (final z in (zones as List?) ?? const []) (z as Map)['zoneName'] as String];
    return names.isEmpty ? 'No zone assigned' : names.join(', ');
  }

  static Shift _shiftOf(Map json) => Shift(
        shiftId: json['shiftAssignmentId'] as String,
        start: _time(json['startsAt']),
        end: _time(json['endsAt']),
        label: json['shiftName'] as String,
        zoneName: _zones(json['zones']),
        zoneIds: [for (final z in (json['zones'] as List?) ?? const []) (z as Map)['zoneId'] as String],
        checkedInAt: _timeOrNull(json['checkInAt']),
        checkInOpensAt: _timeOrNull(json['checkInOpensAt']),
      );

  static Eligibility _eligibilityOf(Object? data) {
    final json = data as Map;
    final checkedIn = json['checkedIn'] as bool;
    return Eligibility(
      checkedIn: checkedIn,
      activeTasks: json['activeTasks'] as int,
      limit: (json['maxActiveTasks'] as int?) ?? Eligibility.workloadLimit,
      zoneName: checkedIn ? _zones(json['zones']) : null,
      shiftEndsAt: checkedIn ? _timeOrNull(json['shiftEndsAt']) : null,
    );
  }

  static String _number(num value) => value == value.roundToDouble() ? value.toInt().toString() : value.toStringAsFixed(1);

  /// "7 people" from the event's metric value and unit; empty when the task has no measurement.
  static String _measurement(Map json) {
    final value = json['metricValue'] as num?;
    if (value == null) return '';
    return [_number(value), json['measurementUnit'] as String?].whereType<String>().where((s) => s.isNotEmpty).join(' ');
  }

  static TaskOffer _offerOf(Map json) {
    final createdAt = _time(json['createdAt']);
    final attempt = (json['attempt'] ?? json['waveNumber']) as int? ?? 1;
    final closedReason = json['closedReason'] as String?;
    final status = switch (json['status']) {
      'PENDING' || 'OFFERED' => OfferStatus.open,
      'ACCEPTED' => OfferStatus.accepted,
      'DECLINED' => OfferStatus.declined,
      'EXPIRED' => OfferStatus.expired,
      _ => switch (closedReason) {
          'TAKEN_BY_OTHER' => OfferStatus.takenByOther,
          'EVENT_CLEARED' => OfferStatus.eventCleared,
          _ => OfferStatus.withdrawn,
        },
    };
    return TaskOffer(
      offerId: json['offerId'] as String,
      origin: _origin(json['origin']),
      sourceCode: json['sourceCode'] as String,
      eventTypeCode: json['eventTypeCode'] as String?,
      title: json['title'] as String,
      priority: _severity(json['priority']),
      zoneName: json['zoneName'] as String,
      location: (json['cameraName'] as String?) ?? '',
      measurement: _measurement(json),
      instructions: (json['instructions'] as String?) ?? '',
      createdAt: createdAt,
      recipients: (json['recipients'] as int?) ?? 1,
      attempt: attempt,
      maxAttempts: (json['maxAttempts'] as int?) ?? TaskOffer.defaultMaxAttempts,
      // The retry interval is a server setting; never guess the next round when it is not sent.
      nextAlertAt: _timeOrNull(json['nextAlertAt']),
      status: status,
      cameraCode: json['cameraCode'] as String?,
      eventClearedAt: _timeOrNull(json['eventClearedAt']),
      expiresAt: _timeOrNull(json['expiresAt']),
      dispatchScope: json['dispatchScope'] as String?,
    );
  }

  static StaffTask _taskOf(Map json) {
    final createdAt = _time(json['createdAt']);
    return StaffTask(
      taskId: json['taskId'] as String,
      origin: _origin(json['origin']),
      sourceCode: json['sourceCode'] as String,
      eventTypeCode: json['eventTypeCode'] as String?,
      title: json['title'] as String,
      priority: _severity(json['priority']),
      raisedFrom: json['raisedFrom'] == null ? null : _severity(json['raisedFrom']),
      zoneName: json['zoneName'] as String,
      location: '',
      instructions: (json['instructions'] as String?) ?? '',
      createdAt: createdAt,
      acceptedAt: _timeOrNull(json['acceptedAt']) ?? _timeOrNull(json['assignedAt']) ?? createdAt,
      status: switch (json['status']) {
        'ACCEPTED' => TaskStatus.accepted,
        'IN_PROGRESS' => TaskStatus.inProgress,
        'SUBMITTED' => TaskStatus.submitted,
        'VERIFIED' => TaskStatus.verified,
        'CANCELLED' => TaskStatus.cancelled,
        final other => throw FormatException('Unknown task status $other'),
      },
      plannedStartAt: _timeOrNull(json['plannedStartAt']),
      startedAt: _timeOrNull(json['startedAt']),
      cameraCode: json['cameraCode'] as String?,
      eventClearedAt: _timeOrNull(json['eventClearedAt']),
    );
  }

  static NotificationKind _kind(String type) => switch (type) {
        'TASK_OFFER' => NotificationKind.taskOffered,
        'TASK_ASSIGNED' => NotificationKind.taskAccepted,
        'TASK_OFFER_WITHDRAWN' => NotificationKind.offerTaken,
        'TASK_NEEDS_ASSIGNMENT' => NotificationKind.offerEscalated,
        'TASK_PRIORITY_RAISED' => NotificationKind.eventEscalated,
        'EVENT_CLEARED' => NotificationKind.eventCleared,
        _ when type.startsWith('SWAP_') => NotificationKind.swapUpdated,
        _ when type.startsWith('SHIFT_') => NotificationKind.shiftChanged,
        _ => NotificationKind.general,
      };

  static AppNotification _notificationOf(Map json) => AppNotification(
        id: json['notificationId'] as String,
        kind: _kind(json['type'] as String),
        title: json['title'] as String,
        body: json['message'] as String,
        createdAt: _time(json['createdAt']),
        severity: json['severity'] == null ? null : _severity(json['severity']),
        taskId: json['taskId'] as String?,
        read: json['readAt'] != null,
      );

  static SwapShift _swapShiftOf(Map json) => SwapShift(
        shiftId: json['shiftAssignmentId'] as String,
        ownerId: json['userId'] as String,
        label: json['shiftName'] as String,
        start: _time(json['startsAt']),
        end: _time(json['endsAt']),
        zoneName: _zones(json['zones']),
      );

  static String? _name(Object? person) => person == null ? null : (person as Map)['fullName'] as String;

  static ShiftSwapRequest _swapOf(Object? data) {
    final json = data as Map;
    final requester = json['requester'] as Map;
    final target = json['target'] as Map?;
    return ShiftSwapRequest(
      requestId: json['swapRequestId'] as String,
      type: SwapType.fromCode(json['type'] as String?),
      status: SwapStatus.fromCode(json['status'] as String),
      requesterId: requester['userId'] as String,
      requesterName: requester['fullName'] as String,
      requesterShift: _swapShiftOf(json['requesterShift'] as Map),
      targetId: target?['userId'] as String?,
      targetName: target?['fullName'] as String?,
      targetShift: json['targetShift'] == null ? null : _swapShiftOf(json['targetShift'] as Map),
      reason: SwapReason.fromCode(json['reasonCode'] as String?),
      note: (json['note'] as String?) ?? '',
      submittedAt: _time(json['createdAt']),
      expiresAt: _timeOrNull(json['expiresAt']),
      targetRespondedAt: _timeOrNull(json['targetRespondedAt']),
      decidedBy: _name(json['decidedBy']),
      decidedAt: _timeOrNull(json['decidedAt']),
      decisionNote: json['decisionNote'] as String?,
      cancelledBy: _name(json['cancelledBy']),
      cancelledAt: _timeOrNull(json['cancelledAt']),
      cancellationReason: json['cancellationReason'] as String?,
      sentByMe: json['viewerRole'] == 'REQUESTER',
      canCancel: json['canCancel'] as bool? ?? false,
      canRespond: json['canRespond'] as bool? ?? false,
    );
  }

  static SwapCandidates _candidatesOf(Object? data) {
    final json = data as Map;
    return SwapCandidates(
      shiftId: json['shiftAssignmentId'] as String,
      type: SwapType.fromCode(json['type'] as String?),
      deadline: _time(json['deadline']),
      hiddenCount: json['hiddenCount'] as int,
      candidates: [
        for (final c in json['candidates'] as List)
          SwapCandidate(
            userId: ((c as Map)['colleague'] as Map)['userId'] as String,
            fullName: (c['colleague'] as Map)['fullName'] as String,
            shift: c['shift'] == null ? null : _swapShiftOf(c['shift'] as Map),
            weeklyHoursAfter: (c['weeklyHoursAfter'] as num).toDouble(),
            recommended: c['recommended'] as bool? ?? (c['weeklyHoursAfter'] as num) <= 40,
          ),
      ],
    );
  }

  // -------------------------------------------------------------------- shifts

  @override
  Stream<List<Shift>> watchShifts() => _shifts.stream;

  @override
  Stream<Eligibility> watchEligibility() => _eligibility.stream;

  @override
  Future<Shift> checkIn(String shiftId) async {
    try {
      final shift = _shiftOf(await _post('/api/me/shifts/$shiftId/check-in') as Map);
      final current = _shifts.value;
      if (current != null) _shifts.value = [for (final s in current) s.shiftId == shiftId ? shift : s];
      unawaited(_eligibility.refresh());
      return shift;
    } on _Failure catch (f) {
      if (f.code == 'CHECK_IN_TOO_EARLY') {
        final shift = _shifts.value?.where((s) => s.shiftId == shiftId).firstOrNull;
        throw CheckInTooEarly(shift?.checkInOpensAt ?? clock());
      }
      throw OperationFailed(f.message);
    }
  }

  // --------------------------------------------------------------------- swaps

  @override
  Stream<List<ShiftSwapRequest>> watchSwapRequests() => _swaps.stream;

  /// Every swap refusal (rules, deadline, state) is shown to the staff member as is.
  Future<T> _swapCall<T>(Future<T> Function() body) async {
    try {
      return await body();
    } on _Failure catch (f) {
      throw SwapNotAllowed(f.message);
    }
  }

  /// Puts [request] at the top of the cached list right away, then reloads in the background.
  ShiftSwapRequest _keep(ShiftSwapRequest request) {
    final current = _swaps.value ?? const <ShiftSwapRequest>[];
    _swaps.value = [request, for (final r in current) if (r.requestId != request.requestId) r];
    unawaited(_swaps.refresh());
    return request;
  }

  @override
  Future<SwapCandidates> swapCandidates(String shiftId, SwapType type) =>
      _swapCall(() async => _candidatesOf(await _get('/api/me/shifts/$shiftId/swap-candidates', {'type': type.code})));

  @override
  Future<ShiftSwapRequest> requestShiftSwap({
    required String shiftId,
    required SwapType type,
    required String targetUserId,
    String? targetShiftId,
    SwapReason? reason,
    String note = '',
  }) =>
      _swapCall(() async => _keep(_swapOf(await _post('/api/swap-requests', {
            'requesterShiftAssignmentId': shiftId,
            'type': type.code,
            'targetUserId': targetUserId,
            'targetShiftAssignmentId': type == SwapType.swap ? targetShiftId : null,
            'reasonCode': reason?.code,
            'note': note.trim().isEmpty ? null : note.trim(),
          }))));

  @override
  Future<ShiftSwapRequest> requestManagerCover({required String shiftId, SwapReason? reason, String note = ''}) =>
      _swapCall(() async => _keep(_swapOf(await _post('/api/me/swap-requests/manager-help', {
            'requesterShiftAssignmentId': shiftId,
            'reasonCode': reason?.code,
            'note': note.trim().isEmpty ? null : note.trim(),
          }))));

  @override
  Future<ShiftSwapRequest> respondToSwap(String requestId, {required bool accept}) =>
      _swapCall(() async => _keep(_swapOf(await _post('/api/swap-requests/$requestId/respond', {'accept': accept}))));

  @override
  Future<ShiftSwapRequest> cancelSwap(String requestId, {String? reason}) =>
      _swapCall(() async => _keep(_swapOf(await _post('/api/swap-requests/$requestId/cancel', {'reason': reason}))));

  // -------------------------------------------------------------------- offers

  @override
  Stream<TaskOffer> incomingOffers() => _incoming.stream;

  @override
  Stream<List<TaskOffer>> watchOpenOffers() => _offers.stream.map((all) => all.where((o) => o.isOpen).toList());

  @override
  Stream<TaskOffer?> watchOffer(String offerId) => _offers.stream.map((all) => all.where((o) => o.offerId == offerId).firstOrNull);

  /// "Lan accepted this task at 2026-10-20T08:00:00Z." from the 409 TASK_ALREADY_TAKEN detail.
  static TaskAlreadyTaken _taken(String detail) {
    final match = RegExp(r'^(.*) accepted this task at (\S+?)\.?$').firstMatch(detail.trim());
    if (match == null) return const TaskAlreadyTaken();
    DateTime? at;
    try {
      at = _time(match.group(2));
    } on FormatException {
      at = null;
    }
    return TaskAlreadyTaken(takenBy: match.group(1), takenAt: at);
  }

  @override
  Future<StaffTask?> respondToOffer(String offerId, TaskResponse response, {Duration? handleAfter, DeclineReason? reason}) async {
    if (response == TaskResponse.cannotHandle && reason == null) {
      throw ArgumentError('Cannot Handle needs a reason (BR-24).');
    }
    try {
      final result = await _post('/api/task-offers/$offerId/respond', {
        'response': switch (response) {
          TaskResponse.handleNow => 'HANDLE_NOW',
          TaskResponse.handleLater => 'HANDLE_LATER',
          TaskResponse.cannotHandle => 'CANNOT_HANDLE',
        },
        'plannedStartAt': response == TaskResponse.handleLater
            ? clock().add(handleAfter ?? const Duration(minutes: 10)).toUtc().toIso8601String()
            : null,
        'reason': reason?.code,
      }) as Map;
      final task = result['task'] == null ? null : _taskOf(result['task'] as Map);
      if (task != null) {
        final current = _tasks.value ?? const <StaffTask>[];
        _tasks.value = [task, for (final t in current) if (t.taskId != task.taskId) t];
      }
      _refreshFast();
      return task;
    } on _Failure catch (f) {
      unawaited(_offers.refresh());
      throw switch (f.code) {
        'TASK_ALREADY_TAKEN' => _taken(f.message),
        'OFFER_CLOSED' || 'OFFER_EXPIRED' => const OfferNoLongerOpen(),
        'WORKLOAD_LIMIT' => const WorkloadLimitReached(),
        _ => OperationFailed(f.message),
      };
    }
  }

  // --------------------------------------------------------------------- tasks

  @override
  Stream<List<StaffTask>> watchTasks() => _tasks.stream;

  @override
  Future<StaffTask> startTask(String taskId) async {
    try {
      final task = _taskOf(await _post('/api/tasks/$taskId/start') as Map);
      final current = _tasks.value ?? const <StaffTask>[];
      _tasks.value = [for (final t in current) t.taskId == taskId ? task : t];
      return task;
    } on _Failure catch (f) {
      unawaited(_tasks.refresh());
      throw OperationFailed(f.message);
    }
  }

  // ---------------------------------------------------------------- completion

  static EvidencePhoto _photoOf(Map json) => EvidencePhoto(
        evidenceId: json['evidenceId'] as String,
        kind: EvidenceKind.fromCode(json['evidenceType'] as String),
        imageUrl: json['imageUrl'] as String,
        capturedAt: _time(json['capturedAt']),
      );

  static TaskEvidenceState _evidenceOf(Object? data) {
    final json = data as Map;
    return TaskEvidenceState(
      taskId: json['taskId'] as String,
      requiresBefore: json['requiresBeforePhoto'] as bool,
      requiresAfter: json['requiresAfterPhoto'] as bool,
      rejectionCount: (json['rejectionCount'] as int?) ?? 0,
      drafts: [for (final p in json['drafts'] as List) _photoOf(p as Map)],
      submissions: [
        for (final s in json['submissions'] as List)
          TaskSubmission(
            submissionId: (s as Map)['submissionId'] as String,
            note: s['note'] as String,
            submittedAt: _time(s['submittedAt']),
            status: switch (s['reviewStatus']) {
              'VERIFIED' => ReviewStatus.verified,
              'REJECTED' => ReviewStatus.rejected,
              _ => ReviewStatus.pending,
            },
            rejectReason: s['rejectReason'] as String?,
            photos: [for (final p in s['photos'] as List) _photoOf(p as Map)],
          ),
      ],
    );
  }

  Future<T> _completionCall<T>(Future<T> Function() body) async {
    try {
      return await body();
    } on _Failure catch (f) {
      unawaited(_tasks.refresh());
      throw OperationFailed(f.message);
    }
  }

  @override
  Future<TaskEvidenceState> taskEvidence(String taskId) => _completionCall(() async => _evidenceOf(await _get('/api/tasks/$taskId/evidence')));

  @override
  Future<TaskEvidenceState> uploadEvidence(String taskId, EvidenceKind kind, String filePath) => _completionCall(() async {
        final name = filePath.split(RegExp(r'[\\/]')).last;
        final png = name.toLowerCase().endsWith('.png');
        final form = FormData.fromMap({
          'type': kind.code,
          'file': await MultipartFile.fromFile(filePath, filename: name, contentType: DioMediaType('image', png ? 'png' : 'jpeg')),
        });
        return _evidenceOf(await _post('/api/tasks/$taskId/evidence', form));
      });

  @override
  Future<TaskEvidenceState> removeEvidence(String taskId, String evidenceId) =>
      _completionCall(() async => _evidenceOf(await _call(() => _dio.delete<Object?>('/api/tasks/$taskId/evidence/$evidenceId'))));

  @override
  Future<StaffTask> submitTask(String taskId, String note) => _completionCall(() async {
        await _post('/api/tasks/$taskId/submit', {'note': note.trim()});
        await _tasks.refresh();
        _refreshFast();
        return (_tasks.value ?? const <StaffTask>[]).firstWhere((t) => t.taskId == taskId,
            orElse: () => throw const OperationFailed('The task was submitted but could not be reloaded. Pull to refresh.'));
      });

  @override
  Future<List<int>> evidenceImage(String imageUrl) => _completionCall(() async {
        final data = await _call(() => _dio.get<Object?>(imageUrl, options: Options(responseType: ResponseType.bytes)));
        return (data as List<int>?) ?? const <int>[];
      });

  // ------------------------------------------------------------- notifications

  @override
  Stream<List<AppNotification>> watchNotifications() => _notifications.stream;

  @override
  Future<void> markAllRead() async {
    final current = _notifications.value;
    if (current != null) _notifications.value = [for (final n in current) n.read ? n : n.markRead()];
    try {
      await _post('/api/me/notifications/read-all');
    } on _Failure {
      // The next poll shows what the server still has unread.
    }
    unawaited(_notifications.refresh());
  }

  // ------------------------------------------------------------------- reports

  @override
  Future<ReportDraft> extractReport(String note, List<String> photoPaths, {bool fromVoice = false, String? voicePath}) =>
      _extractLiveReport(note, photoPaths, fromVoice: fromVoice, voicePath: voicePath);

  Future<ReportDraft> _extractLiveReport(String note, List<String> photoPaths, {bool fromVoice = false, String? voicePath}) async {
    final typesData = await _get('/api/staff-reports/incident-types') as List;
    final tasksData = await _get('/api/staff-reports/task-types') as List;
    final zonesData = await _get('/api/staff-reports/zones') as List;
    final types = [for (final raw in typesData) ReportOption(raw['code'] as String, raw['name'] as String,
        allowedTaskCodes: (raw['allowedTaskTypeCodes'] as List? ?? []).cast<String>())];
    final tasks = [for (final raw in tasksData) ReportOption(raw['code'] as String, raw['name'] as String,
        routineEligible: raw['routineEligible'] == true)];
    final zones = [for (final raw in zonesData) ReportZoneOption(raw['zoneId'] as String, raw['name'] as String, raw['floorName'] as String)];
    Map<String, dynamic>? ai;
    try {
      final form = FormData.fromMap({'note': note});
      for (final path in photoPaths) {
        form.files.add(MapEntry('photos', await MultipartFile.fromFile(path,
            contentType: DioMediaType('image', path.toLowerCase().endsWith('.png') ? 'png' : 'jpeg'))));
      }
      if (voicePath != null) {
        form.files.add(MapEntry('voice', await MultipartFile.fromFile(voicePath,
            contentType: DioMediaType('audio', 'mp4'))));
      }
      ai = ((await _call(() => _dio.post<Object?>('/api/staff-reports/draft', data: form))) as Map).cast<String, dynamic>();
    } on _Failure {
      // The draft can still be filled manually; never invent a classification.
    }
    final category = ai?['reportCategory'] as String?;
    final kind = category == 'POTENTIAL_INCIDENT' ? ReportKind.potentialIncident : ReportKind.routineRequest;
    final code = kind == ReportKind.potentialIncident ? (ai?['incidentTypeCode'] as String?) : null;
    final selected = types.where((x) => x.code == code).firstOrNull;
    final suggested = (ai?['suggestedTaskTypeCodes'] as List? ?? []).whereType<String>().toList();
    final validIncidentTasks = selected?.allowedTaskCodes ?? const <String>[];
    final taskCodes = kind == ReportKind.potentialIncident && selected != null
        ? suggested.where((code) => validIncidentTasks.contains(code) && tasks.any((t) => t.code == code)).take(8).toList()
        : const <String>[];
    final routine = kind == ReportKind.routineRequest
        ? tasks.where((t) => t.routineEligible && suggested.contains(t.code)).firstOrNull : null;
    final suggestedZone = zones.where((z) => z.id == ai?['suggestedZoneId']).firstOrNull;
    final random = Random.secure();
    String hex(int size) => List.generate(size, (_) => random.nextInt(16).toRadixString(16)).join();
    final id = '${hex(8)}-${hex(4)}-4${hex(3)}-${(8 + random.nextInt(4)).toRadixString(16)}${hex(3)}-${hex(12)}';
    final transcript = ai?['transcript'] as String?;
    final combinedNote = [note.trim(), if (transcript != null) transcript.trim()].where((s) => s.isNotEmpty).join('\n');
    return ReportDraft(
      note: combinedNote, photoPaths: photoPaths, kind: kind, type: (selected ?? routine)?.name ?? '',
      location: (ai?['locationDescription'] as String?) ?? '', severity: ReportSeverity.low,
      title: (ai?['title'] as String?) ?? '', suggestedAction: '', fromVoice: fromVoice,
      description: (ai?['description'] as String?) ?? combinedNote,
      aiFields: ai == null ? {} : {if (selected != null) ReportField.type, if (category != null) ReportField.kind,
        if ((ai['title'] as String? ?? '').isNotEmpty) ReportField.title,
        if ((ai['locationDescription'] as String? ?? '').isNotEmpty) ReportField.location},
      live: true, typeCode: (selected ?? routine)?.code, incidentTypes: types, taskTypes: tasks, zones: zones, reportId: id,
      taskTypeCodes: taskCodes, zoneId: suggestedZone?.id,
      confidenceLevel: ai?['confidenceLevel'] as String?, evidence: ai?['evidence'] as String?,
      voicePath: voicePath,
    );
  }

  @override
  Future<ReportReceipt> submitReport(ReportDraft draft) async {
    if (!draft.live || draft.zoneId == null || draft.typeCode == null || draft.reportId == null) {
      throw StateError('Select a Zone and category before submitting.');
    }
    if (draft.kind == ReportKind.potentialIncident && draft.duplicateDecision == null) {
      final duplicates = await _get('/api/staff-reports/duplicates', {'zoneId': draft.zoneId, 'incidentTypeCode': draft.typeCode}) as List;
      if (duplicates.isNotEmpty) throw const ReportOverlapRequired(incident: true);
    }
    if (draft.kind == ReportKind.routineRequest && draft.routineTaskDecision == null) {
      final overlaps = await _get('/api/staff-reports/routine-overlaps', {'zoneId': draft.zoneId, 'taskTypeCode': draft.typeCode}) as List;
      if (overlaps.isNotEmpty) throw const ReportOverlapRequired(incident: false);
    }
    final fields = <String, dynamic>{
      'reportId': draft.reportId, 'zoneId': draft.zoneId, 'title': draft.title.trim(),
      'description': draft.description.trim(), 'locationDescription': draft.location.trim(),
      'reportCategory': draft.kind == ReportKind.potentialIncident ? 'POTENTIAL_INCIDENT' : 'ROUTINE_REQUEST',
    };
    if (draft.kind == ReportKind.potentialIncident) fields['incidentTypeCode'] = draft.typeCode;
    if (draft.confirmedScenarioCode != null) fields['confirmedScenarioCode'] = draft.confirmedScenarioCode;
    if (draft.duplicateDecision != null) fields['duplicateDecision'] = draft.duplicateDecision;
    if (draft.routineTaskDecision != null) fields['routineTaskDecision'] = draft.routineTaskDecision;
    final form = FormData.fromMap(fields);
    for (final code in draft.kind == ReportKind.routineRequest ? [draft.typeCode!] : draft.taskTypeCodes) {
      form.fields.add(MapEntry('taskTypeCodes', code));
    }
    for (final path in draft.photoPaths) {
      form.files.add(MapEntry('photos', await MultipartFile.fromFile(path,
          contentType: DioMediaType('image', path.toLowerCase().endsWith('.png') ? 'png' : 'jpeg'))));
    }
    if (draft.voicePath != null) {
      form.files.add(MapEntry('voice', await MultipartFile.fromFile(draft.voicePath!,
          contentType: DioMediaType('audio', 'mp4'))));
    }
    final data = (await _call(() => _dio.post<Object?>('/api/staff-reports', data: form))) as Map;
    final incidentId = data['incidentId'] as String?;
    final receipt = ReportReceipt(
      reportCode: data['reportId'] as String, outcome: draft.kind == ReportKind.routineRequest ? ReportOutcome.routineTask :
          incidentId != null ? ReportOutcome.incidentQualified : ReportOutcome.awaitingQualification,
      incidentCode: incidentId, title: data['title'] as String, location: draft.location,
      zoneName: draft.zones.where((z) => z.id == draft.zoneId).firstOrNull?.name ?? 'Selected Zone', offeredTo: 0,
      submittedAt: DateTime.tryParse(data['confirmedAt'] as String? ?? '') ?? clock(), edited: draft.edited,
    );
    return receipt;
  }

  void dispose() {
    _disposed = true;
    _stopTimers();
    _offersSub.cancel();
    _notesSub.cancel();
    _incoming.close();
    for (final feed in [_shifts, _eligibility, _offers, _tasks, _notifications, _swaps]) {
      feed.close();
    }
  }
}

class ReportOverlapRequired implements Exception {
  const ReportOverlapRequired({required this.incident});
  final bool incident;
}

/// A failed call inside this repository, before it is turned into a domain exception.
class _Failure implements Exception {
  _Failure(this.error);
  final ApiException error;
  String? get code => error.code;
  String get message => error.message;

  @override
  String toString() => error.message;
}
