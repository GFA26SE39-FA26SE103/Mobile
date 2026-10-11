import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../data/models.dart';
import '../../data/providers.dart';
import '../../shared/format.dart';
import '../../shared/widgets.dart';

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
    return Scaffold(
      appBar: AppBar(title: const Text('My shifts')),
      body: shifts.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Could not load shifts: $e')),
        data: (all) {
          final upcoming = all.where((s) => s != today && s.start.isAfter(now)).toList()..sort((a, b) => a.start.compareTo(b.start));
          return ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 28), children: [
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
                    _UpcomingRow(shift: upcoming[i], swap: swaps[upcoming[i].shiftId]),
                  ],
                ]),
              ),
          ]);
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
    return AppCard(
      borderColor: shift.isCheckedIn ? c.success : c.primary,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Text('Today · ${dayShort(shift.start)}',
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
              Text('${shift.floorName} · ${shift.zoneDetail}', style: theme.bodySmall),
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
  const _UpcomingRow({required this.shift, this.swap});
  final Shift shift;
  final ShiftSwapRequest? swap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final pending = swap?.status == SwapStatus.pending;
    return InkWell(
      onTap: () => context.go('/shifts/${shift.shiftId}/swap'),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
        child: Row(children: [
          SizedBox(width: 64, child: Text(dayShort(shift.start), style: const TextStyle(fontWeight: FontWeight.w700))),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${shift.label} · ${timeRange(shift.start, shift.end)}'),
              if (swap != null) ...[
                const SizedBox(height: 4),
                switch (swap!.status) {
                  SwapStatus.pending => Pill(label: 'Swap: waiting for Operator', fg: c.warning, bg: c.warningTint, dot: true),
                  SwapStatus.rejected => Pill(label: 'Swap declined', fg: c.danger, bg: c.dangerTint),
                  SwapStatus.approved => Pill(label: 'Swap approved', fg: c.success, bg: c.successTint),
                },
              ],
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
            Text('Checked in at ${hm(shift.checkedInAt!)} · ${shift.storeName}', style: theme.bodySmall),
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
        const SizedBox(height: 12),
        AppCard(
          child: FactLine(icon: Icons.groups_outlined, text: 'You + ${shift.teammates.join(', ')} · ${shift.zoneDetail}', strong: true),
        ),
        const SizedBox(height: 24),
        FilledButton(onPressed: () => context.go('/tasks'), child: const Text('View my tasks')),
        const SizedBox(height: 4),
        TextButton(onPressed: () => context.go('/shifts'), child: const Text('Back to my shifts')),
      ]),
    );
  }
}

/// Staff asks for a future shift to be swapped; the Operator approves and picks a replacement
/// from staff the system finds available (no direct Staff-to-Staff negotiation).
class SwapRequestScreen extends ConsumerStatefulWidget {
  const SwapRequestScreen({super.key, required this.shiftId});
  final String shiftId;

  @override
  ConsumerState<SwapRequestScreen> createState() => _SwapRequestScreenState();
}

