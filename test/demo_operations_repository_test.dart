import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supermarket_staff/data/demo_operations_repository.dart';
import 'package:supermarket_staff/data/models.dart';

/// Runs [body] with timers and the repository clock both driven by FakeAsync.
void withRepo(DateTime start, void Function(FakeAsync async, DemoOperationsRepository repo) body) {
  fakeAsync((async) {
    final repo = DemoOperationsRepository(
      clock: () => start.add(async.elapsed),
      latency: Duration.zero,
      extractLatency: Duration.zero,
      autoOfferAfterCheckIn: null,
      otherStaffAcceptDelay: const Duration(seconds: 4),
    );
    body(async, repo);
    repo.dispose();
  });
}

T run<T>(FakeAsync async, Future<T> future) {
  T? value;
  Object? error;
  future.then<void>((v) {
    value = v;
  }, onError: (Object e) {
    error = e;
  });
  async.flushMicrotasks();
  if (error != null) throw error!;
  return value as T;
}

Object? failure(FakeAsync async, Future<Object?> future) {
  Object? error;
  future.then<void>((_) {}, onError: (Object e) {
    error = e;
  });
  async.flushMicrotasks();
  return error;
}

String checkInToday(FakeAsync async, DemoOperationsRepository repo) {
  run(async, repo.checkIn('shift-today'));
  return 'shift-today';
}

TaskOffer openOffer(FakeAsync async, DemoOperationsRepository repo) => run(async, repo.watchOpenOffers().first).single;

