import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../data/models.dart';
import '../../data/providers.dart';
import '../../shared/format.dart';
import '../../shared/widgets.dart';
import 'swap_screens.dart';

class MyShiftsScreen extends ConsumerStatefulWidget {
  const MyShiftsScreen({super.key});

  @override
  ConsumerState<MyShiftsScreen> createState() => _MyShiftsScreenState();
}

class _MyShiftsScreenState extends ConsumerState<MyShiftsScreen> {
  bool _checkingIn = false;
  String? _checkInError;

  Future<void> _checkIn(Shift shift) async {
    setState(() {
      _checkingIn = true;
      _checkInError = null;
    });
    try {
      await ref.read(operationsRepositoryProvider).checkIn(shift.shiftId);
      if (mounted) context.go('/shifts/checked-in');
    } on CheckInTooEarly catch (e) {
      setState(() => _checkInError = 'Check-in opens at ${hm(e.opensAt)}, 15 minutes before your shift.');
    } on StateError catch (e) {
      setState(() => _checkInError = e.message);
    } on OperationFailed catch (e) {
      setState(() => _checkInError = e.message);
    } finally {
      if (mounted) setState(() => _checkingIn = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final now = ref.watch(clockProvider)();
    final shifts = ref.watch(shiftsProvider);
    final today = ref.watch(todayShiftProvider);
    final swaps = ref.watch(swapByShiftProvider);
    final awaiting = ref.watch(swapsAwaitingMeProvider);
    // Open requests colleagues sent me, by the shift of mine they would take.
    final incoming = {
      for (final r in ref.watch(swapRequestsProvider).valueOrNull ?? const <ShiftSwapRequest>[])
        if (!r.sentByMe && r.status.isOpen && r.targetShift != null) r.targetShift!.shiftId: r,
    };
    final repo = ref.read(operationsRepositoryProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('My shifts'), actions: [
        IconButton(
          tooltip: 'Swap requests',
          onPressed: () => context.go('/shifts/swaps'),
          icon: Badge(isLabelVisible: awaiting > 0, label: Text('$awaiting'), child: const Icon(Icons.swap_horiz)),
        ),
        const SizedBox(width: 8),
      ]),
      body: shifts.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => EmptyState(
          icon: Icons.cloud_off_outlined,
          title: 'Could not load shifts',
          body: '$e',
          action: OutlinedButton(onPressed: repo.refresh, child: const Text('Try again')),
        ),
        data: (all) {
          final upcoming = all.where((s) => s != today && s.start.isAfter(now)).toList()..sort((a, b) => a.start.compareTo(b.start));
          return RefreshIndicator(
            onRefresh: repo.refresh,
            child: ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 28), children: [
            if (awaiting > 0) ...[
              InfoBanner(
                tone: BannerTone.danger,
                icon: Icons.swap_horiz,
                title: '$awaiting swap request${awaiting == 1 ? '' : 's'} waiting for your answer',
                action: TextButton(
                  style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(0, 36)),
                  onPressed: () => context.go('/shifts/swaps'),
                  child: const Text('Open requests'),
                ),
              ),
              const SizedBox(height: 12),
            ],
            _WeekStrip(now: now, shifts: all),
            const SizedBox(height: 16),
            if (today != null)
              _TodayCard(shift: today, now: now, busy: _checkingIn, error: _checkInError, onCheckIn: () => _checkIn(today))
            else
              const AppCard(
                child: EmptyState(
                  icon: Icons.event_available_outlined,
                  title: 'No shift today',
                  body: 'You will not receive task offers on days off.',
                ),
              ),
            const GroupLabel('Next shifts'),
            if (upcoming.isEmpty)
              Text('No more shifts this week.', style: Theme.of(context).textTheme.bodySmall)
            else
              AppCard(
                padding: EdgeInsets.zero,
                child: Column(children: [
                  for (var i = 0; i < upcoming.length; i++) ...[
                    if (i > 0) Divider(height: 1, color: context.colors.border),
                    _UpcomingRow(shift: upcoming[i], swap: swaps[upcoming[i].shiftId], incoming: incoming[upcoming[i].shiftId]),
                  ],
                ]),
              ),
          ]),
          );
        },
      ),
    );
  }
}

