import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../data/models.dart';
import '../../data/providers.dart';
import '../../shared/format.dart';
import '../../shared/widgets.dart';

// MF-04 shift swaps: A picks an eligible colleague (SWAP or COVER) → the colleague accepts or
// declines → a Manager approves. Shifts change only on approval; an undecided request expires
// 24 hours before the earliest affected shift.

String _caption(String lead, DateTime start, String label) => '$lead · ${dayShort(start)} · $label'.toUpperCase();

String _when(DateTime t) => '${dayShort(t)}, ${hm(t)}';

/// "YOUR SHIFT · FRI 25 · EVENING" over "14:00–22:00 · Zone B".
class _ShiftCard extends StatelessWidget {
  const _ShiftCard({required this.caption, required this.start, required this.end, required this.zoneName, this.footnote});
  final String caption;
  final DateTime start;
  final DateTime end;
  final String zoneName;
  final String? footnote;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final theme = Theme.of(context).textTheme;
    return AppCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(caption, style: TextStyle(color: c.primary, fontWeight: FontWeight.w700, fontSize: 11.5, letterSpacing: 0.3)),
        const SizedBox(height: 4),
        Text('${timeRange(start, end)} · $zoneName', style: theme.titleMedium),
        if (footnote != null) ...[const SizedBox(height: 2), Text(footnote!, style: theme.bodySmall)],
      ]),
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 16, bottom: 8),
        child: Text(text, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
      );
}

Pill? swapPill(BuildContext context, ShiftSwapRequest r) {
  final c = context.colors;
  if (r.managerNeedsToAssign) {
    return Pill(ellipsis: true, label: 'Manager finding cover', fg: c.warning, bg: c.warningTint, dot: true);
  }
  return switch (r.status) {
    SwapStatus.pendingPeer => r.sentByMe
        ? Pill(ellipsis: true, label: 'Swap: waiting for ${r.otherName}', fg: c.warning, bg: c.warningTint, dot: true)
        : Pill(ellipsis: true, label: 'Waiting for your answer', fg: c.danger, bg: c.dangerTint, dot: true),
    SwapStatus.pendingManager => Pill(ellipsis: true, label: 'Swap: waiting for the Manager', fg: c.warning, bg: c.warningTint, dot: true),
    SwapStatus.approved => Pill(ellipsis: true, label: 'Swap approved', fg: c.success, bg: c.successTint),
    SwapStatus.rejected => Pill(ellipsis: true, label: 'Swap rejected', fg: c.danger, bg: c.dangerTint),
    SwapStatus.declinedByPeer => Pill(ellipsis: true, label: r.sentByMe ? '${r.otherName} declined' : 'You declined', fg: c.danger, bg: c.dangerTint),
    SwapStatus.expired => Pill(ellipsis: true, label: 'Swap request expired', fg: c.textMuted, bg: c.surface2),
    SwapStatus.cancelled => Pill(ellipsis: true, label: 'Swap cancelled', fg: c.textMuted, bg: c.surface2),
  };
}

/// "Your last request …" for a request that ended without a swap.
String? _endedNote(ShiftSwapRequest r) => switch (r.status) {
      SwapStatus.declinedByPeer => '${r.otherName} declined your last request.',
      SwapStatus.rejected => 'The Manager rejected your last request${r.decisionNote == null ? '.' : ': ${r.decisionNote}'}',
      SwapStatus.expired => 'Your last request expired before it was decided.',
      SwapStatus.cancelled => 'Your last request was cancelled${r.cancelledBy == null ? '' : ' by ${r.cancelledBy}'}.',
      _ => null,
    };

Future<bool> _confirm(BuildContext context, String title, String body, String yes) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Keep it')),
          TextButton(onPressed: () => Navigator.of(context).pop(true), child: Text(yes)),
        ],
      ),
    ) ??
    false;

// ------------------------------------------------------------------ request a swap

