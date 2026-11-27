import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../data/models.dart';
import '../../data/providers.dart';
import '../../shared/format.dart';
import '../../shared/widgets.dart';
import 'swap_screens.dart';

final _weekday = DateFormat('EEE');
final _month = DateFormat('MMM');
final _dayHeader = DateFormat('EEEE, MMM d');

DateTime _dateOnly(DateTime t) {
  final l = t.toLocal();
  return DateTime(l.year, l.month, l.day);
}

/// Shifts that touch [day]: one that starts that day, or an overnight shift that runs into it.
List<Shift> _shiftsOn(Iterable<Shift> shifts, DateTime day) {
  final from = _dateOnly(day);
  final to = from.add(const Duration(days: 1));
  return shifts.where((s) => s.start.toLocal().isBefore(to) && s.end.toLocal().isAfter(from)).toList()
    ..sort((a, b) => a.start.compareTo(b.start));
}

class MyShiftsScreen extends ConsumerStatefulWidget {
  const MyShiftsScreen({super.key});

  @override
  ConsumerState<MyShiftsScreen> createState() => _MyShiftsScreenState();
}

class _MyShiftsScreenState extends ConsumerState<MyShiftsScreen> {
  bool _checkingIn = false;
  String? _checkInError;
  DateTime? _selected;

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
    final incoming = ref.watch(incomingSwapByShiftProvider);
    final repo = ref.read(operationsRepositoryProvider);
    final selected = _selected ?? _dateOnly(now);
    return Scaffold(
      appBar: AppBar(title: const Text('My shifts')),
      body: shifts.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => EmptyState(
          icon: Icons.cloud_off_outlined,
          title: 'Could not load shifts',
          body: '$e',
          action: OutlinedButton(onPressed: repo.refresh, child: const Text('Try again')),
        ),
        data: (all) {
          final onDay = _shiftsOn(all, selected);
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
              _DayStrip(now: now, selected: selected, shifts: all, onSelect: (day) => setState(() => _selected = day)),
              GroupLabel(_dayHeader.format(selected)),
              if (onDay.isEmpty)
                AppCard(child: Text('No shift', style: Theme.of(context).textTheme.bodyMedium))
              else
                for (final shift in onDay) ...[
                  if (identical(shift, today) || shift.shiftId == today?.shiftId)
                    _TodayCard(
                      shift: shift,
                      now: now,
                      busy: _checkingIn,
                      error: _checkInError,
                      onCheckIn: () => _checkIn(shift),
                      onOpen: () => context.go('/shifts/${shift.shiftId}'),
                    )
                  else
                    _ShiftRow(shift: shift, swap: swaps[shift.shiftId], incoming: incoming[shift.shiftId]),
                  const SizedBox(height: 10),
                ],
              const SizedBox(height: 8),
              AppCard(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                onTap: () => context.go('/shifts/swaps'),
                child: Row(children: [
                  Icon(Icons.swap_horiz, color: context.colors.primary),
                  const SizedBox(width: 10),
                  const Expanded(child: Text('Swap requests', style: TextStyle(fontWeight: FontWeight.w600))),
                  if (awaiting > 0) ...[
                    Pill(label: '$awaiting', fg: context.colors.onPrimary, bg: context.colors.danger, solid: true),
                    const SizedBox(width: 6),
                  ],
                  Icon(Icons.chevron_right, color: context.colors.textDim),
                ]),
              ),
            ]),
          );
        },
      ),
    );
  }
}

/// A scrollable calendar strip: this week and the next two, each day with its month.
class _DayStrip extends StatelessWidget {
  const _DayStrip({required this.now, required this.selected, required this.shifts, required this.onSelect});
  final DateTime now;
  final DateTime selected;
  final List<Shift> shifts;
  final ValueChanged<DateTime> onSelect;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final today = _dateOnly(now);
    final start = today.subtract(Duration(days: today.weekday - 1));
    final days = [for (var i = 0; i < 21; i++) DateTime(start.year, start.month, start.day + i)];
    final initial = days.indexWhere((d) => d == selected).clamp(0, days.length - 1);
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      controller: ScrollController(initialScrollOffset: ((initial - 2).clamp(0, days.length) * 62).toDouble()),
      child: Row(children: [
        for (var i = 0; i < days.length; i++) ...[
          if (i > 0) const SizedBox(width: 6),
          Builder(builder: (context) {
          final day = days[i];
          final isSelected = day == selected;
          final isToday = day == today;
          final hasShift = _shiftsOn(shifts, day).isNotEmpty;
          final fg = isSelected ? c.onPrimary : c.text;
          return Semantics(
            button: true,
            selected: isSelected,
            label: '${_dayHeader.format(day)}${hasShift ? ', shift' : ', no shift'}',
            child: InkWell(
              key: hasShift ? const ValueKey('shift-day') : null,
              borderRadius: BorderRadius.circular(12),
              onTap: () => onSelect(day),
              child: Container(
                width: 56,
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  color: isSelected ? c.primary : c.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: isSelected || isToday ? c.primary : c.border, width: isToday && !isSelected ? 1.5 : 1),
                ),
                child: ExcludeSemantics(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Text(_weekday.format(day), style: TextStyle(fontSize: 11.5, color: isSelected ? fg : c.textMuted)),
                    Text('${day.day}', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: fg)),
                    Text(_month.format(day), style: TextStyle(fontSize: 10.5, color: isSelected ? fg : c.textMuted)),
                    const SizedBox(height: 3),
                    Container(
                      width: 5,
                      height: 5,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: hasShift ? (isSelected ? c.onPrimary : c.primary) : Colors.transparent,
                      ),
                    ),
                  ]),
                ),
              ),
            ),
          );
          }),
        ],
      ]),
    );
  }
}