class _WeekStrip extends StatelessWidget {
  const _WeekStrip({required this.now, required this.shifts});
  final DateTime now;
  final List<Shift> shifts;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final start = DateTime(now.year, now.month, now.day).subtract(Duration(days: now.weekday - 1));
    const letters = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
    return Row(children: [
      for (var i = 0; i < 7; i++)
        Builder(builder: (context) {
          final day = start.add(Duration(days: i));
          final isToday = day.year == now.year && day.month == now.month && day.day == now.day;
          final hasShift = shifts.any((s) => s.isTodayAt(day));
          final fg = isToday ? c.onPrimary : c.text;
          return Expanded(
            child: Semantics(
              label: '${dayLong(day)}${hasShift ? ', shift' : ', day off'}',
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 3),
                padding: const EdgeInsets.symmetric(vertical: 9),
                decoration: BoxDecoration(
                  color: isToday ? c.primary : c.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: isToday ? c.primary : c.border),
                ),
                child: Column(children: [
                  Text(letters[i], style: TextStyle(fontSize: 11.5, color: isToday ? fg : c.textMuted)),
                  const SizedBox(height: 2),
                  Text('${day.day}', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: fg)),
                  const SizedBox(height: 4),
                  Container(
                    width: 5,
                    height: 5,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: hasShift ? (isToday ? c.onPrimary : c.primary) : Colors.transparent,
                    ),
                  ),
                ]),
              ),
            ),
          );
        }),
    ]);
  }
}

class _TodayCard extends StatelessWidget {
  const _TodayCard({required this.shift, required this.now, required this.busy, required this.error, required this.onCheckIn});
  final Shift shift;
  final DateTime now;
  final bool busy;
  final String? error;
  final VoidCallback onCheckIn;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final theme = Theme.of(context).textTheme;
    final ended = !now.isBefore(shift.end);
    final day = dayShort(shift.start);
    final dateLabel = shift.isTodayAt(now)
        ? 'Today · $day'
        : shift.start.isBefore(now)
            ? 'Overnight shift · $day'
            : 'Upcoming shift · $day';
    return AppCard(
      borderColor: shift.isCheckedIn ? c.success : c.primary,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Text(dateLabel,
                style: TextStyle(color: c.primary, fontWeight: FontWeight.w700, fontSize: 12.5)),
          ),
          shift.isCheckedIn
              ? Pill(label: 'Checked in', fg: c.success, bg: c.successTint, dot: true)
              : Pill(label: startsIn(shift.start, shift.end, now), fg: c.primary, bg: c.primaryTint),
        ]),
        const SizedBox(height: 6),
        Text('${shift.label} · ${timeRange(shift.start, shift.end)}', style: theme.titleLarge),
        const SizedBox(height: 14),
        Row(children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(color: c.primaryTint, borderRadius: BorderRadius.circular(12)),
            child: Icon(Icons.point_of_sale_outlined, color: c.primary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(shift.zoneName, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
              if (shift.placeDetail.isNotEmpty) Text(shift.placeDetail, style: theme.bodySmall),
              if (shift.teammates.isNotEmpty) Text('With ${shift.teammates.join(', ')}', style: theme.bodySmall),
            ]),
          ),
        ]),
        const SizedBox(height: 16),
        if (shift.isCheckedIn)
          FactLine(icon: Icons.notifications_active_outlined, text: 'Checked in at ${hm(shift.checkedInAt!)}. Task offers for ${shift.zoneName} are on.', strong: true)
        else if (!ended) ...[
          FilledButton.icon(
            onPressed: busy ? null : onCheckIn,
            icon: busy
                ? SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: c.textDim))
                : const Icon(Icons.login),
            label: Text(busy ? 'Checking in…' : 'Check in'),
          ),
          const SizedBox(height: 10),
          if (error != null)
            InfoBanner(tone: BannerTone.warning, icon: Icons.schedule, title: 'Too early to check in', body: error)
          else
            Text('Check-in opens 15 min before the shift. Task offers for ${shift.zoneName} reach you only while you are checked in.',
                style: theme.bodySmall),
        ] else
          Text('This shift has ended.', style: theme.bodySmall),
      ]),
    );
  }
}