/// Opened from one of my upcoming shifts: shows the open request for it, or lets me ask a colleague.
class SwapRequestScreen extends ConsumerWidget {
  const SwapRequestScreen({super.key, required this.shiftId});
  final String shiftId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final shifts = ref.watch(shiftsProvider).valueOrNull;
    final shift = shifts?.where((s) => s.shiftId == shiftId).firstOrNull;
    final swap = ref.watch(swapByShiftProvider)[shiftId];
    if (shift == null) {
      if (shifts == null) return Scaffold(appBar: AppBar(title: const Text('Shift swap')), body: const Center(child: CircularProgressIndicator()));
      final approved = swap?.status == SwapStatus.approved;
      return Scaffold(
        appBar: AppBar(title: const Text('Shift swap')),
        body: EmptyState(
          icon: Icons.event_busy,
          title: 'Shift no longer yours',
          body: !approved
              ? 'This shift is not on your schedule.'
              : swap!.type == SwapType.cover
                  ? '${swap.otherName} now covers this shift.'
                  : 'You swapped it with ${swap.otherName}. Their shift is on your schedule now.',
          action: OutlinedButton(onPressed: () => context.go('/shifts'), child: const Text('Back to my shifts')),
        ),
      );
    }
    if (swap != null && swap.status.isOpen) {
      return Scaffold(
        appBar: AppBar(title: const Text('Swap request')),
        body: SwapProgressView(request: swap),
      );
    }
    return _ChooseColleague(shift: shift, lastRequest: swap);
  }
}

class _ChooseColleague extends ConsumerStatefulWidget {
  const _ChooseColleague({required this.shift, this.lastRequest});
  final Shift shift;
  final ShiftSwapRequest? lastRequest;

  @override
  ConsumerState<_ChooseColleague> createState() => _ChooseColleagueState();
}

