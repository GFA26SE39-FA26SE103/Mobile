import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../data/models.dart';
import 'push_notifications.dart';

/// Android notification channels, so staff can tune each kind in system settings.
enum NotifyChannel {
  /// New or re-offered tasks and priority raised to CRITICAL: heads-up, sound, strong vibration.
  taskOffers(
    'task_offers',
    'Task offers',
    'New tasks for your zone. Accept quickly; the first acceptance wins.',
    Importance.max,
  ),

  /// Task assigned, taken by someone else, withdrawn or cleared.
  taskUpdates(
    'task_updates',
    'Task updates',
    'Changes to tasks you were offered or accepted.',
    Importance.defaultImportance,
  ),

  /// Published schedules, shift changes and swap requests.
  shifts(
    'shifts_swaps',
    'Shifts and swaps',
    'Your schedule and shift swap requests.',
    Importance.defaultImportance,
  );

  const NotifyChannel(this.id, this.label, this.description, this.importance);
  final String id;
  final String label;
  final String description;
  final Importance importance;
}

/// Puts notifications in the phone's notification shade.
abstract class DeviceNotifier {
  /// [onTap] receives the payload (an app route) of a tapped notification.
  Future<void> init(void Function(String route) onTap);
  Future<void> requestPermission();
  Future<void> show({
    required int id,
    required NotifyChannel channel,
    required String title,
    required String body,
    required String route,
  });
  Future<void> cancel(int id);
}

/// Tests and platforms without notifications.
class NoopDeviceNotifier implements DeviceNotifier {
  @override
  Future<void> init(void Function(String route) onTap) async {}
  @override
  Future<void> requestPermission() async {}
  @override
  Future<void> show({
    required int id,
    required NotifyChannel channel,
    required String title,
    required String body,
    required String route,
  }) async {}
  @override
  Future<void> cancel(int id) async {}
}

class LocalDeviceNotifier implements DeviceNotifier {
  final _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;

  AndroidFlutterLocalNotificationsPlugin? get _android => _plugin
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >();

  @override
  Future<void> init(void Function(String route) onTap) async {
    try {
      await _plugin.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
          iOS: DarwinInitializationSettings(
            requestAlertPermission: false,
            requestBadgePermission: false,
            requestSoundPermission: false,
          ),
        ),
        onDidReceiveNotificationResponse: (response) {
          final route = response.payload;
          if (route != null && route.isNotEmpty) onTap(route);
        },
      );
      for (final c in NotifyChannel.values) {
        await _android?.createNotificationChannel(
          AndroidNotificationChannel(
            c.id,
            c.label,
            description: c.description,
            importance: c.importance,
          ),
        );
      }
      _ready = true;
      // The app was opened by tapping a notification.
      final launch = await _plugin.getNotificationAppLaunchDetails();
      final route = launch?.notificationResponse?.payload;
      if ((launch?.didNotificationLaunchApp ?? false) &&
          route != null &&
          route.isNotEmpty) {
        onTap(route);
      }
    } on MissingPluginException {
      _ready = false;
    } on PlatformException catch (e) {
      debugPrint('Notifications unavailable: $e');
    }
  }

  @override
  Future<void> requestPermission() async {
    if (!_ready) return;
    // Android 13+ asks the user once; earlier versions grant it at install.
    await _android?.requestNotificationsPermission();
    await _plugin
        .resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin
        >()
        ?.requestPermissions(alert: true, badge: true, sound: true);
  }

  @override
  Future<void> show({
    required int id,
    required NotifyChannel channel,
    required String title,
    required String body,
    required String route,
  }) async {
    if (!_ready) return;
    final urgent = channel == NotifyChannel.taskOffers;
    await _plugin.show(
      id: id,
      title: title,
      body: body,
      payload: route,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          channel.id,
          channel.label,
          channelDescription: channel.description,
          importance: channel.importance,
          priority: urgent ? Priority.max : Priority.defaultPriority,
          // Stamp the notification with the time it is shown; without an explicit time some
          // Android builds show the epoch ("57y") next to it.
          when: DateTime.now().millisecondsSinceEpoch,
          showWhen: true,
          // Task offers behave like an incoming call: wake the screen and show on the lock screen.
          fullScreenIntent: urgent,
          visibility: NotificationVisibility.public,
          category: urgent
              ? AndroidNotificationCategory.call
              : AndroidNotificationCategory.event,
          styleInformation: BigTextStyleInformation(body),
          groupKey: urgent ? null : channel.id,
        ),
        iOS: DarwinNotificationDetails(
          interruptionLevel: urgent
              ? InterruptionLevel.timeSensitive
              : InterruptionLevel.active,
        ),
      ),
    );
  }

  @override
  Future<void> cancel(int id) async {
    if (_ready) await _plugin.cancel(id: id);
  }
}