class _UpcomingRow extends StatelessWidget {
  const _UpcomingRow({required this.shift, this.swap, this.incoming});
  final Shift shift;

  /// My latest request for this shift, and an open request a colleague sent me for it.
  final ShiftSwapRequest? swap;
  final ShiftSwapRequest? incoming;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final pending = swap?.status.isOpen ?? false;
    final shown = incoming ?? (swap?.status == SwapStatus.cancelled ? null : swap);
    final pill = shown == null ? null : swapPill(context, shown);
    return InkWell(
      onTap: () => context.go(incoming != null ? '/shifts/swaps/${incoming!.requestId}' : '/shifts/${shift.shiftId}/swap'),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
        child: Row(children: [
          SizedBox(width: 64, child: Text(dayShort(shift.start), style: const TextStyle(fontWeight: FontWeight.w700))),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${shift.label} · ${timeRange(shift.start, shift.end)}'),
              if (pill != null) ...[const SizedBox(height: 4), pill],
            ]),
          ),
          Pill(label: shift.zoneName.split(' · ').first, fg: c.primary, bg: c.primaryTint),
          Padding(
            padding: const EdgeInsets.only(left: 4),
            child: Icon(pending ? Icons.hourglass_top : Icons.swap_horiz, size: 20, color: c.textDim, semanticLabel: 'Request a shift swap'),
          ),
        ]),
      ),
    );
  }
}

class CheckedInScreen extends ConsumerWidget {
  const CheckedInScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final theme = Theme.of(context).textTheme;
    final shift = ref.watch(todayShiftProvider);
    if (shift == null || !shift.isCheckedIn) {
      return Scaffold(appBar: AppBar(title: const Text('Shift')), body: const Center(child: Text('You are not checked in.')));
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Shift started')),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 28), children: [
        AppCard(
          color: c.successTint,
          borderColor: c.successTint,
          padding: const EdgeInsets.all(20),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(color: c.success, shape: BoxShape.circle),
              child: Icon(Icons.check, color: c.onPrimary, size: 28),
            ),
            const SizedBox(height: 14),
            Text("You're checked in", style: theme.headlineSmall),
            const SizedBox(height: 4),
            Text('${shift.label} shift · ${timeRange(shift.start, shift.end)}', style: const TextStyle(fontWeight: FontWeight.w500)),
            const SizedBox(height: 2),
            Text('Checked in at ${hm(shift.checkedInAt!)}${shift.storeName.isEmpty ? '' : ' · ${shift.storeName}'}', style: theme.bodySmall),
          ]),
        ),
        const SizedBox(height: 12),
        AppCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text(shift.zoneName, style: theme.titleMedium)),
              Pill(label: 'Live', fg: c.primary, bg: c.primaryTint, dot: true),
            ]),
            const SizedBox(height: 4),
            Text('Task offers for ${shift.zoneName} are now on. The first eligible staff member to accept gets the task.',
                style: theme.bodySmall),
          ]),
        ),
        if (shift.teammates.isNotEmpty) ...[
          const SizedBox(height: 12),
          AppCard(
            child: FactLine(
              icon: Icons.groups_outlined,
              text: ['You + ${shift.teammates.join(', ')}', shift.zoneDetail].where((s) => s.isNotEmpty).join(' · '),
              strong: true,
            ),
          ),
        ],
        const SizedBox(height: 24),
        FilledButton(onPressed: () => context.go('/tasks'), child: const Text('View my tasks')),
        const SizedBox(height: 4),
        TextButton(onPressed: () => context.go('/shifts'), child: const Text('Back to my shifts')),
      ]),
    );
  }
}