class _ChooseColleagueState extends ConsumerState<_ChooseColleague> {
  final _note = TextEditingController();
  SwapType _type = SwapType.swap;
  SwapCandidate? _picked;
  bool _details = false;
  SwapReason? _reason;
  bool _managerHelp = false;
  bool _sending = false;
  String? _error;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (_reason == null) {
      setState(() => _error = 'Choose a reason for the swap.');
      return;
    }
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      if (_managerHelp) {
        await ref.read(operationsRepositoryProvider).requestManagerCover(
              shiftId: widget.shift.shiftId,
              reason: _reason,
              note: _note.text,
            );
      } else {
        final picked = _picked!;
        await ref.read(operationsRepositoryProvider).requestShiftSwap(
              shiftId: widget.shift.shiftId,
              type: _type,
              targetUserId: picked.userId,
              targetShiftId: picked.shift?.shiftId,
              reason: _reason,
              note: _note.text,
            );
      }
    } on SwapNotAllowed catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final shift = widget.shift;
    final now = ref.watch(clockProvider)();
    final mine = _ShiftCard(
      caption: _caption(_details ? 'You give' : 'Your shift', shift.start, shift.label),
      start: shift.start,
      end: shift.end,
      zoneName: shift.zoneName,
    );
    if (!shift.canRequestSwapAt(now)) {
      return Scaffold(
        appBar: AppBar(title: const Text('Shift swap')),
        body: ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 28), children: [
          mine,
          const SizedBox(height: 12),
          const InfoBanner(
            tone: BannerTone.warning,
            icon: Icons.lock_clock,
            title: 'This shift has started',
            body: 'A shift cannot be changed after it has started. Talk to the Manager on duty.',
          ),
          const SizedBox(height: 18),
          OutlinedButton(onPressed: () => context.go('/shifts'), child: const Text('Back to my shifts')),
        ]),
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: Text(_details ? (_managerHelp ? 'Ask Manager for cover' : 'Swap request') : 'Choose a colleague'),
        leading: _details ? BackButton(onPressed: () => setState(() { _details = false; _managerHelp = false; })) : null,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
        children: _details ? _detailsStep(mine) : _chooseStep(mine),
      ),
    );
  }

  List<Widget> _chooseStep(Widget mine) {
    final c = context.colors;
    final theme = Theme.of(context).textTheme;
    final candidates = ref.watch(swapCandidatesProvider((widget.shift.shiftId, _type)));
    final ended = widget.lastRequest == null ? null : _endedNote(widget.lastRequest!);
    return [
      mine,
      if (ended != null) ...[
        const SizedBox(height: 12),
        InfoBanner(tone: BannerTone.info, icon: Icons.history, title: ended),
      ],
      const _Label('Type'),
      Wrap(spacing: 8, children: [
        for (final t in SwapType.values)
          ChoiceChip(
            label: Text(t.label),
            selected: _type == t,
            onSelected: (_) => setState(() {
              _type = t;
              _picked = null;
              _managerHelp = false;
            }),
          ),
      ]),
      _Label('Eligible colleagues · ${widget.shift.zoneName}'),
      ...candidates.when(
        loading: () => [const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()))],
        error: (e, _) => [
          InfoBanner(
            tone: BannerTone.warning,
            icon: Icons.lock_clock,
            title: 'This shift cannot be swapped now',
            body: e is SwapNotAllowed ? e.message : '$e',
            action: TextButton(
              style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(0, 36)),
              onPressed: () => ref.invalidate(swapCandidatesProvider((widget.shift.shiftId, _type))),
              child: const Text('Try again'),
            ),
          ),
        ],
        data: (data) => [
          if (data.candidates.isEmpty)
            AppCard(
              child: EmptyState(
                icon: Icons.person_search_outlined,
                title: 'Nobody can take this shift',
                body: _type == SwapType.swap
                    ? 'No colleague has a shift you could take in return without breaking a rule. Try asking for a cover.'
                    : 'No colleague is free at that time within their weekly hours.',
              ),
            )
          else
            for (final candidate in data.candidates) ...[
              _CandidateCard(
                candidate: candidate,
                selected: identical(candidate, _picked) ||
                    (_picked?.userId == candidate.userId && _picked?.shift?.shiftId == candidate.shift?.shiftId),
                onTap: () => setState(() => _picked = candidate),
              ),
              const SizedBox(height: 10),
            ],
          const SizedBox(height: 2),
          AppCard(
            color: c.primaryTint,
            borderColor: c.primaryTint,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Only eligible colleagues are listed', style: TextStyle(color: c.primary, fontWeight: FontWeight.w600)),
              const SizedBox(height: 2),
              Text(
                'Free at both shift times, at or below the 48 h hard limit and not on leave. Up to 40 h is recommended.'
                '${data.hiddenCount > 0 ? ' ${data.hiddenCount} colleague${data.hiddenCount == 1 ? ' is' : 's are'} hidden.' : ''}'
                ' The request must be decided by ${_when(data.deadline)}, or you keep this shift.',
                style: theme.bodySmall,
              ),
            ]),
          ),
        ],
      ),
      const SizedBox(height: 18),
      FilledButton(
        onPressed: _picked == null ? null : () => setState(() { _managerHelp = false; _details = true; }),
        child: Text(_picked == null ? 'Choose a colleague' : 'Choose ${_picked!.fullName}'),
      ),
      const SizedBox(height: 10),
      OutlinedButton.icon(
        onPressed: () => setState(() { _managerHelp = true; _picked = null; _type = SwapType.cover; _details = true; }),
        icon: const Icon(Icons.support_agent),
        label: const Text('Ask Manager to assign cover'),
      ),
      const SizedBox(height: 10),
      OutlinedButton(onPressed: () => context.go('/shifts'), child: const Text('Back to my shifts')),
    ];
  }

  List<Widget> _detailsStep(Widget mine) {
    final theme = Theme.of(context).textTheme;
    final picked = _picked;
    final theirs = picked?.shift;
    return [
      mine,
      _Label(_managerHelp ? 'Who decides' : theirs == null ? 'Covered by' : 'In exchange'),
      if (_managerHelp)
        AppCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Manager assigns an eligible Staff member', style: theme.titleMedium),
            Text('No colleague acceptance is needed. Your shift stays unchanged until the Manager assigns cover.', style: theme.bodySmall),
          ]),
        )
      else if (theirs != null)
        _ShiftCard(
          caption: _caption('You get', theirs.start, theirs.label),
          start: theirs.start,
          end: theirs.end,
          zoneName: theirs.zoneName,
          footnote: "${picked!.fullName}'s shift",
        )
      else
        AppCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(picked!.fullName, style: theme.titleMedium),
            Text('Takes your shift · ${_workload(picked.weeklyHoursAfter, picked.recommended)}', style: theme.bodySmall),
          ]),
        ),
      const _Label('Why do you need a swap?'),
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
          hintText: _managerHelp
              ? 'Add context so the Manager can choose suitable cover (optional)'
              : _reason == SwapReason.other ? 'Required: tell ${picked!.fullName} and the Manager why' : 'Note for ${picked!.fullName} (optional)',
        ),
      ),
      FactLine(
        icon: Icons.info_outline,
        text: _managerHelp
            ? 'The Manager chooses and assigns cover directly. You receive a notification when the schedule changes.'
            : '${picked!.fullName} answers first, then the Manager decides. You keep this shift until it is approved.',
      ),
      if (_error != null) ...[
        const SizedBox(height: 12),
        InfoBanner(tone: BannerTone.danger, icon: Icons.error_outline, title: _error!),
      ],
      const SizedBox(height: 18),
      FilledButton(onPressed: _sending ? null : _send, child: Text(_sending ? 'Sending…' : 'Send request')),
      const SizedBox(height: 10),
      OutlinedButton(onPressed: _sending ? null : () => setState(() { _details = false; _managerHelp = false; }), child: const Text('Back')),
    ];
  }
}

