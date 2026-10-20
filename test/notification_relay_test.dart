import 'package:flutter_test/flutter_test.dart';
import 'package:supermarket_staff/core/device_notifications.dart';
import 'package:supermarket_staff/data/models.dart';

class FakeNotifier implements DeviceNotifier {
  final shown = <({int id, NotifyChannel channel, String title, String body, String route})>[];
  final cancelled = <int>[];

  @override
  Future<void> init(void Function(String route) onTap) async {}
  @override
  Future<void> requestPermission() async {}
  @override
  Future<void> show({required int id, required NotifyChannel channel, required String title, required String body, required String route}) async =>
      shown.add((id: id, channel: channel, title: title, body: body, route: route));
  @override
  Future<void> cancel(int id) async => cancelled.add(id);
}

final now = DateTime(2026, 10, 20, 10);

AppNotification note(String id, NotificationKind kind, {String? taskId}) =>
    AppNotification(id: id, kind: kind, title: 'Title $id', body: 'Body $id', createdAt: now, taskId: taskId);

TaskOffer offer({int attempt = 1, Severity priority = Severity.warning, Severity? raisedFrom, OfferStatus status = OfferStatus.open}) => TaskOffer(
      offerId: 'off-1',
      origin: TaskOrigin.operationalEvent,
      sourceCode: 'EVT-1',
      title: 'Long queue at checkout',
      priority: priority,
      raisedFrom: raisedFrom,
      zoneName: 'Zone B · Checkout',
      location: 'Checkout 3',
      measurement: '7 people',
      instructions: '',
      createdAt: now,
      recipients: 3,
      attempt: attempt,
      nextAlertAt: now,
      status: status,
    );

void main() {
  late FakeNotifier fake;
  late NotificationRelay relay;
  setUp(() {
    fake = FakeNotifier();
    relay = NotificationRelay(fake)..foreground = false;
  });

  test('the first load is history; only notifications that arrive later reach the shade', () {
    relay.onNotes([note('n1', NotificationKind.swapUpdated)]);
    expect(fake.shown, isEmpty);

    relay.onNotes([note('n2', NotificationKind.swapUpdated), note('n1', NotificationKind.swapUpdated)]);
    expect(fake.shown.single.title, 'Title n2');
    expect(fake.shown.single.channel, NotifyChannel.shifts);
    expect(fake.shown.single.route, '/shifts/swaps');

    // The same list again shows nothing new.
    relay.onNotes([note('n2', NotificationKind.swapUpdated), note('n1', NotificationKind.swapUpdated)]);
    expect(fake.shown, hasLength(1));
  });

  test('channels and routes follow the kind; offers and check-ins are not repeated as notes', () {
    relay.onNotes([]);
    relay.onNotes([
      note('a', NotificationKind.taskAccepted, taskId: 't-9'),
      note('b', NotificationKind.shiftChanged),
      note('c', NotificationKind.taskOffered),
      note('d', NotificationKind.shiftStarted),
      note('e', NotificationKind.eventEscalated, taskId: 't-9'),
    ]);
    expect([for (final s in fake.shown) (s.title, s.channel, s.route)], [
      ('Title a', NotifyChannel.taskUpdates, '/tasks/t-9'),
      ('Title b', NotifyChannel.shifts, '/shifts'),
      ('Title e', NotifyChannel.taskOffers, '/tasks/t-9'),
    ]);
  });

  test('nothing is shown while the app is in front', () {
    relay.foreground = true;
    relay.onNotes([]);
    relay.onNotes([note('n1', NotificationKind.swapUpdated)]);
    relay.onOffer(offer());
    expect(fake.shown, isEmpty);
  });

  test('an offer alerts urgently, again on each re-offer and on CRITICAL, and leaves the shade once closed', () {
    relay.onOffer(offer());
    relay.onOffer(offer(attempt: 2));
    relay.onOffer(offer(attempt: 2, priority: Severity.critical, raisedFrom: Severity.warning));
    expect([for (final s in fake.shown) s.title], ['New task · Zone B', 'Still waiting · offer 2 of 3', 'Now CRITICAL · Zone B']);
    expect(fake.shown.every((s) => s.channel == NotifyChannel.taskOffers && s.route == '/alerts'), isTrue);
    expect(fake.shown.first.body, 'Long queue at checkout · Checkout 3 · Tap to respond');
    // One notification per offer: re-offers replace it rather than stacking.
    expect(fake.shown.map((s) => s.id).toSet(), hasLength(1));

    relay.onOpenOffers([offer()]);
    expect(fake.cancelled, isEmpty);
    relay.onOpenOffers([]);
    expect(fake.cancelled, [NotificationRelay.idFor('off-1')]);
  });
}