/// Decides what reaches the notification shade. Only while the app is not in front: in the app the
/// offer sheet and the Alerts badge already show everything.
class NotificationRelay {
  NotificationRelay(this.notifier);
  final DeviceNotifier notifier;

  bool foreground = true;
  Set<String>? _seenNotes;
  final _shownOffers = <String>{};
  final _pushed = <String>{};
  final _pushOrder = <String>[];

  static int idFor(String key) => key.hashCode & 0x7fffffff;

  /// Every server notification except task offers, which come through [onOffer] with their re-offers.
  void onNotes(List<AppNotification> notes) {
    final seen = _seenNotes;
    _seenNotes = {for (final n in notes) n.id};
    // The first load is history; only what arrives after it is news.
    if (seen == null || foreground) return;
    for (final n in notes.where(
      (n) => !seen.contains(n.id) && !_pushed.contains(n.id),
    )) {
      final channel = channelFor(n.kind);
      if (channel == null) continue;
      notifier.show(
        id: idFor(n.id),
        channel: channel,
        title: n.title,
        body: n.body,
        route: routeFor(n),
      );
    }
  }

  /// Firebase foreground delivery. The same notification may later arrive in
  /// polling, so remember a bounded set of server ids to prevent duplication.
  void onPush(PushPayload payload) {
    if (!_pushed.add(payload.notificationId)) return;
    _pushOrder.add(payload.notificationId);
    if (_pushOrder.length > 256) _pushed.remove(_pushOrder.removeAt(0));
    final channel = NotifyChannel.values
        .where((value) => value.id == payload.channelId)
        .firstOrNull;
    if (channel == null) return;
    notifier.show(
      id: idFor(payload.notificationId),
      channel: channel,
      title: payload.title,
      body: payload.body,
      route: payload.route,
    );
  }

  /// A new offer, a re-offer (next attempt) or an offer raised to CRITICAL.
  void onOffer(TaskOffer offer) {
    if (!offer.isOpen) return;
    _shownOffers.add(offer.offerId);
    if (foreground) return;
    final zone = offer.zoneName.split(' · ').first;
    final title =
        offer.raisedFrom != null && offer.priority == Severity.critical
        ? 'Now CRITICAL · $zone'
        : offer.attempt > 1
        ? 'Still waiting · ${offer.roundLabel}'
        : 'New task · $zone';
    final where = offer.location.isEmpty ? zone : offer.location;
    notifier.show(
      id: idFor(offer.offerId),
      channel: NotifyChannel.taskOffers,
      title: title,
      body: '${offer.title} · $where · Tap to respond',
      route: '/alerts',
    );
  }

  /// Offers that closed (taken, withdrawn, cleared) leave the shade so nobody taps a stale task.
  void onOpenOffers(List<TaskOffer> open) {
    final still = {for (final o in open) o.offerId};
    for (final id in _shownOffers.where((id) => !still.contains(id)).toList()) {
      _shownOffers.remove(id);
      notifier.cancel(idFor(id));
    }
  }

  static NotifyChannel? channelFor(NotificationKind kind) => switch (kind) {
    NotificationKind.taskOffered => null,
    NotificationKind.eventEscalated => NotifyChannel.taskOffers,
    NotificationKind.taskAccepted ||
    NotificationKind.offerTaken ||
    NotificationKind.offerEscalated ||
    NotificationKind.eventCleared ||
    NotificationKind.taskVerified ||
    NotificationKind.taskRejected ||
    NotificationKind.reportSent ||
    NotificationKind.general => NotifyChannel.taskUpdates,
    // Check-in happens on this phone; telling the user again adds nothing.
    NotificationKind.shiftStarted => null,
    NotificationKind.shiftChanged ||
    NotificationKind.swapUpdated => NotifyChannel.shifts,
  };

  static String routeFor(AppNotification n) => switch (n.kind) {
    _ when n.taskId != null => '/tasks/${n.taskId}',
    NotificationKind.swapUpdated => '/shifts/swaps',
    NotificationKind.shiftChanged => '/shifts',
    _ => '/alerts',
  };
}