String _hours(double h) => h == h.roundToDouble() ? '${h.toInt()}' : h.toStringAsFixed(1);
String _workload(double h, bool recommended) => '${_hours(h)} / 48 h · ${recommended ? 'recommended' : 'high workload'}';

class _CandidateCard extends StatelessWidget {
  const _CandidateCard({required this.candidate, required this.selected, required this.onTap});
  final SwapCandidate candidate;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final theme = Theme.of(context).textTheme;
    final shift = candidate.shift;
    return Semantics(
      selected: selected,
      button: true,
      child: AppCard(
        onTap: onTap,
        color: selected ? c.primaryTint : null,
        borderColor: selected ? c.primary : null,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (shift != null)
            Text('${dayShort(shift.start)} · ${shift.label} · ${timeRange(shift.start, shift.end)}'.toUpperCase(),
                style: TextStyle(color: c.primary, fontWeight: FontWeight.w700, fontSize: 11.5, letterSpacing: 0.3)),
          const SizedBox(height: 2),
          Row(children: [
            if (selected) ...[Icon(Icons.check, size: 20, color: c.primary), const SizedBox(width: 4)],
            Expanded(child: Text(candidate.fullName, style: theme.titleMedium)),
          ]),
          Text('${shift?.zoneName ?? 'Free at your shift time'} · ${_workload(candidate.weeklyHoursAfter, candidate.recommended)}', style: theme.bodySmall),
        ]),
      ),
    );
  }
}

// --------------------------------------------------------------------- progress

/// Where a request stands, from my side: the shifts involved, the steps so far, and what I can do.
class SwapProgressView extends ConsumerStatefulWidget {
  const SwapProgressView({super.key, required this.request});
  final ShiftSwapRequest request;

  @override
  ConsumerState<SwapProgressView> createState() => _SwapProgressViewState();
}

class _SwapProgressViewState extends ConsumerState<SwapProgressView> {
  bool _busy = false;
  String? _error;

  Future<void> _act(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } on SwapNotAllowed catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _cancel() async {
    final r = widget.request;
    final ok = await _confirm(
      context,
      r.sentByMe ? 'Cancel this request?' : 'Withdraw your acceptance?',
      r.sentByMe ? 'You keep your shift and ${r.otherName} is told.' : 'The swap will not happen. ${r.otherName} and the Manager are told.',
      r.sentByMe ? 'Cancel request' : 'Withdraw',
    );
    if (ok) await _act(() => ref.read(operationsRepositoryProvider).cancelSwap(r.requestId));
  }

  Future<void> _respond(bool accept) => _act(() => ref.read(operationsRepositoryProvider).respondToSwap(widget.request.requestId, accept: accept));

