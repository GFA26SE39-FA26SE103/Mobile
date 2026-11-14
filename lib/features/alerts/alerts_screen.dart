import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../data/models.dart';
import '../../data/providers.dart';
import '../../shared/format.dart';
import '../../shared/widgets.dart';
import 'incoming_alert.dart';

class AlertsScreen extends ConsumerWidget {
  const AlertsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = ref.watch(clockProvider)();
    final eligibility = ref.watch(eligibilityProvider).valueOrNull;
    final open = ref.watch(openOffersProvider).valueOrNull ?? const <TaskOffer>[];
    final notes = ref.watch(notificationsProvider).valueOrNull ?? const <AppNotification>[];
    final unread = notes.where((n) => !n.read).length;
    final todayStart = DateTime(now.year, now.month, now.day);
    final today = notes.where((n) => !n.createdAt.isBefore(todayStart)).toList();
    final earlier = notes.where((n) => n.createdAt.isBefore(todayStart)).toList();

    return Scaffold(
      appBar: AppBar(title: const Text('Alerts')),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 28), children: [
        if (eligibility != null && !eligibility.checkedIn) ...[
          const SizedBox(height: 8),
          InfoBanner(
            tone: BannerTone.warning,
            icon: Icons.notifications_off_outlined,
            title: "You're not receiving task offers",
            body: 'Task offers only reach staff who are checked in to their shift.',
            action: TextButton(
              style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(0, 36)),
              onPressed: () => context.go('/shifts'),
              child: const Text('Check in'),
            ),
          ),
        ],
        if (open.isNotEmpty) ...[
          const GroupLabel('Waiting for you'),
          for (final a in open) ...[
            _OpenOfferCard(offer: a, now: now, onTap: () => showTaskOffer(context, a.offerId)),
            const SizedBox(height: 10),
          ],
        ],
        GroupLabel(
          'Today',
          trailing: unread > 0
              ? TextButton(
                  style: TextButton.styleFrom(minimumSize: const Size(0, 32), padding: const EdgeInsets.symmetric(horizontal: 4)),
                  onPressed: () => ref.read(operationsRepositoryProvider).markAllRead(),
                  child: const Text('Mark all read'),
                )
              : null,
        ),
        if (today.isEmpty)
          Text('No notifications yet today.', style: Theme.of(context).textTheme.bodySmall)
        else
          for (final n in today) ...[_NotificationTile(note: n, now: now), const SizedBox(height: 10)],
        if (earlier.isNotEmpty) ...[
          const GroupLabel('Earlier'),
          for (final n in earlier) ...[_NotificationTile(note: n, now: now), const SizedBox(height: 10)],
        ],
      ]),
    );
  }
}

class _OpenOfferCard extends StatelessWidget {
  const _OpenOfferCard({required this.offer, required this.now, required this.onTap});
  final TaskOffer offer;
  final DateTime now;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return AppCard(
      onTap: onTap,
      borderColor: c.danger,
      child: Row(children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(color: c.dangerTint, borderRadius: BorderRadius.circular(10)),
          child: Icon(Icons.warning_amber_rounded, color: c.danger, size: 22),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(offer.title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
            Text([if (offer.location.isNotEmpty) offer.location, offer.roundLabel].join(' · '),
                style: Theme.of(context).textTheme.bodySmall),
          ]),
        ),
        Text('Respond', style: TextStyle(color: c.primary, fontWeight: FontWeight.w600)),
      ]),
    );
  }
}

class _NotificationTile extends StatelessWidget {
  const _NotificationTile({required this.note, required this.now});
  final AppNotification note;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final tone = note.severity == null ? (fg: c.textMuted, bg: c.surface2) : severityColors(context, note.severity!);
    final icon = switch (note.kind) {
      NotificationKind.taskOffered => Icons.notification_important_outlined,
      NotificationKind.taskAccepted => Icons.assignment_turned_in_outlined,
      NotificationKind.offerTaken => Icons.how_to_reg_outlined,
      NotificationKind.offerEscalated => Icons.support_agent,
      NotificationKind.eventEscalated => Icons.trending_up,
      NotificationKind.eventCleared => Icons.check_circle_outline,
      NotificationKind.taskVerified => Icons.verified_outlined,
      NotificationKind.taskRejected => Icons.replay,
      NotificationKind.reportSent => Icons.send_outlined,
      NotificationKind.shiftStarted => Icons.login,
      NotificationKind.shiftChanged => Icons.event_note_outlined,
      NotificationKind.swapUpdated => Icons.swap_horiz,
      NotificationKind.general => Icons.notifications_none,
    };
    // Swap notifications carry no request id on the server, so they open the request list.
    final target = switch (note.kind) {
      _ when note.taskId != null => '/tasks/${note.taskId}',
      NotificationKind.swapUpdated => '/shifts/swaps',
      NotificationKind.shiftChanged => '/shifts',
      _ => null,
    };
    return AppCard(
      onTap: target == null ? null : () => context.go(target),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(color: tone.bg, borderRadius: BorderRadius.circular(10)),
          child: Icon(icon, color: tone.fg, size: 21),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(note.title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
            const SizedBox(height: 2),
            Text(note.body, style: TextStyle(color: c.textMuted, fontSize: 13.5)),
            if (note.severity != null) ...[const SizedBox(height: 6), SeverityChip(note.severity!)],
          ]),
        ),
        const SizedBox(width: 8),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text(timeAgo(note.createdAt, now), style: Theme.of(context).textTheme.bodySmall),
          if (!note.read) ...[
            const SizedBox(height: 6),
            Semantics(
              label: 'Unread',
              child: Container(width: 8, height: 8, decoration: BoxDecoration(color: c.primary, shape: BoxShape.circle)),
            ),
          ],
        ]),
      ]),
    );
  }
}