class _SwapRequestScreenState extends ConsumerState<SwapRequestScreen> {
  final _note = TextEditingController();
  SwapReason? _reason;
  bool _sending = false;
  String? _error;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_reason == null) {
      setState(() => _error = 'Choose a reason for the swap.');
      return;
    }
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      await ref.read(operationsRepositoryProvider).requestShiftSwap(widget.shiftId, _reason!, _note.text);
    } on SwapNotAllowed catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final theme = Theme.of(context).textTheme;
    final now = ref.watch(clockProvider)();
    final shift = ref.watch(shiftsProvider).valueOrNull?.where((s) => s.shiftId == widget.shiftId).firstOrNull;
    final swap = ref.watch(swapByShiftProvider)[widget.shiftId];
    if (shift == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Shift swap')),
        body: EmptyState(
          icon: Icons.event_busy,
          title: 'Shift no longer yours',
          body: swap?.status == SwapStatus.approved ? '${swap!.replacement} now covers this shift.' : 'This shift is not on your schedule.',
          action: OutlinedButton(onPressed: () => context.go('/shifts'), child: const Text('Back to my shifts')),
        ),
      );
    }
    final summary = AppCard(
      child: Row(children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(color: c.primaryTint, borderRadius: BorderRadius.circular(12)),
          child: Icon(Icons.event_outlined, color: c.primary),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${dayShort(shift.start)} · ${shift.label}', style: theme.titleMedium),
            Text('${timeRange(shift.start, shift.end)} · ${shift.zoneName}', style: theme.bodySmall),
          ]),
        ),
      ]),
    );

    if (swap != null && swap.status != SwapStatus.rejected) {
      final approved = swap.status == SwapStatus.approved;
      return Scaffold(
        appBar: AppBar(title: const Text('Shift swap')),
        body: ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 28), children: [
          summary,
          const SizedBox(height: 12),
          InfoBanner(
            tone: approved ? BannerTone.success : BannerTone.warning,
            icon: approved ? Icons.check_circle_outline : Icons.hourglass_top,
            title: approved ? 'Swap approved' : 'Request sent · waiting for the Operator',
            body: approved
                ? '${swap.replacement} covers this shift.'
                : 'The Operator picks a replacement from staff the system finds available. Keep this shift until the request is approved.',
          ),
          const SizedBox(height: 12),
          AppCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('REASON', style: theme.labelSmall),
              const SizedBox(height: 4),
              Text(swap.reason.label, style: const TextStyle(fontWeight: FontWeight.w600)),
              if (swap.note.isNotEmpty) ...[const SizedBox(height: 4), Text(swap.note, style: theme.bodySmall)],
              const SizedBox(height: 10),
              Text('Sent ${dayShort(swap.submittedAt)} at ${hm(swap.submittedAt)}', style: theme.bodySmall),
            ]),
          ),
          const SizedBox(height: 22),
          OutlinedButton(onPressed: () => context.go('/shifts'), child: const Text('Back to my shifts')),
        ]),
      );
    }

    final allowed = shift.canRequestSwapAt(now);
    return Scaffold(
      appBar: AppBar(title: const Text('Request a shift swap')),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 28), children: [
        summary,
        if (swap?.status == SwapStatus.rejected) ...[
          const SizedBox(height: 12),
          InfoBanner(tone: BannerTone.danger, icon: Icons.block, title: 'Last request was declined', body: swap!.decisionNote),
        ],
        const SizedBox(height: 16),
        if (!allowed)
          const InfoBanner(
            tone: BannerTone.warning,
            icon: Icons.lock_clock,
            title: 'This shift has started',
            body: 'A shift cannot be changed after it has started. Talk to the Operator on duty.',
          )
        else ...[
          Text('Why do you need a swap?', style: theme.titleMedium),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final r in SwapReason.values)
              ChoiceChip(label: Text(r.label), selected: _reason == r, onSelected: (_) => setState(() => _reason = r)),
          ]),
          const SizedBox(height: 14),
          TextField(
            controller: _note,
            minLines: 2,
            maxLines: 4,
            maxLength: 200,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              hintText: _reason == SwapReason.other ? 'Required: tell the Operator why' : 'Note for the Operator (optional)',
            ),
          ),
          const FactLine(
            icon: Icons.info_outline,
            text: 'The system checks who is free without overlapping shifts or going over working hours. The Operator picks the replacement.',
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            InfoBanner(tone: BannerTone.danger, icon: Icons.error_outline, title: _error!),
          ],
          const SizedBox(height: 18),
          FilledButton(onPressed: _sending ? null : _submit, child: Text(_sending ? 'Sending…' : 'Send request')),
        ],
        const SizedBox(height: 10),
        OutlinedButton(onPressed: () => context.go('/shifts'), child: const Text('Back to my shifts')),
      ]),
    );
  }
}