void main() {
  final start = DateTime(2026, 10, 11, 14, 20);

  group('task offers', () {
    test('only reach staff who are checked in', () {
      withRepo(start, (async, repo) {
        final delivered = <TaskOffer>[];
        repo.incomingOffers().listen(delivered.add);

        expect(repo.simulateEventTask(), contains('Check in'));
        async.flushMicrotasks();
        expect(delivered, isEmpty);

        checkInToday(async, repo);
        expect(repo.simulateEventTask(), isNull);
        async.flushMicrotasks();
        expect(delivered, hasLength(1));
        expect(delivered.single.origin, TaskOrigin.operationalEvent);
        expect(delivered.single.sourceCode, startsWith('EVT-'));
      });
    });

    test('Handle Now accepts responsibility and starts work immediately', () {
      withRepo(start, (async, repo) {
        checkInToday(async, repo);
        repo.simulateEventTask();
        final offer = openOffer(async, repo);

        final task = run(async, repo.respondToOffer(offer.offerId, TaskResponse.handleNow))!;

        expect(task.status, TaskStatus.inProgress);
        expect(task.startedAt, isNotNull);
        expect(task.plannedStartAt, isNull);
        expect(run(async, repo.watchOpenOffers().first), isEmpty);
      });
    });

    test('Accept and Handle Later keeps the task Accepted with a planned start, then overdue', () {
      withRepo(start, (async, repo) {
        checkInToday(async, repo);
        repo.simulateEventTask();
        final offer = openOffer(async, repo);

        final task = run(async, repo.respondToOffer(offer.offerId, TaskResponse.handleLater, handleAfter: const Duration(minutes: 15)))!;

        expect(task.status, TaskStatus.accepted);
        expect(task.isDeferred, isTrue);
        expect(task.plannedStartAt, start.add(const Duration(minutes: 15)));
        expect(task.isOverdueAt(start.add(const Duration(minutes: 10))), isFalse);
        expect(task.isOverdueAt(start.add(const Duration(minutes: 16))), isTrue);

        final started = run(async, repo.startTask(task.taskId));
        expect(started.status, TaskStatus.inProgress);
        expect(started.isDeferred, isFalse);
      });
    });

    test('Cannot Handle needs a reason and only withdraws this staff member', () {
      withRepo(start, (async, repo) {
        checkInToday(async, repo);
        repo.simulateEventTask();
        final offer = openOffer(async, repo);

        expect(failure(async, repo.respondToOffer(offer.offerId, TaskResponse.cannotHandle)), isA<ArgumentError>());
        final result = run(async, repo.respondToOffer(offer.offerId, TaskResponse.cannotHandle, reason: DeclineReason.onBreak));

        expect(result, isNull);
        expect(run(async, repo.watchOpenOffers().first), isEmpty);
        expect(run(async, repo.watchTasks().first).where((t) => t.sourceCode == offer.sourceCode), isEmpty);
      });
    });

    test('first acceptance wins: a later response gets TaskAlreadyTaken', () {
      withRepo(start, (async, repo) {
        checkInToday(async, repo);
        repo.simulateEventTask(takenByOther: true);
        final offer = openOffer(async, repo);

        async.elapse(const Duration(seconds: 5));
        final error = failure(async, repo.respondToOffer(offer.offerId, TaskResponse.handleNow));

        expect(error, isA<TaskAlreadyTaken>());
        expect((error as TaskAlreadyTaken).takenBy, 'An Khương');
      });
    });

    test('staff at the 2-task limit stop receiving offers', () {
      withRepo(start, (async, repo) {
        checkInToday(async, repo);
        repo.simulateEventTask();
        run(async, repo.respondToOffer(openOffer(async, repo).offerId, TaskResponse.handleLater)); // seeded task + this one = 2

        expect(run(async, repo.watchEligibility().first).atWorkloadLimit, isTrue);
        expect(repo.simulateEventTask(), contains('2 active tasks'));

        repo.completeActiveTasks();
        expect(repo.simulateEventTask(), isNull);
      });
    });

    test('unanswered offers re-notify every 60 s, 3 times, then escalate to the Operator', () {
      withRepo(start, (async, repo) {
        final delivered = <TaskOffer>[];
        repo.incomingOffers().listen(delivered.add);
        checkInToday(async, repo);
        repo.simulateEventTask();
        async.flushMicrotasks();

        async.elapse(const Duration(seconds: 60));
        async.elapse(const Duration(seconds: 60));
        expect(delivered.map((o) => o.attempt), [1, 2, 3]);

        async.elapse(const Duration(seconds: 60));
        expect(run(async, repo.watchOpenOffers().first), isEmpty);
        final notes = run(async, repo.watchNotifications().first);
        expect(notes.first.kind, NotificationKind.offerEscalated);
        expect(notes.first.title, contains('Operator'));
      });
    });
  });

  group('event episodes', () {
    test('escalation raises the same open offer instead of creating another', () {
      withRepo(start, (async, repo) {
        final delivered = <TaskOffer>[];
        repo.incomingOffers().listen(delivered.add);
        checkInToday(async, repo);
        repo.simulateEventTask();
        final offer = openOffer(async, repo);
        expect(offer.priority, Severity.warning);
        expect(offer.eventTypeCode, 'LONG_QUEUE');

        expect(repo.escalateLatestEvent(), isNull);
        async.flushMicrotasks();

        final raised = openOffer(async, repo);
        expect(raised.offerId, offer.offerId);
        expect(raised.sourceCode, offer.sourceCode);
        expect(raised.priority, Severity.critical);
        expect(raised.raisedFrom, Severity.warning);
        expect(raised.measurement, '11 people waiting · 6 min');
        expect(delivered.map((o) => o.offerId).toSet(), {offer.offerId});
        expect(repo.escalateLatestEvent(), contains('already CRITICAL'));
      });
    });

    test('escalation reaches a task already accepted from the event', () {
      withRepo(start, (async, repo) {
        checkInToday(async, repo);
        repo.simulateEventTask();
        final offer = openOffer(async, repo);
        final task = run(async, repo.respondToOffer(offer.offerId, TaskResponse.handleLater, handleAfter: const Duration(minutes: 5)))!;

        expect(repo.escalateLatestEvent(), isNull);
        final updated = run(async, repo.watchTasks().first).firstWhere((t) => t.taskId == task.taskId);
        expect(updated.priority, Severity.critical);
        expect(updated.raisedFrom, Severity.warning);
        expect(updated.status, TaskStatus.accepted);
      });
    });

    test('a cleared event withdraws its open offer and stops re-offers', () {
      withRepo(start, (async, repo) {
        checkInToday(async, repo);
        repo.simulateEventTask();
        final offer = openOffer(async, repo);

        expect(repo.clearLatestEvent(), isNull);
        expect(run(async, repo.watchOpenOffers().first), isEmpty);
        final cleared = run(async, repo.watchOffer(offer.offerId).first)!;
        expect(cleared.status, OfferStatus.eventCleared);
        expect(cleared.eventClearedAt, isNotNull);

        async.elapse(TaskOffer.realertInterval * (TaskOffer.maxAttempts + 1));
        expect(run(async, repo.watchOffer(offer.offerId).first)!.status, OfferStatus.eventCleared);
        expect(failure(async, repo.respondToOffer(offer.offerId, TaskResponse.handleNow)), isA<OfferNoLongerOpen>());
        expect(repo.clearLatestEvent(), contains('No active AI event'));
      });
    });

    test('a cleared event leaves an accepted task with the staff member', () {
      withRepo(start, (async, repo) {
        checkInToday(async, repo);
        repo.simulateEventTask();
        final offer = openOffer(async, repo);
        final task = run(async, repo.respondToOffer(offer.offerId, TaskResponse.handleNow))!;

        expect(repo.clearLatestEvent(), isNull);
        final kept = run(async, repo.watchTasks().first).firstWhere((t) => t.taskId == task.taskId);
        expect(kept.status, TaskStatus.inProgress);
        expect(kept.eventClearedAt, isNotNull);
        expect(run(async, repo.watchNotifications().first).first.kind, NotificationKind.eventCleared);
      });
    });
  });

  group('staff reports', () {
    test('AI reads a Vietnamese spill note as a potential incident with location and severity', () {
      withRepo(start, (async, repo) {
        checkInToday(async, repo);
        final draft = run(async, repo.extractReport('Chai nước ngọt bị vỡ ở cuối kệ số 4, sàn trơn, có khách suýt ngã.', const []));

        expect(draft.type, 'Spill / broken item');
        expect(draft.kind, ReportKind.potentialIncident);
        expect(draft.location, 'Zone B · Aisle 4');
        expect(draft.severity, ReportSeverity.high);
        expect(draft.aiFields, containsAll(ReportField.values));
      });
    });

    test('a routine request becomes a Task without opening an Incident', () {
      withRepo(start, (async, repo) {
        checkInToday(async, repo);
        final draft = run(async, repo.extractReport('Kệ trống ở quầy 2, cần restock nước suối', const []));
        expect(draft.kind, ReportKind.routineRequest);

        final receipt = run(async, repo.submitReport(draft));
        expect(receipt.outcome, ReportOutcome.routineTask);
        expect(receipt.incidentCode, isNull);
        expect(receipt.offeredTo, 2);
        expect(receipt.edited, isFalse);
      });
    });

    test('a qualifying potential incident opens an Incident and offers a corrective Task', () {
      withRepo(start, (async, repo) {
        checkInToday(async, repo);
        final draft = run(async, repo.extractReport('Spill near checkout 3, floor is wet', const []));
        final receipt = run(async, repo.submitReport(draft));

        expect(receipt.outcome, ReportOutcome.incidentQualified);
        expect(receipt.incidentCode, startsWith('INC-'));
        expect(run(async, repo.watchNotifications().first).first.title, contains(receipt.incidentCode!));
      });
    });

    test('a low-severity potential incident waits for qualification', () {
      withRepo(start, (async, repo) {
        checkInToday(async, repo);
        final draft = run(async, repo.extractReport('Spill near checkout 3', const []))
            .edit(ReportField.severity, severity: ReportSeverity.low);
        final receipt = run(async, repo.submitReport(draft));

        expect(receipt.outcome, ReportOutcome.awaitingQualification);
        expect(receipt.offeredTo, 0);
        expect(receipt.edited, isTrue);
      });
    });

    test('changing the category re-derives the kind until the staff member picks one', () {
      withRepo(start, (async, repo) {
        checkInToday(async, repo);
        var draft = run(async, repo.extractReport('Spill near checkout 3', const []));
        draft = draft.edit(ReportField.type, text: 'Customer needs help');
        expect(draft.kind, ReportKind.routineRequest);

        draft = draft.edit(ReportField.kind, kind: ReportKind.potentialIncident).edit(ReportField.type, text: 'Restock or shelf tidy');
        expect(draft.kind, ReportKind.potentialIncident);
      });
    });

    test('a photo-only report leaves the text fields for the staff member', () {
      withRepo(start, (async, repo) {
        final draft = run(async, repo.extractReport('', const ['photo.jpg']));
        expect(draft.title, isEmpty);
        expect(draft.aiFields, isEmpty);
        expect(draft.validate(), isNotNull);
      });
    });
  });

  group('shifts', () {
    test('check-in is refused before the 15-minute window', () {
      withRepo(DateTime(2026, 10, 11, 9), (async, repo) {
        final tomorrow = run(async, repo.watchShifts().first).firstWhere((s) => s.shiftId == 'shift-1');
        final error = failure(async, repo.checkIn(tomorrow.shiftId));
        expect(error, isA<CheckInTooEarly>());
        expect((error as CheckInTooEarly).opensAt, tomorrow.start.subtract(const Duration(minutes: 15)));
      });
    });

    test('a swap request waits for the Operator, then an approval hands the shift over', () {
      withRepo(start, (async, repo) {
        final request = run(async, repo.requestShiftSwap('shift-1', SwapReason.study, 'Exam that morning'));
        expect(request.status, SwapStatus.pending);
        expect(failure(async, repo.requestShiftSwap('shift-1', SwapReason.study, '')), isA<SwapNotAllowed>());

        expect(repo.decideLatestSwap(approve: true), isNull);
        final swaps = run(async, repo.watchSwapRequests().first);
        expect(swaps.single.status, SwapStatus.approved);
        expect(swaps.single.replacement, isNotNull);
        expect(run(async, repo.watchShifts().first).any((s) => s.shiftId == 'shift-1'), isFalse);
      });
    });

    test('a started shift cannot be swapped and Other needs a note', () {
      withRepo(start, (async, repo) {
        expect(failure(async, repo.requestShiftSwap('shift-today', SwapReason.personal, '')), isA<SwapNotAllowed>());
        expect(failure(async, repo.requestShiftSwap('shift-3', SwapReason.other, '  ')), isA<SwapNotAllowed>());
      });
    });

    test('a declined swap keeps the shift and records the reason', () {
      withRepo(start, (async, repo) {
        run(async, repo.requestShiftSwap('shift-3', SwapReason.personal, ''));
        repo.decideLatestSwap(approve: false);
        final swap = run(async, repo.watchSwapRequests().first).single;
        expect(swap.status, SwapStatus.rejected);
        expect(swap.decisionNote, isNotEmpty);
        expect(run(async, repo.watchShifts().first).any((s) => s.shiftId == 'shift-3'), isTrue);
      });
    });
  });
}