  @override
  Widget build(BuildContext context) {
    final r = widget.request;
    final c = context.colors;
    final theme = Theme.of(context).textTheme;
    final give = r.iGive;
    final get = r.iGet;
    final deadline = r.expiresAt;
    return ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 28), children: [
      if (give != null)
        _ShiftCard(caption: _caption('You give', give.start, give.label), start: give.start, end: give.end, zoneName: give.zoneName)
      else
        AppCard(child: Text('You give nothing back: ${r.otherName} asks you to cover their shift.', style: theme.bodyMedium)),
      _Label(r.managerNeedsToAssign ? 'Cover assignment' : get == null ? 'Covered by' : give == null ? 'You would take' : 'In exchange'),
      if (get != null)
        _ShiftCard(
          caption: _caption(give == null ? 'You take' : 'You get', get.start, get.label),
          start: get.start,
          end: get.end,
          zoneName: get.zoneName,
          footnote: "${r.otherName}'s shift",
        )
      else if (r.managerNeedsToAssign)
        AppCard(child: Text('The Manager is choosing an eligible Staff member. Your schedule has not changed yet.', style: theme.bodyMedium))
      else
        AppCard(child: Text('${r.otherName} covers your shift. Nothing comes back to you.', style: theme.bodyMedium)),
      if (!r.sentByMe && (r.reason != null || r.note.isNotEmpty)) ...[
        _Label('Note from ${r.otherName}${r.reason == null ? '' : ' · ${r.reason!.label}'}'),
        AppCard(child: Text(r.note.isEmpty ? 'No note.' : r.note, style: theme.bodyMedium)),
      ],
      const _Label('Progress'),
      _ProgressCard(request: r),
      if (r.status.isOpen && deadline != null) ...[
        const SizedBox(height: 12),
        AppCard(
          color: c.primaryTint,
          borderColor: c.primaryTint,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(r.managerNeedsToAssign
                ? 'The Manager will assign cover directly'
                : r.canRespond ? 'After you accept, the Manager approves' : 'Keep this shift until it is approved',
                style: TextStyle(color: c.primary, fontWeight: FontWeight.w600)),
            const SizedBox(height: 2),
            Text('Shifts change only after approval. Not decided by ${_when(deadline)}: the request expires and the schedule stays as it is.',
                style: theme.bodySmall),
          ]),
        ),
      ],
      if (_error != null) ...[
        const SizedBox(height: 12),
        InfoBanner(tone: BannerTone.danger, icon: Icons.error_outline, title: _error!),
      ],
      const SizedBox(height: 22),
      if (r.canRespond) ...[
        FilledButton(
          onPressed: _busy ? null : () => _respond(true),
          child: Text(_busy ? 'Sending…' : r.type == SwapType.cover ? 'Accept cover' : 'Accept swap'),
        ),
        const SizedBox(height: 4),
        TextButton(
          style: TextButton.styleFrom(foregroundColor: c.danger),
          onPressed: _busy ? null : () => _respond(false),
          child: const Text('Decline'),
        ),
      ] else ...[
        FilledButton(onPressed: () => context.go('/shifts'), child: const Text('Back to my shifts')),
        if (r.canCancel) ...[
          const SizedBox(height: 4),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: c.danger),
            onPressed: _busy ? null : _cancel,
            child: Text(r.sentByMe ? 'Cancel request' : 'Withdraw my acceptance'),
          ),
        ],
      ],
    ]);
  }
}

class _ProgressCard extends StatelessWidget {
  const _ProgressCard({required this.request});
  final ShiftSwapRequest request;

  @override
  Widget build(BuildContext context) {
    final r = request;
    final c = context.colors;
    final theme = Theme.of(context).textTheme;
    final peer = r.sentByMe ? r.otherName : 'You';
    final accepted = r.targetRespondedAt != null && r.status != SwapStatus.declinedByPeer;
    final steps = <(bool?, String)>[
      (true, '${r.sentByMe ? 'Sent' : 'Sent by ${r.otherName}'} · ${_when(r.submittedAt)}'),
      if (r.managerNeedsToAssign) (null, 'Manager selects and assigns cover'),
      if (r.status == SwapStatus.declinedByPeer)
        (false, '$peer declined${r.targetRespondedAt == null ? '' : ' · ${_when(r.targetRespondedAt!)}'}')
      else if (accepted)
        (true, '$peer accepted · ${_when(r.targetRespondedAt!)}')
      else if (r.status == SwapStatus.pendingPeer)
        (null, r.sentByMe ? '${r.otherName} answers' : 'Your answer'),
      if (r.status == SwapStatus.approved) (true, 'Approved${r.decidedBy == null ? '' : ' by ${r.decidedBy}'}${r.decidedAt == null ? '' : ' · ${_when(r.decidedAt!)}'}'),
      if (r.status == SwapStatus.rejected) (false, 'Rejected${r.decisionNote == null ? '' : ': ${r.decisionNote}'}'),
      if (r.status == SwapStatus.pendingManager || r.status == SwapStatus.pendingPeer) (null, 'Manager decision'),
      if (r.status == SwapStatus.cancelled)
        (false, 'Cancelled${r.cancelledBy == null ? '' : ' by ${r.cancelledBy}'}${r.cancellationReason == null ? '' : ': ${r.cancellationReason}'}'),
      if (r.status == SwapStatus.expired) (false, 'Expired${r.expiresAt == null ? '' : ' · ${_when(r.expiresAt!)}'}: not decided in time'),
    ];
    final step = r.managerNeedsToAssign ? 'MANAGER ASSIGNMENT' : switch (r.status) {
      SwapStatus.pendingPeer => 'STEP 1 OF 2',
      SwapStatus.pendingManager => 'STEP 2 OF 2',
      _ => 'DONE',
    };
    final title = r.managerNeedsToAssign ? 'Manager is finding cover' : switch (r.status) {
      SwapStatus.pendingPeer => r.sentByMe ? 'Waiting for ${r.otherName}' : 'Waiting for your answer',
      SwapStatus.pendingManager => 'Waiting for the Manager',
      SwapStatus.approved => r.type == SwapType.cover && r.sentByMe ? '${r.otherName} covers this shift' : 'Swap approved',
      SwapStatus.rejected => 'Rejected by the Manager',
      SwapStatus.declinedByPeer => r.sentByMe ? '${r.otherName} declined' : 'You declined',
      SwapStatus.cancelled => 'Cancelled',
      SwapStatus.expired => 'Expired',
    };
    return AppCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(step, style: TextStyle(color: c.primary, fontWeight: FontWeight.w700, fontSize: 11.5, letterSpacing: 0.3)),
        const SizedBox(height: 2),
        Text(title, style: theme.titleLarge),
        const SizedBox(height: 6),
        for (final (done, text) in steps)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(
                done == null ? Icons.radio_button_unchecked : (done ? Icons.check : Icons.close),
                size: 16,
                color: done == false ? c.danger : c.textMuted,
              ),
              const SizedBox(width: 8),
              Expanded(child: Text(text, style: theme.bodySmall)),
            ]),
          ),
      ]),
    );
  }
}

