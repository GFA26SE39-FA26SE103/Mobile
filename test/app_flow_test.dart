import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supermarket_staff/core/providers.dart';
import 'package:supermarket_staff/core/push_notifications.dart';
import 'package:supermarket_staff/core/theme/app_colors.dart';
import 'package:supermarket_staff/core/theme/app_theme.dart';
import 'package:supermarket_staff/data/models.dart';
import 'package:supermarket_staff/data/providers.dart';
import 'package:supermarket_staff/features/auth/auth_repository.dart';
import 'package:supermarket_staff/features/report/report_screens.dart';
import 'package:supermarket_staff/features/report/voice_input.dart';
import 'package:supermarket_staff/features/tasks/tasks_screens.dart';

import 'helpers.dart';

Future<void> goTab(WidgetTester tester, String label) async {
  await tester.tap(find.descendant(of: find.byType(NavigationBar), matching: find.text(label)));
  await settle(tester);
}

Future<void> checkIn(WidgetTester tester) async {
  await goTab(tester, 'Shifts');
  await tester.tap(find.widgetWithText(FilledButton, 'Check in'));
  await settle(tester);
}

class _FakeVoiceInput implements VoiceInput {
  const _FakeVoiceInput(this.transcript);

  final String? transcript;

  @override
  Future<bool> start(
    void Function(String words, bool isFinal) onText, {
    void Function()? onDone,
  }) async {
    if (transcript == null) return false;
    onText(transcript!, true);
    onDone?.call();
    return true;
  }

  @override
  Future<void> stop() async {}
}

