import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supermarket_staff/core/api/api_exception.dart';
import 'package:supermarket_staff/data/http_operations_repository.dart';
import 'package:supermarket_staff/data/models.dart';

/// A canned backend: each route answers with JSON, or with [Problem] for an error.
class FakeApi implements HttpClientAdapter {
  final routes = <String, Object? Function(RequestOptions request)>{};
  final calls = <RequestOptions>[];

  void on(String route, Object? Function(RequestOptions request) answer) => routes[route] = answer;

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    calls.add(options);
    if (requestStream != null) await requestStream.drain<void>();
    final answer = routes['${options.method} ${options.path}'];
    final headers = {
      Headers.contentTypeHeader: ['application/json'],
    };
    if (answer == null) return ResponseBody.fromString('{"title":"Not found"}', 404, headers: headers);
    final result = answer(options);
    if (result is Problem) {
      return ResponseBody.fromString(jsonEncode({'code': result.code, 'detail': result.detail}), result.status, headers: headers);
    }
    return ResponseBody.fromString(jsonEncode(result), 200, headers: headers);
  }

  @override
  void close({bool force = false}) {}
}

class Problem {
  const Problem(this.status, this.code, this.detail);
  final int status;
  final String code;
  final String detail;
}

/// 2026-10-20 10:00 local: every time below is relative to this.
final now = DateTime(2026, 10, 20, 10);
String utc(DateTime local) => local.toUtc().toIso8601String();

Map<String, Object?> shiftJson({String id = 'sa-1', DateTime? start, DateTime? checkInAt}) {
  final s = start ?? now.add(const Duration(days: 3));
  return {
    'shiftAssignmentId': id,
    'shiftId': 'tpl-1',
    'shiftName': 'Evening',
    'workDate': '2026-10-23',
    'startsAt': utc(s),
    'endsAt': utc(s.add(const Duration(hours: 8))),
    'checkInOpensAt': utc(s.subtract(const Duration(minutes: 15))),
    'checkInAt': checkInAt == null ? null : utc(checkInAt),
    'checkOutAt': null,
    'status': 'SCHEDULED',
    'zones': [
      {'zoneId': 'z-b', 'zoneName': 'Zone B'},
    ],
  };
}

Map<String, Object?> offerJson({int attempt = 1, String status = 'OFFERED', String? closedReason}) => {
      'offerId': 'off-1',
      'taskId': 'task-1',
      'origin': 'OPERATIONAL_EVENT',
      'sourceCode': 'EVT-1A2B3C4D',
      'eventTypeCode': 'LONG_QUEUE',
      'title': 'Long queue at checkout',
      'instructions': 'Open one more counter',
      'priority': 'WARNING',
      'zoneId': 'z-b',
      'zoneName': 'Zone B',
      'cameraCode': 'CAM-03',
      'cameraName': 'Checkout 3',
      'metricValue': 7.0,
      'measurementMode': 'QUEUE_LENGTH',
      'measurementUnit': 'people',
      'createdAt': utc(now),
      'recipients': 3,
      'attempt': attempt,
      'maxAttempts': 4,
      'nextAlertAt': utc(now.add(const Duration(seconds: 60))),
      'status': status,
      'closedReason': closedReason,
      'eventClearedAt': null,
    };

Map<String, Object?> taskJson({String status = 'IN_PROGRESS'}) => {
      'taskId': 'task-1',
      'origin': 'OPERATIONAL_EVENT',
      'sourceCode': 'EVT-1A2B3C4D',
      'eventTypeCode': 'LONG_QUEUE',
      'title': 'Long queue at checkout',
      'instructions': null,
      'priority': 'CRITICAL',
      'raisedFrom': 'WARNING',
      'zoneId': 'z-b',
      'zoneName': 'Zone B',
      'cameraCode': 'CAM-03',
      'status': status,
      'assignmentType': 'OFFER',
      'assigneeUserId': 'me',
      'assigneeName': 'Linh',
      'createdAt': utc(now),
      'assignedAt': utc(now),
      'acceptedAt': utc(now.add(const Duration(minutes: 1))),
      'plannedStartAt': null,
      'startedAt': utc(now.add(const Duration(minutes: 1))),
      'submittedAt': null,
      'eventClearedAt': null,
      'needsAssignment': false,
      'updatedAt': utc(now),
    };

Map<String, Object?> person(String id, String name) => {'userId': id, 'fullName': name};

Map<String, Object?> swapShiftJson(String id, String owner, DateTime start) => {
      'shiftAssignmentId': id,
      'userId': owner,
      'shiftName': 'Evening',
      'workDate': '2026-10-23',
      'startsAt': utc(start),
      'endsAt': utc(start.add(const Duration(hours: 8))),
      'zones': [
        {'zoneId': 'z-b', 'zoneName': 'Zone B'},
      ],
    };