// ------------------------------------------------------------------------ inbox

class SwapInboxScreen extends ConsumerWidget {
  const SwapInboxScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final requests = ref.watch(swapRequestsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Swap requests')),
      body: requests.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => EmptyState(
          icon: Icons.cloud_off_outlined,
          title: 'Could not load swap requests',
          body: '$e',
          action: OutlinedButton(onPressed: () => ref.read(operationsRepositoryProvider).refresh(), child: const Text('Try again')),
        ),
        data: (all) {
          final waiting = all.where((r) => r.canRespond).toList();
          final received = all.where((r) => !r.sentByMe && !r.canRespond).toList();
          final sent = all.where((r) => r.sentByMe).toList();
          return RefreshIndicator(
            onRefresh: () => ref.read(operationsRepositoryProvider).refresh(),
            child: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 28), children: [
              if (all.isEmpty)
                const EmptyState(
                  icon: Icons.swap_horiz,
                  title: 'No swap requests',
                  body: 'To swap a shift, open it from My shifts. Requests colleagues send you appear here.',
                ),
              if (waiting.isNotEmpty) ...[
                const GroupLabel('Waiting for you'),
                for (final r in waiting) _InboxTile(request: r),
              ],
              if (received.isNotEmpty) ...[
                const GroupLabel('Received'),
                for (final r in received) _InboxTile(request: r),
              ],
              if (sent.isNotEmpty) ...[
                const GroupLabel('Sent'),
                for (final r in sent) _InboxTile(request: r),
              ],
            ]),
          );
        },
      ),
    );
  }
}

class _InboxTile extends StatelessWidget {
  const _InboxTile({required this.request});
  final ShiftSwapRequest request;

  @override
  Widget build(BuildContext context) {
    final r = request;
    final shift = r.sentByMe ? r.requesterShift : (r.targetShift ?? r.requesterShift);
    final pill = swapPill(context, r);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: AppCard(
        onTap: () => context.go('/shifts/swaps/${r.requestId}'),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(r.sentByMe ? 'To ${r.otherName} · ${r.type.label}' : 'From ${r.otherName} · ${r.type.label}',
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
          const SizedBox(height: 2),
          Text('${dayShort(shift.start)} · ${shift.label} · ${timeRange(shift.start, shift.end)}', style: Theme.of(context).textTheme.bodySmall),
          if (pill != null) ...[const SizedBox(height: 8), pill],
        ]),
      ),
    );
  }
}

class SwapDetailScreen extends ConsumerWidget {
  const SwapDetailScreen({super.key, required this.requestId});
  final String requestId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final requests = ref.watch(swapRequestsProvider).valueOrNull;
    final request = requests?.where((r) => r.requestId == requestId).firstOrNull;
    if (request == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Swap request')),
        body: requests == null
            ? const Center(child: CircularProgressIndicator())
            : EmptyState(
                icon: Icons.search_off,
                title: 'Request not found',
                body: 'It may be older than the requests the app keeps.',
                action: OutlinedButton(onPressed: () => context.go('/shifts/swaps'), child: const Text('All swap requests')),
              ),
      );
    }
    return Scaffold(
      appBar: AppBar(title: Text(request.sentByMe ? 'Swap request' : 'Request from ${request.otherName}')),
      body: SwapProgressView(request: request),
    );
  }
}