class _TodayCard extends StatelessWidget {
  const _TodayCard({
    required this.shift,
    required this.now,
    required this.busy,
    required this.error,
    required this.onCheckIn,
    required this.onOpen,
  });
  final Shift shift;
  final DateTime now;
  final bool busy;
  final String? error;
  final VoidCallback onCheckIn;
  final VoidCallback onOpen;

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
      onTap: onOpen,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Text(dateLabel, style: TextStyle(color: c.primary, fontWeight: FontWeight.w700, fontSize: 12.5)),
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
          Icon(Icons.chevron_right, color: c.textDim, semanticLabel: 'Shift detail'),
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

/// One shift of the selected day; opens its Shift detail.
class _ShiftRow extends StatelessWidget {
  const _ShiftRow({required this.shift, this.swap, this.incoming});
  final Shift shift;

  /// My latest request for this shift, and an open request a colleague sent me for it.
  final ShiftSwapRequest? swap;
  final ShiftSwapRequest? incoming;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final shown = incoming ?? (swap?.status == SwapStatus.cancelled ? null : swap);
    final pill = shown == null ? null : swapPill(context, shown);
    return AppCard(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
      onTap: () => context.go('/shifts/${shift.shiftId}'),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${shift.label} · ${timeRange(shift.start, shift.end)}', style: const TextStyle(fontWeight: FontWeight.w600)),
            if (pill != null) ...[const SizedBox(height: 4), pill],
          ]),
        ),
        Pill(label: shift.zoneName.split(' · ').first, fg: c.primary, bg: c.primaryTint),
        Padding(
          padding: const EdgeInsets.only(left: 4),
          child: Icon(Icons.chevron_right, size: 20, color: c.textDim, semanticLabel: 'Shift detail'),
        ),
      ]),
    );
  }
}

/// One shift: when, where, its state and, while it can still change, the way into a swap.
class ShiftDetailScreen extends ConsumerWidget {
  const ShiftDetailScreen({super.key, required this.shiftId});
  final String shiftId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final theme = Theme.of(context).textTheme;
    final now = ref.watch(clockProvider)();
    final shifts = ref.watch(shiftsProvider).valueOrNull;
    final shift = shifts?.where((s) => s.shiftId == shiftId).firstOrNull;
    if (shift == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Shift detail')),
        body: shifts == null
            ? const Center(child: CircularProgressIndicator())
            : EmptyState(
                icon: Icons.event_busy,
                title: 'Shift not found',
                body: 'This shift is no longer on your schedule.',
                action: OutlinedButton(onPressed: () => context.go('/shifts'), child: const Text('Back to my shifts')),
              ),
      );
    }
    final mine = ref.watch(swapByShiftProvider)[shiftId];
    final incoming = ref.watch(incomingSwapByShiftProvider)[shiftId];
    final shown = incoming ?? (mine?.status == SwapStatus.cancelled ? null : mine);
    final pill = shown == null ? null : swapPill(context, shown);
    final (status, fg, bg) = shift.isCheckedIn
        ? ('Checked in', c.success, c.successTint)
        : !now.isBefore(shift.end)
            ? ('Ended', c.textMuted, c.surface2)
            : shift.isActiveAt(now)
                ? ('In progress', c.warning, c.warningTint)
                : ('Scheduled · ${startsIn(shift.start, shift.end, now)}', c.primary, c.primaryTint);
    return Scaffold(
      appBar: AppBar(title: const Text('Shift detail')),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 28), children: [
        AppCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(
                child: Text(_dayHeader.format(shift.start.toLocal()).toUpperCase(),
                    style: TextStyle(color: c.primary, fontWeight: FontWeight.w700, fontSize: 12.5)),
              ),
              Pill(label: status, fg: fg, bg: bg, dot: shift.isCheckedIn),
            ]),
            const SizedBox(height: 6),
            Text(shift.label, style: theme.titleLarge),
            const SizedBox(height: 12),
            FactLine(icon: Icons.schedule, text: timeRange(shift.start, shift.end), strong: true),
            const SizedBox(height: 6),
            FactLine(icon: Icons.place_outlined, text: [shift.zoneName, shift.placeDetail].where((s) => s.isNotEmpty).join(' · ')),
            if (shift.teammates.isNotEmpty) ...[
              const SizedBox(height: 6),
              FactLine(icon: Icons.groups_outlined, text: 'With ${shift.teammates.join(', ')}'),
            ],
            if (shift.isCheckedIn) ...[
              const SizedBox(height: 6),
              FactLine(icon: Icons.login, text: 'Checked in at ${hm(shift.checkedInAt!)}'),
            ],
            if (pill != null) ...[const SizedBox(height: 12), pill],
          ]),
        ),
        const SizedBox(height: 22),
        if (incoming != null)
          FilledButton(onPressed: () => context.go('/shifts/swaps/${incoming.requestId}'), child: const Text('Review swap request'))
        else if (mine != null && mine.status.isOpen)
          FilledButton(onPressed: () => context.go('/shifts/$shiftId/swap'), child: const Text('View swap request'))
        else if (shift.canRequestSwapAt(now))
          FilledButton.icon(
            onPressed: () => context.go('/shifts/$shiftId/swap'),
            icon: const Icon(Icons.swap_horiz),
            label: const Text('Swap shift'),
          )
        else
          Text('A shift cannot be swapped after it has started.', style: theme.bodySmall, textAlign: TextAlign.center),
        const SizedBox(height: 10),
        OutlinedButton(onPressed: () => context.go('/shifts'), child: const Text('Back to my shifts')),
      ]),
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