Map<String, Object?> swapJson({String status = 'PENDING_PEER', String viewerRole = 'REQUESTER'}) {
  final mine = now.add(const Duration(days: 3));
  return {
    'swapRequestId': 'swap-1',
    'type': 'SWAP',
    'status': status,
    'requester': person('me', 'Linh'),
    'requesterShift': swapShiftJson('sa-1', 'me', mine),
    'target': person('u-lan', 'Hoàng Lan'),
    'targetShift': swapShiftJson('sa-9', 'u-lan', mine.add(const Duration(days: 2))),
    'reasonCode': 'STUDY',
    'note': 'Exam',
    'createdAt': utc(now),
    'expiresAt': utc(mine.subtract(const Duration(hours: 24))),
    'targetRespondedAt': null,
    'decidedBy': null,
    'decidedAt': null,
    'decisionNote': null,
    'cancelledBy': null,
    'cancelledAt': null,
    'cancellationReason': null,
    'viewerRole': viewerRole,
    'canCancel': viewerRole == 'REQUESTER',
    'canRespond': viewerRole == 'TARGET' && status == 'PENDING_PEER',
    'canDecide': false,
    'checks': [],
    'updatedAt': utc(now),
  };
}

({HttpOperationsRepository repo, FakeApi api}) build({DateTime? currentTime}) {
  final api = FakeApi()
    ..on('GET /api/me/shifts', (_) => [shiftJson()])
    ..on('GET /api/me/eligibility', (_) => {
          'checkedIn': true,
          'shiftAssignmentId': 'sa-0',
          'shiftEndsAt': utc(now.add(const Duration(hours: 4))),
          'activeTasks': 1,
          'maxActiveTasks': 2,
          'zones': [
            {'zoneId': 'z-b', 'zoneName': 'Zone B'},
          ],
        })
    ..on('GET /api/me/task-offers', (_) => [offerJson()])
    ..on('GET /api/me/tasks', (_) => [taskJson()])
    ..on('GET /api/me/notifications', (_) => [
          {
            'notificationId': 'n-1',
            'type': 'SWAP_PEER_ACCEPTED',
            'title': 'Hoàng Lan accepted',
            'message': 'Waiting for the Manager',
            'severity': null,
            'taskId': null,
            'eventId': null,
            'createdAt': utc(now),
            'readAt': null,
          },
        ])
    ..on('GET /api/me/swap-requests', (_) => [swapJson()]);
  final dio = Dio(BaseOptions(baseUrl: 'http://api.test'))..httpClientAdapter = api;
  final repo = HttpOperationsRepository(dio, clock: () => currentTime ?? now, poll: false);
  addTearDown(repo.dispose);
  return (repo: repo, api: api);
}

