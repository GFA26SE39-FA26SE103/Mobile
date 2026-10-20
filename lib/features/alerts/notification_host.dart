import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/device_notifications.dart';
import '../../core/providers.dart';
import '../../core/router.dart';
import '../../data/providers.dart';
import 'incoming_alert.dart';

/// While a staff member is signed in, relays task offers, task updates and schedule changes to the
/// phone's notification shade whenever the app is in the background. Tapping one opens its screen.
class DeviceNotificationHost extends ConsumerStatefulWidget {
  const DeviceNotificationHost({super.key, required this.child});
  final Widget child;

  @override
  ConsumerState<DeviceNotificationHost> createState() => _DeviceNotificationHostState();
}

class _DeviceNotificationHostState extends ConsumerState<DeviceNotificationHost> with WidgetsBindingObserver {
  late final NotificationRelay _relay;

  @override
  void initState() {
    super.initState();
    final notifier = ref.read(deviceNotifierProvider);
    _relay = NotificationRelay(notifier);
    final state = WidgetsBinding.instance.lifecycleState;
    _relay.foreground = state == null || state == AppLifecycleState.resumed;
    WidgetsBinding.instance.addObserver(this);
    () async {
      await notifier.init((route) {
        if (mounted) ref.read(routerProvider).go(route);
      });
      await notifier.requestPermission();
    }();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) => _relay.foreground = state == AppLifecycleState.resumed;

  @override
  Widget build(BuildContext context) {
    ref.listen(notificationsProvider, (_, next) {
      final notes = next.valueOrNull;
      if (notes != null) _relay.onNotes(notes);
    });
    ref.listen(incomingOfferProvider, (_, next) {
      final offer = next.valueOrNull;
      if (offer != null) _relay.onOffer(offer);
    });
    ref.listen(openOffersProvider, (_, next) {
      final open = next.valueOrNull;
      if (open != null) _relay.onOpenOffers(open);
    });
    return widget.child;
  }
}
