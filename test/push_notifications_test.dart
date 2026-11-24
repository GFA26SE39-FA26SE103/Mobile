import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:supermarket_staff/core/push_notifications.dart';

void main() {
  test('push payload validates required fields and derives the channel', () {
    final offer = PushPayload.tryParse(
      data: const {
        'notificationId': 'note-1',
        'type': 'TASK_OFFER',
        'route': '/alerts',
      },
      title: 'New task',
      body: 'Frozen aisle',
    );

    expect(offer, isNotNull);
    expect(offer!.channelId, 'task_offers');
    expect(offer.route, '/alerts');
    expect(
      PushPayload.tryParse(
        data: const {'type': 'TASK_OFFER', 'route': '/alerts'},
        title: 'Missing id',
        body: 'Ignored',
      ),
      isNull,
    );
  });

  test(
    'registration persists backend device id and refreshes the token',
    () async {
      final messages = FakePushMessaging('token-abcdefghijklmnopqrstuvwxyz');
      final api = FakeDeviceApi();
      final store = MemoryDeviceIdentityStore();
      final registration = PushRegistration(
        messaging: messages,
        api: api,
        identityStore: store,
        platform: 'ANDROID',
      );

      await registration.start();
      messages.refresh.add('rotated-token-abcdefghijklmnopqrstuvwxyz');
      await Future<void>.delayed(Duration.zero);

      expect(api.registrations, [
        ('token-abcdefghijklmnopqrstuvwxyz', null),
        ('rotated-token-abcdefghijklmnopqrstuvwxyz', 'device-1'),
      ]);
      expect(store.deviceId, 'device-1');
      await registration.dispose();
    },
  );

  test(
    'a device id the server does not know is dropped and the phone registers afresh',
    () async {
      final messages = FakePushMessaging('token-abcdefghijklmnopqrstuvwxyz');
      final api = FakeDeviceApi(unknownIds: {'dev-server-device'});
      final store = MemoryDeviceIdentityStore()..deviceId = 'dev-server-device';
      final registration = PushRegistration(
        messaging: messages,
        api: api,
        identityStore: store,
        platform: 'ANDROID',
      );

      await registration.start();
      await Future<void>.delayed(Duration.zero);

      expect(api.registrations, [
        ('token-abcdefghijklmnopqrstuvwxyz', 'dev-server-device'),
        ('token-abcdefghijklmnopqrstuvwxyz', null),
      ]);
      expect(store.deviceId, 'device-1');
      expect(registration.status.value, PushStatus.registered);
      await registration.dispose();
    },
  );

  test(
    'the last known push target is sent again when Firebase does not report it',
    () async {
      // Firebase reports the target only when it changes; this installation registered earlier.
      final messages = FakePushMessaging(null);
      final api = FakeDeviceApi();
      final store = MemoryDeviceIdentityStore()..token = 'known-token-abcdefghijklmnopqrstuvwxyz';
      final registration = PushRegistration(
        messaging: messages,
        api: api,
        identityStore: store,
        platform: 'ANDROID',
      );

      await registration.start();
      await Future<void>.delayed(Duration.zero);

      expect(api.registrations, [('known-token-abcdefghijklmnopqrstuvwxyz', null)]);
      expect(store.deviceId, 'device-1');
      await registration.dispose();
    },
  );

  test('a build without Firebase configuration reports push as off', () async {
    final registration = PushRegistration(
      messaging: const NoopPushMessaging(),
      api: FakeDeviceApi(),
      identityStore: MemoryDeviceIdentityStore(),
      platform: 'ANDROID',
    );

    await registration.start();

    expect(registration.status.value, PushStatus.notConfigured);
  });

  test(
    'explicit logout revokes the registered device and clears local identity',
    () async {
      final messages = FakePushMessaging('token-abcdefghijklmnopqrstuvwxyz');
      final api = FakeDeviceApi();
      final store = MemoryDeviceIdentityStore()..deviceId = 'owned-device';
      final registration = PushRegistration(
        messaging: messages,
        api: api,
        identityStore: store,
        platform: 'ANDROID',
      );

      await registration.revoke();

      expect(api.revocations, ['owned-device']);
      expect(store.deviceId, isNull);
      await registration.dispose();
    },
  );
}

class FakePushMessaging implements PushMessaging {
  FakePushMessaging(this.currentToken);

  final String? currentToken;
  final refresh = StreamController<String>.broadcast(sync: true);

  @override
  bool get configured => true;

  @override
  Stream<PushPayload> get foregroundMessages => const Stream.empty();

  @override
  Stream<String> get openedRoutes => const Stream.empty();

  @override
  Stream<String> get registrationRefreshes => refresh.stream;

  @override
  Future<void> register() async {
    final value = currentToken;
    if (value != null) refresh.add(value);
  }

  @override
  Future<String?> initialRoute() async => null;

  @override
  Future<void> requestPermission() async {}
}

class FakeDeviceApi implements DeviceRegistrationApi {
  FakeDeviceApi({this.unknownIds = const {}});

  /// Device ids this server has never issued, e.g. ones issued by the dev API.
  final Set<String> unknownIds;
  final registrations = <(String, String?)>[];
  final revocations = <String>[];

  @override
  Future<String> register({
    required String fcmToken,
    required String platform,
    String? deviceId,
  }) async {
    registrations.add((fcmToken, deviceId));
    if (unknownIds.contains(deviceId)) throw const DeviceRegistrationNotFound();
    return deviceId ?? 'device-1';
  }

  @override
  Future<void> revoke(String deviceId) async => revocations.add(deviceId);
}

class MemoryDeviceIdentityStore implements DeviceIdentityStore {
  String? deviceId;
  String? token;

  @override
  Future<String?> readToken() async => token;

  @override
  Future<void> writeToken(String value) async => token = value;

  @override
  Future<void> clear() async => deviceId = null;

  @override
  Future<String?> read() async => deviceId;

  @override
  Future<void> write(String value) async => deviceId = value;
}