void main() {
  test('real report draft uses catalog, requires staff selections, and submits to backend', () async {
    final (:repo, :api) = build();
    api.on('GET /api/staff-reports/incident-types', (_) => [
      {'code': 'SPILL_BROKEN_EQUIPMENT', 'name': 'Spill', 'allowedTaskTypeCodes': ['TT-06']}
    ]);
    api.on('GET /api/staff-reports/task-types', (_) => [
      {'code': 'TT-06', 'name': 'Clean spill', 'routineEligible': false}
    ]);
    api.on('GET /api/staff-reports/zones', (_) => [
      {'zoneId': 'z-b', 'name': 'Zone B', 'floorName': 'Floor 1'}
    ]);
    api.on('POST /api/staff-reports/draft', (_) => {
      'title': 'Wet floor', 'locationDescription': 'Aisle 2',
      'reportCategory': 'POTENTIAL_INCIDENT', 'incidentTypeCode': 'SPILL_BROKEN_EQUIPMENT',
      'needsReview': true, 'suggestedTaskTypeCodes': ['TT-06'], 'suggestedZoneId': 'z-b',
      'confidenceLevel': 'MEDIUM', 'evidence': 'Zone B mentioned in note',
    });
    api.on('GET /api/staff-reports/duplicates', (_) => []);
    api.on('POST /api/staff-reports', (_) => {
      'reportId': '00000000-0000-4000-8000-000000000001', 'title': 'Wet floor',
      'incidentId': '00000000-0000-4000-8000-000000000002', 'confirmedAt': utc(now),
    });

    var draft = await repo.extractReport('wet floor in Zone B', []);
    expect(draft.live, isTrue);
    expect(draft.typeCode, 'SPILL_BROKEN_EQUIPMENT');
    expect(draft.zoneId, 'z-b');
    expect(draft.taskTypeCodes, ['TT-06']);
    expect(draft.confidenceLevel, 'MEDIUM');
    expect(draft.evidence, 'Zone B mentioned in note');
    expect(draft.validate(), isNull);
    final receipt = await repo.submitReport(draft);
    expect(receipt.preview, isFalse);
    expect(receipt.outcome, ReportOutcome.incidentQualified);
    expect(api.calls.any((r) => r.path == '/api/staff-reports'), isTrue);
  });

  test('AI outage keeps a manual draft, never an invented IncidentType', () async {
    final (:repo, :api) = build();
    api.on('GET /api/staff-reports/incident-types', (_) => []);
    api.on('GET /api/staff-reports/task-types', (_) => []);
    api.on('GET /api/staff-reports/zones', (_) => []);
    api.on('POST /api/staff-reports/draft', (_) => const Problem(503, 'REPORT_AI_UNAVAILABLE', 'Unavailable'));
    final draft = await repo.extractReport('wet floor', []);
    expect(draft.live, isTrue);
    expect(draft.aiFields, isEmpty);
    expect(draft.typeCode, isNull);
  });

  test('a failed AI draft keeps the manual form and says why', () async {
    final (:repo, :api) = build();
    api.on('GET /api/staff-reports/incident-types', (_) => []);
    api.on('GET /api/staff-reports/task-types', (_) => []);
    api.on('GET /api/staff-reports/zones', (_) => []);
    api.on('POST /api/staff-reports/draft', (_) => const Problem(503, 'REPORT_AI_NOT_CONFIGURED', 'Report AI is not configured; fill the report manually.'));
    final draft = await repo.extractReport('wet floor', []);
    expect(draft.aiFields, isEmpty);
    expect(draft.aiIssue, contains('REPORT_AI_NOT_CONFIGURED'));
    expect(draft.aiIssue, contains('not set up on the server'));
    expect(draft.withSelection(zoneId: 'z').aiIssue, draft.aiIssue);
    expect(reportAiIssue(const ApiException(status: 422, code: 'REPORT_PHOTO_INVALID', message: 'Use a JPEG or PNG photo of at most 10 MB.')),
        'Use a JPEG or PNG photo of at most 10 MB. (REPORT_PHOTO_INVALID)');
  });

  test('recorded audio reaches draft and final report; transcript is reviewable', () async {
    final (:repo, :api) = build();
    final directory = await Directory('.dart_tool').createTemp('report-voice-test');
    addTearDown(() => directory.delete(recursive: true));
    final voice = File('${directory.path}/note.m4a')..writeAsBytesSync([0, 0, 0, 0, 0x66, 0x74, 0x79, 0x70]);
    api.on('GET /api/staff-reports/incident-types', (_) => []);
    api.on('GET /api/staff-reports/task-types', (_) => [
      {'code': 'TT-11', 'name': 'Clean area', 'routineEligible': true}
    ]);
    api.on('GET /api/staff-reports/zones', (_) => [
      {'zoneId': 'z-b', 'name': 'Zone B', 'floorName': 'Floor 1'}
    ]);
    api.on('POST /api/staff-reports/draft', (request) {
      final form = request.data as FormData;
      expect(form.files.single.key, 'voice');
      expect(form.files.single.value.contentType.toString(), 'audio/mp4');
      return {
        'title': 'Clean aisle', 'description': 'Clean aisle', 'reportCategory': 'ROUTINE_REQUEST',
        'suggestedTaskTypeCodes': ['TT-11'], 'transcript': 'Please clean aisle four.', 'needsReview': true,
      };
    });
    api.on('GET /api/staff-reports/routine-overlaps', (_) => []);
    api.on('POST /api/staff-reports', (request) {
      final form = request.data as FormData;
      expect(form.files.single.key, 'voice');
      expect(form.fields.singleWhere((entry) => entry.key == 'description').value, 'Clean aisle');
      return {
        'reportId': '00000000-0000-4000-8000-000000000001', 'title': 'Clean aisle', 'confirmedAt': utc(now),
      };
    });
    final draft = await repo.extractReport('', [], fromVoice: true, voicePath: voice.path);
    expect(draft.note, 'Please clean aisle four.');
    expect(draft.voicePath, voice.path);
    expect(draft.typeCode, 'TT-11');
    expect(draft.withSelection(zoneId: 'z-b').validate(), isNull);
    await repo.submitReport(draft.withSelection(zoneId: 'z-b'));
  });

  test('checked-in single Zone defaults without marking Staff edit; ambiguous zones do not', () {
    const draft = ReportDraft(note: 'wet floor', photoPaths: [], kind: ReportKind.potentialIncident,
      type: '', location: '', title: '', suggestedAction: '', aiFields: {},
      live: true, zones: [ReportZoneOption('z-b', 'Zone B', 'Floor 1')]);
    final checkedIn = Shift(shiftId: 'shift', start: now, end: now.add(const Duration(hours: 8)),
      label: 'Morning', zoneName: 'Zone B', zoneIds: const ['z-b'], checkedInAt: now);
    final result = draft.defaultZoneFromShift(checkedIn);
    expect(result.zoneId, 'z-b');
    expect(result.edited, isFalse);
    final ambiguous = Shift(shiftId: 'shift', start: now, end: now.add(const Duration(hours: 8)),
      label: 'Morning', zoneName: 'Multiple', zoneIds: const ['z-b', 'z-c'], checkedInAt: now);
    expect(draft.defaultZoneFromShift(ambiguous).zoneId, isNull);
  });

  test('similar Incident requires explicit Staff decision before POST', () async {
    final (:repo, :api) = build();
    api.on('GET /api/staff-reports/incident-types', (_) => [
      {'code': 'SAFETY_HAZARD', 'name': 'Safety hazard', 'allowedTaskTypeCodes': ['TT-12']}
    ]);
    api.on('GET /api/staff-reports/task-types', (_) => [
      {'code': 'TT-12', 'name': 'Isolate area', 'routineEligible': false}
    ]);
    api.on('GET /api/staff-reports/zones', (_) => [
      {'zoneId': 'z-b', 'name': 'Zone B', 'floorName': 'Floor 1'}
    ]);
    api.on('POST /api/staff-reports/draft', (_) => {
      'title': 'Exposed wire', 'reportCategory': 'POTENTIAL_INCIDENT', 'incidentTypeCode': 'SAFETY_HAZARD',
    });
    api.on('GET /api/staff-reports/duplicates', (_) => [{'incidentId': 'inc-1', 'taskIds': []}]);
    final draft = (await repo.extractReport('exposed wire', [])).withSelection(zoneId: 'z-b', taskTypeCodes: ['TT-12']);
    await expectLater(repo.submitReport(draft), throwsA(isA<ReportOverlapRequired>()));
    expect(api.calls.where((r) => r.path == '/api/staff-reports'), isEmpty);
  });

  test('confirmed electrical-wire report requires both mandatory task types', () {
    final draft = ReportDraft(note: 'wire', photoPaths: const [], kind: ReportKind.potentialIncident,
      type: 'Safety hazard', location: '', title: 'Exposed wire',
      suggestedAction: '', aiFields: const {}, live: true, typeCode: 'SAFETY_HAZARD',
      zoneId: 'z-b', taskTypeCodes: const ['TT-12'], confirmedScenarioCode: 'EXPOSED_ELECTRICAL_WIRE');
    expect(draft.validate(), 'Exposed electrical wire requires TT-12 and TT-13.');
    expect(draft.withSelection(taskTypeCodes: ['TT-12', 'TT-13']).validate(), isNull);
  });
  test('maps shifts, eligibility, tasks and notifications from the API', () async {
    final (:repo, :api) = build();
    await repo.refresh();

    final shift = (await repo.watchShifts().first).single;
    expect(shift.shiftId, 'sa-1');
    expect(shift.label, 'Evening');
    expect(shift.zoneName, 'Zone B');
    expect(shift.zoneIds, ['z-b']);
    expect(shift.start, now.add(const Duration(days: 3)));
    expect(shift.isCheckedIn, isFalse);
    expect(shift.placeDetail, isEmpty);
    // The shifts call covers this week from Monday onwards.
    expect(api.calls.firstWhere((c) => c.path == '/api/me/shifts').queryParameters['from'], '2026-10-19');

    final eligibility = await repo.watchEligibility().first;
    expect(eligibility.checkedIn, isTrue);
    expect(eligibility.zoneName, 'Zone B');
    expect(eligibility.atWorkloadLimit, isFalse);

    final task = (await repo.watchTasks().first).single;
    expect(task.status, TaskStatus.inProgress);
    expect(task.priority, Severity.critical);
    expect(task.raisedFrom, Severity.warning);
    expect(task.instructions, isEmpty);

    final note = (await repo.watchNotifications().first).single;
    expect(note.kind, NotificationKind.swapUpdated);
    expect(note.read, isFalse);
  });

  test('a time without an offset is read as UTC', () async {
    final (:repo, :api) = build();
    final startUtc = now.add(const Duration(days: 1)).toUtc();
    api.on('GET /api/me/shifts', (_) => [shiftJson()..['startsAt'] = startUtc.toIso8601String().replaceAll('Z', '')]);
    await repo.refresh();
    expect((await repo.watchShifts().first).single.start.toUtc(), startUtc);
  });

  test('includes Sunday assignments when loading shifts early on Monday', () async {
    final monday = DateTime(2026, 11, 30, 0, 9);
    final (:repo, :api) = build(currentTime: monday);
    api.on('GET /api/me/shifts', (_) => []);

    await repo.refresh();

    expect(api.calls.firstWhere((c) => c.path == '/api/me/shifts').queryParameters['from'], '2026-11-29');
  });

  test('an open offer is delivered once, and again when it is re-offered', () async {
    final (:repo, :api) = build();
    final delivered = <TaskOffer>[];
    final sub = repo.incomingOffers().listen(delivered.add);
    addTearDown(sub.cancel);

    await repo.refresh();
    await repo.refresh();
    await Future<void>.delayed(Duration.zero);
    expect(delivered, hasLength(1));
    final offer = delivered.single;
    expect(offer.measurement, '7 people');
    expect(offer.location, 'Checkout 3');
    expect(offer.recipients, 3);
    expect(offer.maxAttempts, 4);

    api.on('GET /api/me/task-offers', (_) => [offerJson(attempt: 2)]);
    await repo.refresh();
    await Future<void>.delayed(Duration.zero);
    expect(delivered.map((o) => o.attempt), [1, 2]);

    api.on('GET /api/me/task-offers', (_) => [offerJson(attempt: 2, status: 'WITHDRAWN', closedReason: 'TAKEN_BY_OTHER')]);
    await repo.refresh();
    expect((await repo.watchOffer('off-1').first)!.status, OfferStatus.takenByOther);
    expect(await repo.watchOpenOffers().first, isEmpty);
  });

  test('Handle later sends the planned start; refusals become domain errors', () async {
    final (:repo, :api) = build();
    await repo.refresh();
    api.on('POST /api/task-offers/off-1/respond', (_) => {'response': 'HANDLE_LATER', 'task': taskJson(status: 'ACCEPTED')});

    final task = await repo.respondToOffer('off-1', TaskResponse.handleLater, handleAfter: const Duration(minutes: 15));
    expect(task!.status, TaskStatus.accepted);
    final body = api.calls.last.data as Map;
    expect(body['response'], 'HANDLE_LATER');
    expect(DateTime.parse(body['plannedStartAt'] as String), now.add(const Duration(minutes: 15)).toUtc());

    api.on('POST /api/task-offers/off-1/respond',
        (_) => const Problem(409, 'TASK_ALREADY_TAKEN', 'An Khương accepted this task at 2026-10-20T03:01:00.0000000Z.'));
    final taken = await repo.respondToOffer('off-1', TaskResponse.handleNow).then<Object?>((_) => null, onError: (Object e) => e);
    expect(taken, isA<TaskAlreadyTaken>());
    expect((taken as TaskAlreadyTaken).takenBy, 'An Khương');
    expect(taken.takenAt!.toUtc(), DateTime.utc(2026, 10, 20, 3, 1));

    api.on('POST /api/task-offers/off-1/respond', (_) => const Problem(409, 'WORKLOAD_LIMIT', 'You already have 2 active tasks.'));
    await expectLater(repo.respondToOffer('off-1', TaskResponse.handleNow), throwsA(isA<WorkloadLimitReached>()));

    api.on('POST /api/task-offers/off-1/respond', (_) => const Problem(409, 'NOT_ON_SHIFT', 'Check in first.'));
    await expectLater(
      repo.respondToOffer('off-1', TaskResponse.handleNow),
      throwsA(isA<OperationFailed>().having((e) => e.message, 'message', 'Check in first.')),
    );
  });

  test('check-in too early carries the opening time; a check-in updates the shift', () async {
    final (:repo, :api) = build();
    await repo.refresh();
    api.on('POST /api/me/shifts/sa-1/check-in', (_) => const Problem(422, 'CHECK_IN_TOO_EARLY', 'Too early.'));
    final early = await repo.checkIn('sa-1').then<Object?>((_) => null, onError: (Object e) => e);
    expect((early as CheckInTooEarly).opensAt, now.add(const Duration(days: 3)).subtract(const Duration(minutes: 15)));

    api.on('POST /api/me/shifts/sa-1/check-in', (_) => shiftJson(checkInAt: now));
    await repo.checkIn('sa-1');
    expect((await repo.watchShifts().first).single.checkedInAt, now);
  });

  test('swaps: candidates, sending a request, and a refused request', () async {
    final (:repo, :api) = build();
    await repo.refresh();

    final request = (await repo.watchSwapRequests().first).single;
    expect(request.sentByMe, isTrue);
    expect(request.status, SwapStatus.pendingPeer);
    expect(request.otherName, 'Hoàng Lan');
    expect(request.iGet?.shiftId, 'sa-9');
    expect(request.reason, SwapReason.study);

    api.on('GET /api/me/shifts/sa-1/swap-candidates', (r) => {
          'shiftAssignmentId': 'sa-1',
          'type': r.queryParameters['type'],
          'deadline': utc(now.add(const Duration(days: 2))),
          'candidates': [
            {
              'colleague': person('u-lan', 'Hoàng Lan'),
              'shift': swapShiftJson('sa-9', 'u-lan', now.add(const Duration(days: 5))),
              'weeklyHoursAfter': 32.0,
            },
          ],
          'hiddenCount': 2,
        });
    final options = await repo.swapCandidates('sa-1', SwapType.swap);
    expect(api.calls.last.queryParameters['type'], 'SWAP');
    expect(options.hiddenCount, 2);
    expect(options.candidates.single.shift!.shiftId, 'sa-9');

    api.on('POST /api/swap-requests', (_) => swapJson());
    await repo.requestShiftSwap(shiftId: 'sa-1', type: SwapType.cover, targetUserId: 'u-lan', targetShiftId: 'sa-9', reason: SwapReason.health);
    final body = api.calls.last.data as Map;
    expect(body['type'], 'COVER');
    expect(body['targetShiftAssignmentId'], isNull);
    expect(body['reasonCode'], 'HEALTH');
    expect(body['note'], isNull);

    api.on('POST /api/swap-requests/swap-1/respond', (_) => const Problem(409, 'SWAP_EXPIRED', 'This request has expired.'));
    await expectLater(
      repo.respondToSwap('swap-1', accept: true),
      throwsA(isA<SwapNotAllowed>().having((e) => e.message, 'message', 'This request has expired.')),
    );
  });

  test('staff can ask the Manager to choose cover without selecting a colleague', () async {
    final (:repo, :api) = build();
    await repo.refresh();
    api.on('POST /api/me/swap-requests/manager-help', (_) => {
          ...swapJson(status: 'PENDING_MANAGER'),
          'type': 'COVER',
          'target': null,
          'targetShift': null,
        });

    final request = await repo.requestManagerCover(
      shiftId: 'sa-1',
      reason: SwapReason.health,
      note: 'Cannot find anyone',
    );

    expect(request.managerNeedsToAssign, isTrue);
    expect(request.targetId, isNull);
    expect(api.calls.last.data, {
      'requesterShiftAssignmentId': 'sa-1',
      'reasonCode': 'HEALTH',
      'note': 'Cannot find anyone',
    });
  });

  test('a received request is mine to answer, and a failed first load shows as an error', () async {
    final (:repo, :api) = build();
    api.on('GET /api/me/swap-requests', (_) => [swapJson(viewerRole: 'TARGET')]);
    api.on('GET /api/me/shifts', (_) => const Problem(503, 'SWAP_SCHEMA_NOT_READY', 'Shift data is not ready.'));
    await repo.refresh();

    final received = (await repo.watchSwapRequests().first).single;
    expect(received.sentByMe, isFalse);
    expect(received.canRespond, isTrue);
    expect(received.otherName, 'Linh');
    expect(received.iGive?.shiftId, 'sa-9');

    await expectLater(repo.watchShifts().first, throwsA(predicate((e) => '$e' == 'Shift data is not ready.')));
  });

  test('submitted is not verified, cancelled is finished, and the shift end limits Handle later', () async {
    final (:repo, :api) = build();
    api.on('GET /api/me/tasks', (_) => [
          taskJson(status: 'SUBMITTED'),
          taskJson(status: 'VERIFIED')..['taskId'] = 'task-2',
          taskJson(status: 'CANCELLED')..['taskId'] = 'task-3',
        ]);
    await repo.refresh();

    final tasks = await repo.watchTasks().first;
    expect(tasks.map((t) => t.status), [TaskStatus.submitted, TaskStatus.verified, TaskStatus.cancelled]);
    expect(tasks.any((t) => t.isActive), isFalse);
    expect(api.calls.firstWhere((c) => c.path == '/api/me/tasks').queryParameters['status'], contains('CANCELLED'));
    expect((await repo.watchEligibility().first).shiftEndsAt, now.add(const Duration(hours: 4)));
  });

  test('offer outcomes and the last round follow the server, with nothing guessed', () async {
    final (:repo, :api) = build();
    Map<String, Object?> o(String id, String status, {String? reason, int attempt = 1}) =>
        offerJson(attempt: attempt, status: status, closedReason: reason)..['offerId'] = id;
    api.on('GET /api/me/task-offers', (_) => [
          o('last', 'OFFERED', attempt: 3)..['nextAlertAt'] = null,
          o('expired', 'EXPIRED', reason: 'NO_ACCEPTANCE'),
          o('cleared', 'WITHDRAWN', reason: 'EVENT_CLEARED'),
          o('manual', 'WITHDRAWN', reason: 'MANUALLY_ASSIGNED'),
          o('declined', 'DECLINED'),
        ]);
    await repo.refresh();
    Future<TaskOffer> get(String id) async => (await repo.watchOffer(id).first)!;

    final last = await get('last');
    expect((last.isOpen, last.attempt, last.maxAttempts, last.nextAlertAt), (true, 3, 4, null));
    expect((await get('expired')).status, OfferStatus.expired);
    expect((await get('cleared')).status, OfferStatus.eventCleared);
    // Withdrawn by the Operator is not "taken by someone else".
    expect((await get('manual')).status, OfferStatus.withdrawn);
    expect((await get('declined')).status, OfferStatus.declined);
  });

  test('reads TaskOffer V7 statuses and fields', () async {
    final (:repo, :api) = build();
    Map<String, Object?> o(String id, String status, {String? reason}) {
      final json = offerJson(status: status, closedReason: reason)..['offerId'] = id;
      json.remove('attempt');
      return json
        ..['waveNumber'] = 2
        ..['dispatchScope'] = 'SAME_FLOOR'
        ..['expiresAt'] = utc(now.add(const Duration(seconds: 45)));
    }

    api.on('GET /api/me/task-offers', (_) => [
          o('open', 'PENDING'),
          o('taken', 'CANCELLED', reason: 'TAKEN_BY_OTHER'),
          o('cleared', 'CANCELLED', reason: 'EVENT_CLEARED'),
          o('other', 'CANCELLED'),
          o('late', 'EXPIRED'),
        ]);
    await repo.refresh();
    Future<TaskOffer> get(String id) async => (await repo.watchOffer(id).first)!;

    final open = await get('open');
    expect((open.status, open.attempt, open.dispatchScope, open.roundLabel), (OfferStatus.open, 2, 'SAME_FLOOR', 'offer round 2'));
    expect(open.expiresAt, now.add(const Duration(seconds: 45)));
    expect((await get('taken')).status, OfferStatus.takenByOther);
    expect((await get('cleared')).status, OfferStatus.eventCleared);
    expect((await get('other')).status, OfferStatus.withdrawn);
    expect((await get('late')).status, OfferStatus.expired);
  });

  test('Handle now and Cannot handle send exactly the documented payload', () async {
    final (:repo, :api) = build();
    await repo.refresh();
    api.on('POST /api/task-offers/off-1/respond', (r) => {'response': (r.data as Map)['response'], 'task': null});

    await repo.respondToOffer('off-1', TaskResponse.handleNow);
    expect(api.calls.last.data, {'response': 'HANDLE_NOW', 'plannedStartAt': null, 'reason': null});

    expect(await repo.respondToOffer('off-1', TaskResponse.cannotHandle, reason: DeclineReason.unavailable), isNull);
    expect(api.calls.last.data, {'response': 'CANNOT_HANDLE', 'plannedStartAt': null, 'reason': 'UNAVAILABLE'});
  });

  test('a shift the Manager cancelled is left out of My shifts', () async {
    final (:repo, :api) = build();
    api.on('GET /api/me/shifts', (_) => [shiftJson(), shiftJson(id: 'sa-2')..['status'] = 'CANCELLED']);
    await repo.refresh();
    expect((await repo.watchShifts().first).map((s) => s.shiftId), ['sa-1']);
  });

  test('polling runs only in the foreground and reloads on resume', () async {
    final api = build().api;
    final dio = Dio(BaseOptions(baseUrl: 'http://api.test'))..httpClientAdapter = api;
    final repo = HttpOperationsRepository(dio, clock: () => now, fastPoll: const Duration(milliseconds: 20), slowPoll: const Duration(hours: 1));
    addTearDown(repo.dispose);
    int offerCalls() => api.calls.where((c) => c.path == '/api/me/task-offers').length;

    await Future<void>.delayed(const Duration(milliseconds: 70));
    expect(offerCalls(), greaterThan(1));

    repo.setForeground(false);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    final paused = offerCalls();
    await Future<void>.delayed(const Duration(milliseconds: 80));
    expect(offerCalls(), paused);

    // Well before the next 20 ms tick, so this call comes from the reload on resume.
    repo.setForeground(true);
    await Future<void>.delayed(const Duration(milliseconds: 5));
    expect(offerCalls(), greaterThan(paused));
  });

  test('evidence: parse the state, upload a photo as multipart, submit the note, map refusals', () async {
    final (:repo, :api) = build();
    Map<String, Object?> photo(String id, String type) => {'evidenceId': id, 'evidenceType': type, 'imageUrl': '/api/tasks/task-1/evidence/$id/image', 'capturedAt': utc(now)};
    const reportPhotoUrl = '/api/tasks/task-1/report-photos/photo-1/image';
    final state = {
      'taskId': 'task-1',
      'taskStatus': 'IN_PROGRESS',
      'requiresBeforePhoto': true,
      'requiresAfterPhoto': true,
      'rejectionCount': 1,
      'drafts': [photo('ev-2', 'AFTER_PHOTO')],
      'reportPhotos': [{'mediaId': 'photo-1', 'imageUrl': reportPhotoUrl}],
      'submissions': [
        {
          'submissionId': 'sub-1',
          'submittedByUserId': 'me',
          'submittedByName': 'Linh',
          'note': 'Mopped',
          'submittedAt': utc(now.subtract(const Duration(minutes: 5))),
          'reviewStatus': 'REJECTED',
          'rejectReason': 'Still wet',
          'photos': [photo('ev-1', 'BEFORE_PHOTO')],
        },
      ],
    };
    api.on('GET /api/tasks/task-1/evidence', (_) => state);
    final evidence = await repo.taskEvidence('task-1');
    expect((evidence.requiresBefore, evidence.requiresAfter, evidence.rejectionCount, evidence.inRework), (true, true, 1, true));
    expect(evidence.draft(EvidenceKind.after)!.evidenceId, 'ev-2');
    expect(evidence.reportPhotoUrls, [reportPhotoUrl]);
    expect(evidence.latest!.rejectReason, 'Still wet');
    expect(evidence.latest!.photos.single.kind, EvidenceKind.before);

    final file = File('${Directory.systemTemp.createTempSync('ev').path}/after.jpg')..writeAsBytesSync([0xff, 0xd8, 0xff, 0xe0]);
    api.on('POST /api/tasks/task-1/evidence', (_) => state);
    await repo.uploadEvidence('task-1', EvidenceKind.before, file.path);
    final form = api.calls.last.data as FormData;
    expect(form.fields.single, isA<MapEntry<String, String>>().having((f) => '${f.key}=${f.value}', 'field', 'type=BEFORE_PHOTO'));
    expect(form.files.single.value.contentType.toString(), 'image/jpeg');

    api.on('POST /api/tasks/task-1/submit', (_) => const Problem(422, 'EVIDENCE_REQUIRED', 'This task needs a before photo.'));
    await expectLater(
      repo.submitTask('task-1', 'Done'),
      throwsA(isA<OperationFailed>().having((e) => e.message, 'message', 'This task needs a before photo.')),
    );
    api.on('POST /api/tasks/task-1/submit', (_) => {'taskId': 'task-1', 'status': 'SUBMITTED'});
    api.on('GET /api/me/tasks', (_) => [taskJson(status: 'SUBMITTED')]);
    expect((await repo.submitTask('task-1', '  Mopped and dried  ')).status, TaskStatus.submitted);
    expect(api.calls.firstWhere((c) => c.path == '/api/tasks/task-1/submit' && c.data is Map && (c.data as Map)['note'] == 'Mopped and dried'), isNotNull);
  });

  test('Review 2 evidence: an Incident task may send a note with the missing-photo reason; lane and rejections are read', () async {
    final (:repo, :api) = build();
    final incident = taskJson()
      ..['origin'] = 'INCIDENT'
      ..['verificationMode'] = 'MANUAL'
      ..['verificationMethod'] = 'OPERATOR_EVIDENCE'
      ..['rejectionCount'] = 1;
    final camera = taskJson()
      ..['taskId'] = 'task-2'
      ..['verificationMode'] = 'AUTO';
    api.on('GET /api/me/tasks', (_) => [incident, camera]);
    await repo.refresh();
    final tasks = await repo.watchTasks().first;
    final first = tasks.firstWhere((t) => t.taskId == 'task-1');
    expect((first.verificationMode, first.rejectionCount, first.acceptsNoteInsteadOfPhoto), (VerificationMode.manual, 1, true));
    expect(tasks.firstWhere((t) => t.taskId == 'task-2').verificationMode, VerificationMode.auto);

    api.on('GET /api/tasks/task-1/evidence', (_) => {
          'taskId': 'task-1',
          'taskStatus': 'SUBMITTED',
          'verificationMode': 'MANUAL',
          'verificationMethod': 'OPERATOR_EVIDENCE',
          'requiresBeforePhoto': false,
          'requiresAfterPhoto': false,
          'rejectionCount': 0,
          'drafts': [],
          'submissions': [
            {
              'submissionId': 'sub-1',
              'submittedByUserId': 'me',
              'note': 'Roped off the area and mopped',
              'submittedAt': utc(now),
              'reviewStatus': 'PENDING',
              'rejectReason': null,
              'missingPhotoReason': 'Phone camera broken',
              'photos': [],
            },
          ],
        });
    final evidence = await repo.taskEvidence('task-1');
    expect((evidence.verificationMode, evidence.requiresAfter, evidence.latest!.missingPhotoReason),
        (VerificationMode.manual, false, 'Phone camera broken'));

    api.on('POST /api/tasks/task-1/submit', (_) => {'taskId': 'task-1', 'status': 'SUBMITTED'});
    await repo.submitTask('task-1', ' Roped off and mopped ', missingPhotoReason: ' Phone camera broken ');
    expect(api.calls.lastWhere((c) => c.path == '/api/tasks/task-1/submit').data, {'note': 'Roped off and mopped', 'missingPhotoReason': 'Phone camera broken'});
    // With an after photo an Incident note may be empty: nothing extra is sent.
    await repo.submitTask('task-1', '  ');
    expect(api.calls.lastWhere((c) => c.path == '/api/tasks/task-1/submit').data, <String, Object?>{});
  });

  test('verification notifications are told apart from other task updates', () async {
    final (:repo, :api) = build();
    Map<String, Object?> note(String id, String type) => {
          'notificationId': id, 'type': type, 'title': type, 'message': '', 'severity': null,
          'taskId': 'task-1', 'eventId': null, 'createdAt': utc(now), 'readAt': null,
        };
    api.on('GET /api/me/notifications', (_) => [
          note('n1', 'TASK_VERIFIED'),
          note('n2', 'TASK_AUTO_VERIFIED'),
          note('n3', 'TASK_REJECTED'),
          note('n4', 'TASK_VERIFICATION_EXCEPTION'),
        ]);
    await repo.refresh();
    final kinds = {for (final n in await repo.watchNotifications().first) n.id: n.kind};
    expect(kinds, {
      'n1': NotificationKind.taskVerified,
      'n2': NotificationKind.taskVerified,
      'n3': NotificationKind.taskRejected,
      'n4': NotificationKind.general,
    });
  });
}