void main() {
  testWidgets('an in-progress Clean Spill task shows its original report photo', (tester) async {
    const taskId = 'clean-spill';
    const photoUrl = '/api/tasks/$taskId/report-photos/photo-1/image';
    final now = DateTime(2026, 11, 22, 10);
    final task = StaffTask(
      taskId: taskId,
      origin: TaskOrigin.incident,
      sourceCode: 'INC-SPILL',
      title: 'Clean Spill',
      priority: Severity.warning,
      zoneName: 'Household Aisle',
      location: 'First Floor',
      instructions: 'Clean the spill.',
      createdAt: now,
      acceptedAt: now,
      status: TaskStatus.inProgress,
    );
    await tester.pumpWidget(ProviderScope(
      overrides: [
        tasksProvider.overrideWith((ref) => Stream.value([task])),
        taskEvidenceProvider(taskId).overrideWith((ref) async => const TaskEvidenceState(
          taskId: taskId, requiresBefore: false, requiresAfter: false, reportPhotoUrls: [photoUrl],
        )),
        evidenceImageProvider(photoUrl).overrideWith((ref) async => base64Decode(
          'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+a/2sAAAAASUVORK5CYII=',
        )),
      ],
      child: MaterialApp(
        theme: buildTheme(AppColors.light, Brightness.light),
        home: const TaskDetailScreen(taskId: taskId),
      ),
    ));
    await settle(tester);
    expect(text('Report photos'), findsOneWidget);
    expect(find.byType(Image), findsOneWidget);
    await tapVisible(tester, find.byTooltip('Open report photo 1'));
    await settle(tester);
    expect(find.widgetWithText(AppBar, 'Report photo 1'), findsOneWidget);
  });

  appTest('report dictation fills the note and opens review', (tester, app) async {
    await goTab(tester, 'Report');
    expect(text('Type, speak or add a photo.'), findsOneWidget);
    expect(text('Record note'), findsNothing);
    expect(text('Take photo'), findsOneWidget);
    expect(text('From gallery'), findsOneWidget);
    expect(text('You are not checked in'), findsOneWidget);
    expect(text('You can still report. Add the location yourself on the next screen.'), findsNothing);
    expect(find.textContaining('No Incident or Task is created until you confirm'), findsNothing);
    final aiButton = find.widgetWithText(FilledButton, 'Let AI fill the report');
    expect(tester.widget<FilledButton>(aiButton).onPressed, isNull);
    await tester.tap(text('Speak'));
    await settle(tester);
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text, 'Broken bottle in aisle 4');
    expect(tester.widget<FilledButton>(aiButton).onPressed, isNotNull);
    await tapVisible(tester, aiButton);
    await settle(tester);
    expect(find.widgetWithText(AppBar, 'Review report'), findsOneWidget);
    final draft = app.container.read(reportDraftProvider);
    expect(draft?.fromVoice, isTrue);
    expect(draft?.note, 'Broken bottle in aisle 4');
  }, voiceInput: const _FakeVoiceInput('Broken bottle in aisle 4'));

  appTest('unavailable dictation keeps the report unready and shows an error', (tester, app) async {
    await goTab(tester, 'Report');
    await tester.tap(text('Speak'));
    await settle(tester);
    expect(text('Voice input is not available. Allow microphone access, or type the report instead.'), findsOneWidget);
    final aiButton = find.widgetWithText(FilledButton, 'Let AI fill the report');
    await tester.scrollUntilVisible(aiButton, 150, scrollable: find.byType(Scrollable).first);
    expect(tester.widget<FilledButton>(aiButton).onPressed, isNull);
  }, voiceInput: const _FakeVoiceInput(null));
  appTest('sign-in validates input, then lands a staff member on My tasks', signedIn: false, (tester, app) async {
    expect(text('Welcome back'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
    await tester.pump();
    expect(text('Enter your work email.'), findsOneWidget);
    expect(text('Enter your password.'), findsOneWidget);

    await tester.enterText(find.byType(TextFormField).at(0), 'linh@store.test');
    await tester.enterText(find.byType(TextFormField).at(1), MockAuthRepository.password);
    await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
    await tester.pump();
    expect(text('Signing in…'), findsOneWidget);
    await settle(tester, const Duration(milliseconds: 200), 10);

    expect(find.widgetWithText(AppBar, 'My tasks'), findsOneWidget);
    expect(text('Off shift'), findsOneWidget);
  });

  testWidgets('empty task tabs keep their titles and the check-in action', (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        tasksProvider.overrideWith((ref) => Stream.value(const <StaffTask>[])),
        openOffersProvider.overrideWith((ref) => Stream.value(const <TaskOffer>[])),
        eligibilityProvider.overrideWith(
          (ref) => Stream.value(const Eligibility(checkedIn: false, activeTasks: 0)),
        ),
      ],
      child: MaterialApp(
        theme: buildTheme(AppColors.light, Brightness.light),
        home: const MyTasksScreen(),
      ),
    ));
    await settle(tester);
    expect(text('No accepted tasks'), findsOneWidget);
    expect(text('Go to my shifts'), findsOneWidget);
    expect(text('Check in to your shift to start receiving task offers for your zone.'), findsNothing);

    await tester.tap(text('In progress · 0'));
    await settle(tester);
    expect(text('Nothing in progress'), findsOneWidget);
    expect(text('Tasks you handle now or start later appear here.'), findsNothing);

    await tester.tap(text('Finished'));
    await settle(tester);
    expect(text('No finished tasks yet'), findsOneWidget);
    expect(text('Submitted tasks wait here for the Operator to verify them.'), findsNothing);
  });

  appTest('Me shows ON only while push is registered', (tester, app) async {
    await goTab(tester, 'Me');
    expect(text('Today'), findsOneWidget);
    expect(text('Off shift'), findsNothing);
    final pushTile = find.widgetWithText(ListTile, 'Push notifications');
    await tester.scrollUntilVisible(pushTile, 200, scrollable: find.byType(Scrollable).first);
    expect(text('Server'), findsNothing);

    final status = app.container.read(pushRegistrationProvider).status;
    for (final state in PushStatus.values) {
      status.value = state;
      await tester.pump();
      expect(tester.widget<ListTile>(pushTile).subtitle, isNull);
      expect((tester.widget<ListTile>(pushTile).trailing as Text).data,
          state == PushStatus.registered ? 'ON' : 'OFF');
    }
  });

  appTest('a manager account sees why it cannot use the staff app', signedIn: false, (tester, app) async {
    await tester.enterText(find.byType(TextFormField).at(0), 'manager@store.test');
    await tester.enterText(find.byType(TextFormField).at(1), MockAuthRepository.password);
    await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
    await settle(tester, const Duration(milliseconds: 200), 10);

    expect(text('This app is for store staff. Manager accounts use the web console.'), findsOneWidget);
  });

  appTest('check in → event task offer → Handle now → the task is in progress', (tester, app) async {
    await goTab(tester, 'Alerts');
    expect(text("You're not checked in"), findsOneWidget);
    expect(text('Task offers only reach staff who are checked in to their shift.'), findsNothing);

    await tester.tap(find.widgetWithText(TextButton, 'Check in'));
    await settle(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'Check in'));
    await settle(tester);
    expect(text("You're checked in"), findsOneWidget);

    app.repo.simulateEventTask();
    await settle(tester);
    expect(text('New task offer'), findsOneWidget);
    expect(text('WARNING · Operational event'), findsOneWidget);
    expect(text('Offer 1 of 3'), findsOneWidget);

    await tapVisible(tester, find.widgetWithText(FilledButton, 'Handle now'));
    await settle(tester);

    expect(find.widgetWithText(AppBar, 'Task detail'), findsOneWidget);
    expect(text('Task started · Long queue at checkout'), findsOneWidget);
    expect(find.textContaining('In progress'), findsWidgets);
  });

  appTest('Accept, handle later shows the planned start and Start now begins work', (tester, app) async {
    await checkIn(tester);
    app.repo.simulateEventTask();
    await settle(tester);

    await tapVisible(tester, find.widgetWithText(OutlinedButton, 'Accept, handle later'));
    await settle(tester);
    expect(text('When will you start?'), findsOneWidget);
    await tapVisible(tester, find.widgetWithText(ChoiceChip, 'In 15 min'));
    await tester.pump();
    await tapVisible(tester, find.byWidgetPredicate((w) => w is FilledButton && w.child is Text && (w.child as Text).data!.startsWith('Accept · start by')));
    await settle(tester);

    expect(find.textContaining('Starts by'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Start now'), findsOneWidget);

    await tapVisible(tester, find.widgetWithText(FilledButton, 'Start now'));
    await settle(tester);
    expect(find.widgetWithText(FilledButton, 'Start now'), findsNothing);
    expect(find.textContaining('In progress'), findsWidgets);
  });

  appTest('when someone else accepts first the sheet says so', (tester, app) async {
    await checkIn(tester);
    app.repo.simulateEventTask(takenByOther: true);
    await settle(tester);
    expect(text('New task offer'), findsOneWidget);

    await tester.pump(const Duration(seconds: 5));
    await settle(tester);

    expect(text('Task already taken'), findsOneWidget);
    expect(text('An Khương accepted this task first. The offer is now withdrawn.'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Back to my tasks'));
    await settle(tester);
    expect(text('Task already taken'), findsNothing);
  });

  appTest('the open offer turns CRITICAL in place, then is withdrawn when the event clears', (tester, app) async {
    await checkIn(tester);
    app.repo.simulateEventTask();
    await settle(tester);
    expect(text('WARNING · Operational event'), findsOneWidget);

    app.repo.escalateLatestEvent();
    await settle(tester);
    expect(text('CRITICAL · Operational event'), findsOneWidget);
    expect(text('Raised from WARNING'), findsOneWidget);
    expect(text('11 people waiting · 6 min'), findsOneWidget);
    expect(text('New task offer'), findsOneWidget);

    app.repo.clearLatestEvent();
    await settle(tester);
    expect(text('No longer needed'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'OK'));
    await settle(tester);
    expect(text('No longer needed'), findsNothing);
  });

  appTest('a task whose event cleared stays mine and says the area is back to normal', (tester, app) async {
    await checkIn(tester);
    app.repo.simulateEventTask();
    await settle(tester);
    await tapVisible(tester, find.widgetWithText(FilledButton, 'Handle now'));
    await settle(tester);

    app.repo.clearLatestEvent();
    await settle(tester);
    expect(text('The camera shows this area back to normal'), findsOneWidget);
    expect(find.textContaining('Event cleared'), findsOneWidget);
    expect(find.textContaining('In progress'), findsWidgets);
  });

  appTest('Cannot handle needs a reason before it is sent', (tester, app) async {
    await checkIn(tester);
    app.repo.simulateEventTask();
    await settle(tester);

    await tapVisible(tester, find.widgetWithText(TextButton, 'Cannot handle'));
    await settle(tester);
    await tapVisible(tester, find.widgetWithText(FilledButton, 'Send: cannot handle'));
    await settle(tester);
    expect(text('Choose a reason.'), findsOneWidget);

    await tapVisible(tester, find.widgetWithText(ChoiceChip, DeclineReason.unavailable.label));
    await tapVisible(tester, find.widgetWithText(FilledButton, 'Send: cannot handle'));
    await settle(tester);
    expect(text('New task offer'), findsNothing);
    expect(await app.repo.watchOpenOffers().first, isEmpty);
  });

  appTest('report: describe → AI draft as potential incident → fix a field → Incident opened', (tester, app) async {
    await checkIn(tester);
    await goTab(tester, 'Report');

    final aiButton = find.widgetWithText(FilledButton, 'Let AI fill the report');
    expect(tester.widget<FilledButton>(aiButton).onPressed, isNull);

    await tester.enterText(find.byType(TextField), 'Chai nước ngọt bị vỡ ở cuối kệ số 4, sàn trơn, có khách suýt ngã.');
    await tester.pump();
    await tester.tap(aiButton);
    await settle(tester);

    expect(find.widgetWithText(AppBar, 'Review report'), findsOneWidget);
    expect(text('AI filled 5 fields'), findsOneWidget);
    expect(text('Spill / broken item'), findsOneWidget);
    expect(text('Zone B · Aisle 4'), findsOneWidget);

    await tester.tap(text('Broken item, wet floor at aisle 4'));
    await settle(tester);
    await tester.enterText(find.byType(TextField).last, 'Broken bottle, wet floor, aisle 4');
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await settle(tester);
    expect(text('AI filled 4 fields'), findsOneWidget);

    await tester.scrollUntilVisible(find.widgetWithText(FilledButton, 'Confirm and send'), 200, scrollable: find.byType(Scrollable).first);
    await tapVisible(tester, find.widgetWithText(FilledButton, 'Confirm and send'));
    await settle(tester);

    expect(find.textContaining('Incident INC-'), findsOneWidget);
    expect(text('Checked and edited'), findsOneWidget);
  });

  appTest('report: a routine request goes out as a task, not an incident', (tester, app) async {
    await checkIn(tester);
    await goTab(tester, 'Report');
    await tester.enterText(find.byType(TextField), 'Kệ trống ở quầy 2, cần restock nước suối');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Let AI fill the report'));
    await settle(tester);

    expect(text('Restock or shelf tidy'), findsOneWidget);
    await tester.scrollUntilVisible(find.widgetWithText(FilledButton, 'Confirm and send'), 200, scrollable: find.byType(Scrollable).first);
    expect(find.textContaining('No incident is opened'), findsOneWidget);
    await tapVisible(tester, find.widgetWithText(FilledButton, 'Confirm and send'));
    await settle(tester);

    expect(text('Request sent'), findsOneWidget);
    expect(text('ROUTINE REQUEST'), findsOneWidget);
  });

  appTest('shift swap: pick a colleague, they accept, then the Manager approves', (tester, app) async {
    await goTab(tester, 'Shifts');
    // The last day with a shift is days away, well before the 24-hour cut-off.
    await tapVisible(tester, find.byKey(const ValueKey('shift-day')).last);
    await settle(tester);
    await tapVisible(tester, find.textContaining('Evening ·').last);
    await settle(tester);
    expect(find.widgetWithText(AppBar, 'Shift detail'), findsOneWidget);
    await tapVisible(tester, text('Swap shift'));
    await settle(tester);
    expect(find.widgetWithText(AppBar, 'Choose a colleague'), findsOneWidget);

    await tapVisible(tester, text('Hoàng Lan'));
    await settle(tester);
    // The eligibility rules are folded under their heading.
    await tester.scrollUntilVisible(text('Only eligible colleagues are listed'), 200, scrollable: find.byType(Scrollable).first);
    expect(find.textContaining('colleague is hidden'), findsNothing);
    await tapVisible(tester, text('Only eligible colleagues are listed'));
    await settle(tester);
    await tester.scrollUntilVisible(find.textContaining('colleague is hidden'), 200, scrollable: find.byType(Scrollable).first);
    expect(find.textContaining('colleague is hidden'), findsOneWidget);
    await tester.scrollUntilVisible(find.widgetWithText(FilledButton, 'Choose Hoàng Lan'), 200, scrollable: find.byType(Scrollable).first);
    await tapVisible(tester, find.widgetWithText(FilledButton, 'Choose Hoàng Lan'));
    await settle(tester);
    expect(text("Hoàng Lan's shift"), findsOneWidget);

    await tester.scrollUntilVisible(find.widgetWithText(FilledButton, 'Send request'), 200, scrollable: find.byType(Scrollable).first);
    await tapVisible(tester, find.widgetWithText(FilledButton, 'Send request'));
    await settle(tester);
    expect(text('Choose a reason for the swap.'), findsOneWidget);

    await tapVisible(tester, find.widgetWithText(ChoiceChip, SwapReason.study.label));
    await tapVisible(tester, find.widgetWithText(FilledButton, 'Send request'));
    await settle(tester);
    expect(text('Waiting for Hoàng Lan'), findsOneWidget);
    await tester.scrollUntilVisible(find.widgetWithText(TextButton, 'Cancel request'), 200, scrollable: find.byType(Scrollable).first);
    expect(find.widgetWithText(TextButton, 'Cancel request'), findsOneWidget);

    app.repo.advanceLatestSwap(approve: true);
    await settle(tester);
    expect(text('Waiting for the Manager'), findsOneWidget);

    app.repo.advanceLatestSwap(approve: true);
    await settle(tester);
    expect(text('Shift no longer yours'), findsOneWidget);
  });

  appTest('a swap request from a colleague: open it from My shifts and accept', (tester, app) async {
    app.repo.receiveSwapRequest();
    await goTab(tester, 'Shifts');
    expect(text('1 swap request waiting for your answer'), findsOneWidget);

    await tester.tap(find.widgetWithText(TextButton, 'Open requests'));
    await settle(tester);
    expect(find.widgetWithText(AppBar, 'Swap requests'), findsOneWidget);
    await tester.tap(text('From Quang · Swap shifts'));
    await settle(tester);

    expect(find.widgetWithText(AppBar, 'Request from Quang'), findsOneWidget);
    expect(text('Exam that day. Can you take my shift?'), findsOneWidget);
    await tester.scrollUntilVisible(find.widgetWithText(FilledButton, 'Accept swap'), 200, scrollable: find.byType(Scrollable).first);
    await tapVisible(tester, find.widgetWithText(FilledButton, 'Accept swap'));
    await settle(tester);
    expect(text('Waiting for the Manager'), findsOneWidget);
    await tester.scrollUntilVisible(find.widgetWithText(TextButton, 'Withdraw my acceptance'), 200, scrollable: find.byType(Scrollable).first);
    expect(find.widgetWithText(TextButton, 'Withdraw my acceptance'), findsOneWidget);
  });

  appTest('at the 2-task limit My tasks explains that offers are paused', (tester, app) async {
    await checkIn(tester);
    app.repo.simulateEventTask();
    await settle(tester);
    await tapVisible(tester, find.widgetWithText(FilledButton, 'Handle now'));
    await settle(tester);
    // Re-selecting the current tab returns to the task list.
    await goTab(tester, 'Tasks');

    expect(text('New offers are paused'), findsOneWidget);
  });
  appTest('complete a task: note → submit → rework → resubmit → verified', (tester, app) async {
    await checkIn(tester);
    app.repo.simulateEventTask();
    await settle(tester);
    await tapVisible(tester, find.widgetWithText(FilledButton, 'Handle now'));
    await settle(tester);
    // The detail now also shows who verifies the work, so the button can sit below the fold.
    expect(text('Verification'), findsOneWidget);
    await tester.scrollUntilVisible(find.widgetWithText(FilledButton, 'Complete task'), 300, scrollable: find.byType(Scrollable).first);
    await tapVisible(tester, find.widgetWithText(FilledButton, 'Complete task'));
    await settle(tester);
    expect(find.widgetWithText(AppBar, 'Complete task'), findsOneWidget);
    expect(text('Add a completion note'), findsOneWidget);
    await tester.scrollUntilVisible(text('Submit for verification'), 300, scrollable: find.byType(Scrollable).first);
    final submit = find.ancestor(of: text('Submit for verification'), matching: find.byWidgetPredicate((w) => w is ButtonStyleButton));
    expect(submit, findsOneWidget);
    expect(tester.widget<ButtonStyleButton>(submit).onPressed, isNull);

    await tester.enterText(find.byType(TextField), 'Opened counter 4, queue cleared');
    await tester.pump();
    await tapVisible(tester, submit);
    await settle(tester);
    expect(text('Waiting for verification'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Back to my tasks'));
    await settle(tester);
    expect(app.repo.reviewLatestSubmission(approve: false), isNull);
    await settle(tester);
    await tester.tap(find.textContaining('In progress ·'));
    await settle(tester);
    await tapVisible(tester, find.text('Long queue at checkout').first);
    await settle(tester);
    expect(text('Rework needed'), findsOneWidget);

    await tester.scrollUntilVisible(text('Complete task'), 300, scrollable: find.byType(Scrollable).first);
    await tapVisible(tester, text('Complete task'));
    await settle(tester);
    expect(text('Rework needed'), findsOneWidget);
    await tester.scrollUntilVisible(find.byType(TextField), 300, scrollable: find.byType(Scrollable).first);
    await tester.enterText(find.byType(TextField), 'Opened counters 4 and 5');
    await tester.pump();
    await tester.scrollUntilVisible(text('Submit for verification'), 300, scrollable: find.byType(Scrollable).first);
    await tapVisible(tester, text('Submit for verification'));
    await settle(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'Back to my tasks'));
    await settle(tester);

    expect(app.repo.reviewLatestSubmission(approve: true), isNull);
    await settle(tester);
    await tapVisible(tester, find.textContaining('Finished'));
    await settle(tester);
    await tapVisible(tester, find.text('Long queue at checkout').first);
    await settle(tester);
    expect(text('Verified'), findsOneWidget);
    await tester.scrollUntilVisible(text('Opened counters 4 and 5'), 300, scrollable: find.byType(Scrollable).first);
    expect(text('Opened counters 4 and 5'), findsOneWidget);
  });
}
