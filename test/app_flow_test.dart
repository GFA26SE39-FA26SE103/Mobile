import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supermarket_staff/data/models.dart';
import 'package:supermarket_staff/features/auth/auth_repository.dart';
import 'package:supermarket_staff/features/report/recorded_voice_input.dart';

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

class _FakeReportRecorder implements ReportAudioRecorder {
  int starts = 0;
  bool failStop = false;

  @override
  Future<bool> start() async { starts++; return true; }
  @override
  Future<String?> stop() async {
    if (failStop) throw StateError('microphone stopped');
    return '.dart_tool/test-voice.m4a';
  }
  @override
  Future<void> cancel() async {}
  @override
  Future<void> dispose() async {}
}

void main() {
  final recorder = _FakeReportRecorder();
  appTest('report voice recording enables review only after a successful stop', (tester, app) async {
    await goTab(tester, 'Report');
    final aiButton = find.widgetWithText(FilledButton, 'Let AI fill the report');
    expect(tester.widget<FilledButton>(aiButton).onPressed, isNull);
    await tester.tap(text('Record note'));
    await settle(tester);
    expect(recorder.starts, 1);
    expect(text('Stop recording'), findsOneWidget);
    expect(tester.widget<FilledButton>(aiButton).onPressed, isNull);
    await tester.tap(text('Stop recording'));
    await settle(tester);
    expect(text('Record again'), findsOneWidget);
    expect(tester.widget<FilledButton>(aiButton).onPressed, isNotNull);
  }, audioRecorder: recorder);

  final failingRecorder = _FakeReportRecorder()..failStop = true;
  appTest('failed voice stop keeps the report unready and shows an error', (tester, app) async {
    await goTab(tester, 'Report');
    await tester.tap(text('Record note'));
    await settle(tester);
    await tester.tap(text('Stop recording'));
    await settle(tester);
    expect(text('Could not record the voice note. Try again or type the report.'), findsOneWidget);
    await tester.scrollUntilVisible(text('Let AI fill the report'), 150, scrollable: find.byType(Scrollable).first);
    expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Let AI fill the report')).onPressed, isNull);
  }, audioRecorder: failingRecorder);
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

  appTest('a manager account sees why it cannot use the staff app', signedIn: false, (tester, app) async {
    await tester.enterText(find.byType(TextFormField).at(0), 'manager@store.test');
    await tester.enterText(find.byType(TextFormField).at(1), MockAuthRepository.password);
    await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
    await settle(tester, const Duration(milliseconds: 200), 10);

    expect(text('This app is for store staff. Manager accounts use the web console.'), findsOneWidget);
  });

  appTest('check in → event task offer → Handle now → the task is in progress', (tester, app) async {
    await goTab(tester, 'Alerts');
    expect(text("You're not receiving task offers"), findsOneWidget);

    await checkIn(tester);
    expect(text("You're checked in"), findsOneWidget);

    app.repo.simulateEventTask();
    await settle(tester);
    expect(text('New task offer in your zone'), findsOneWidget);
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
    expect(text('New task offer in your zone'), findsOneWidget);

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
    expect(text('New task offer in your zone'), findsOneWidget);

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
    expect(text('Choose a reason so the Operator knows why.'), findsOneWidget);

    await tapVisible(tester, find.widgetWithText(ChoiceChip, DeclineReason.onBreak.label));
    await tapVisible(tester, find.widgetWithText(FilledButton, 'Send: cannot handle'));
    await settle(tester);
    expect(text('New task offer in your zone'), findsNothing);
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
    expect(text('AI filled 6 fields'), findsOneWidget);
    expect(text('Spill / broken item'), findsOneWidget);
    expect(text('Zone B · Aisle 4'), findsOneWidget);

    await tester.tap(text('Broken item, wet floor at aisle 4'));
    await settle(tester);
    await tester.enterText(find.byType(TextField).last, 'Broken bottle, wet floor, aisle 4');
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await settle(tester);
    expect(text('AI filled 5 fields'), findsOneWidget);

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
    // The last evening row is days away, well before the 24-hour cut-off (today's card may say Evening too).
    await tester.tap(find.textContaining('Evening ·').last);
    await settle(tester);
    expect(find.widgetWithText(AppBar, 'Choose a colleague'), findsOneWidget);

    await tapVisible(tester, text('Hoàng Lan'));
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
