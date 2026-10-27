import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../data/models.dart';
import '../../data/providers.dart';
import '../../shared/format.dart';
import '../../shared/widgets.dart';

final incomingOfferProvider = StreamProvider<TaskOffer>((ref) => ref.watch(operationsRepositoryProvider).incomingOffers());

String? _showingOfferId;

/// Opens the offer sheet for [offerId] unless it is already on screen.
Future<void> showTaskOffer(BuildContext context, String offerId) async {
  if (_showingOfferId == offerId) return;
  _showingOfferId = offerId;
  try {
    final task = await showModalBottomSheet<StaffTask>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => TaskOfferSheet(offerId: offerId),
    );
    if (task != null && context.mounted) {
      context.go('/tasks/${task.taskId}');
      final message = task.isDeferred ? 'Accepted · start by ${hm(task.plannedStartAt!)}' : 'Task started · ${task.title}';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    }
  } finally {
    if (_showingOfferId == offerId) _showingOfferId = null;
  }
}

/// Puts each delivered offer in front of the staff member, wherever they are in the app.
class TaskOfferHost extends ConsumerStatefulWidget {
  const TaskOfferHost({super.key, required this.child});
  final Widget child;

  @override
  ConsumerState<TaskOfferHost> createState() => _TaskOfferHostState();
}

class _TaskOfferHostState extends ConsumerState<TaskOfferHost> {
  @override
  void dispose() {
    // The shell can go away with a sheet still open (sign-out); never block the next session's offers.
    _showingOfferId = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(incomingOfferProvider, (previous, next) {
      final offer = next.valueOrNull;
      if (offer == null || !offer.isOpen) return;
      HapticFeedback.heavyImpact();
      if (_showingOfferId == null) showTaskOffer(context, offer.offerId);
    });
    return widget.child;
  }
}

enum _Phase { deciding, choosingLater, choosingReason, sending }

class TaskOfferSheet extends ConsumerStatefulWidget {
  const TaskOfferSheet({super.key, required this.offerId});
  final String offerId;

  @override
  ConsumerState<TaskOfferSheet> createState() => _TaskOfferSheetState();
}

class _TaskOfferSheetState extends ConsumerState<TaskOfferSheet> {
  _Phase _phase = _Phase.deciding;
  Duration _later = handleLaterOptions[1];
  DeclineReason? _reason;
  String? _error;
  TaskAlreadyTaken? _taken;
  late final Timer _ticker;
  int _roundAttempt = 0;
  int _roundSeconds = 1;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker.cancel();
    super.dispose();
  }

  Future<void> _respond(TaskResponse response) async {
    if (response == TaskResponse.cannotHandle && _reason == null) {
      setState(() => _error = 'Choose a reason so the Operator knows why.');
      return;
    }
    final previous = _phase;
    setState(() {
      _phase = _Phase.sending;
      _error = null;
    });
    try {
      final task = await ref.read(operationsRepositoryProvider).respondToOffer(
            widget.offerId,
            response,
            handleAfter: response == TaskResponse.handleLater ? _later : null,
            reason: response == TaskResponse.cannotHandle ? _reason : null,
          );
      if (mounted) Navigator.of(context).pop(task);
    } on TaskAlreadyTaken catch (e) {
      if (mounted) setState(() => _taken = e);
    } on WorkloadLimitReached {
      if (mounted) {
        setState(() {
          _phase = previous;
          _error = 'You already have ${Eligibility.workloadLimit} active tasks. Finish one before taking another.';
        });
      }
    } on OfferNoLongerOpen {
      if (mounted) {
        setState(() {
          _phase = previous;
          _error = 'This offer is no longer open.';
        });
      }
    } on OperationFailed catch (e) {
      if (mounted) {
        setState(() {
          _phase = previous;
          _error = e.message;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final offer = ref.watch(offerProvider(widget.offerId)).valueOrNull;
    final now = ref.watch(clockProvider)();
    if (offer == null) return const SizedBox(height: 200, child: Center(child: CircularProgressIndicator()));

    final taken = _taken ??
        (offer.status == OfferStatus.takenByOther ? TaskAlreadyTaken(takenBy: offer.takenBy, takenAt: offer.takenAt) : null);
    if (taken != null) return _TakenView(offer: offer, taken: taken);
    if (offer.status == OfferStatus.escalated) return _EscalatedView(offer: offer);
    if (offer.status == OfferStatus.eventCleared) return _ClearedView(offer: offer);
    if (offer.status == OfferStatus.withdrawn) return _WithdrawnView(offer: offer);

    final c = context.colors;
    final theme = Theme.of(context).textTheme;
    final sending = _phase == _Phase.sending;
    final next = offer.nextAlertAt;
    final secondsLeft = next == null ? null : math.max(0, next.difference(now).inSeconds);
    // The ring spans this round as first seen, since the server sets the retry interval.
    if (secondsLeft != null && offer.attempt != _roundAttempt) {
      _roundAttempt = offer.attempt;
      _roundSeconds = math.max(1, secondsLeft);
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(color: c.danger, borderRadius: BorderRadius.circular(12)),
          child: Row(children: [
            Icon(Icons.vibration, color: c.onPrimary, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text('New task offer in your zone',
                  style: TextStyle(color: c.onPrimary, fontWeight: FontWeight.w700, fontSize: 13, letterSpacing: 0.2)),
            ),
            Text(timeAgo(offer.createdAt, now), style: TextStyle(color: c.onPrimary, fontSize: 12.5)),
          ]),
        ),
        const SizedBox(height: 16),
        Text(offer.title, style: theme.titleLarge?.copyWith(fontSize: 22)),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
          SeverityChip(offer.priority, suffix: offer.origin.label, solid: offer.priority == Severity.critical),
          if (offer.raisedFrom != null) Pill(label: 'Raised from ${offer.raisedFrom!.label}', fg: c.danger, bg: c.dangerTint, dot: true),
          Text(offer.sourceCode, style: theme.bodySmall),
        ]),
        const SizedBox(height: 12),
        FactLine(icon: Icons.place_outlined, text: place(offer.zoneName, offer.location), strong: true),
        if (offer.measurement.isNotEmpty) FactLine(icon: Icons.insights_outlined, text: offer.measurement, strong: true),
        if (offer.instructions.isNotEmpty) FactLine(icon: Icons.assignment_outlined, text: offer.instructions, strong: true),
        const SizedBox(height: 12),
        AppCard(
          color: c.surface2,
          borderColor: c.surface2,
          padding: const EdgeInsets.all(12),
          child: Row(children: [
            if (secondsLeft != null)
              _Countdown(seconds: secondsLeft, total: math.max(_roundSeconds, secondsLeft))
            else
              Icon(Icons.support_agent, color: c.textMuted, size: 28),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Offer ${offer.attempt} of ${offer.maxAttempts}', style: const TextStyle(fontWeight: FontWeight.w600)),
                Text(
                  secondsLeft != null && offer.attempt < offer.maxAttempts
                      ? 'Sent to ${offer.recipients} staff on shift. Offered again in $secondsLeft s if nobody accepts.'
                      : 'Last offer. If nobody accepts it soon, the Operator assigns it.',
                  style: theme.bodySmall,
                ),
              ]),
            ),
          ]),
        ),
        if (_error != null) ...[
          const SizedBox(height: 12),
          InfoBanner(tone: BannerTone.danger, icon: Icons.error_outline, title: _error!),
        ],
        const SizedBox(height: 16),
        ...switch (_phase) {
          _Phase.choosingLater => _laterChoices(theme, c),
          _Phase.choosingReason => _reasonChoices(theme, c),
          _ => _mainChoices(theme, c, sending),
        },
      ]),
    );
  }

  List<Widget> _mainChoices(TextTheme theme, AppColors c, bool sending) => [
        FilledButton.icon(
          style: FilledButton.styleFrom(backgroundColor: c.success),
          onPressed: sending ? null : () => _respond(TaskResponse.handleNow),
          icon: sending
              ? SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: c.textDim))
              : const Icon(Icons.bolt),
          label: Text(sending ? 'Sending…' : 'Handle now'),
        ),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          onPressed: sending ? null : () => setState(() => _phase = _Phase.choosingLater),
          icon: const Icon(Icons.schedule),
          label: const Text('Accept, handle later'),
        ),
        const SizedBox(height: 4),
        TextButton(
          style: TextButton.styleFrom(foregroundColor: c.danger),
          onPressed: sending ? null : () => setState(() => _phase = _Phase.choosingReason),
          child: const Text('Cannot handle'),
        ),
        Text('The first staff member to accept gets the task.', textAlign: TextAlign.center, style: theme.bodySmall),
      ];

  /// Delays whose start still falls inside the checked-in shift; the server refuses later ones.
  List<Duration> _laterOptions() {
    final now = ref.read(clockProvider)();
    final end = ref.read(eligibilityProvider).valueOrNull?.shiftEndsAt;
    return [for (final d in handleLaterOptions) if (end == null || now.add(d).isBefore(end)) d];
  }

  List<Widget> _laterChoices(TextTheme theme, AppColors c) {
    final options = _laterOptions();
    final later = options.contains(_later) ? _later : options.firstOrNull;
    return [
      Text('When will you start?', style: theme.titleMedium),
      const SizedBox(height: 4),
      Text('You take responsibility now. If you have not started by then, the task is marked overdue.', style: theme.bodySmall),
      const SizedBox(height: 10),
      if (later == null)
        InfoBanner(
          tone: BannerTone.warning,
          icon: Icons.schedule,
          title: 'Your shift ends too soon to start later',
          body: 'Handle it now or choose Cannot handle.',
        )
      else
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final d in options)
            ChoiceChip(label: Text('In ${d.inMinutes} min'), selected: later == d, onSelected: (_) => setState(() => _later = d)),
        ]),
      const SizedBox(height: 16),
      if (later != null)
        FilledButton(
          onPressed: () {
            _later = later;
            _respond(TaskResponse.handleLater);
          },
          child: Text('Accept · start by ${hm(ref.read(clockProvider)().add(later))}'),
        ),
      const SizedBox(height: 10),
      OutlinedButton(onPressed: () => setState(() => _phase = _Phase.deciding), child: const Text('Back')),
    ];
  }

  List<Widget> _reasonChoices(TextTheme theme, AppColors c) => [
        Text("Why can't you handle it?", style: theme.titleMedium),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final r in DeclineReason.values)
            ChoiceChip(label: Text(r.label), selected: _reason == r, onSelected: (_) => setState(() => _reason = r)),
        ]),
        const SizedBox(height: 16),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: c.text, foregroundColor: c.bg),
          onPressed: () => _respond(TaskResponse.cannotHandle),
          child: const Text('Send: cannot handle'),
        ),
        const SizedBox(height: 10),
        OutlinedButton(onPressed: () => setState(() => _phase = _Phase.deciding), child: const Text('Back')),
      ];
}

class _Countdown extends StatelessWidget {
  const _Countdown({required this.seconds, required this.total});
  final int seconds;
  final int total;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return SizedBox(
      width: 44,
      height: 44,
      child: Stack(alignment: Alignment.center, children: [
        CircularProgressIndicator(value: (seconds / total).clamp(0, 1).toDouble(), strokeWidth: 3.5, color: c.danger, backgroundColor: c.dangerTint),
        Text('$seconds', style: TextStyle(fontWeight: FontWeight.w700, color: c.danger, fontFeatures: const [FontFeature.tabularFigures()])),
      ]),
    );
  }
}

class _TakenView extends StatelessWidget {
  const _TakenView({required this.offer, required this.taken});
  final TaskOffer offer;
  final TaskAlreadyTaken taken;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final theme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Align(
          alignment: Alignment.centerLeft,
          child: Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(color: c.dangerTint, shape: BoxShape.circle),
            child: Icon(Icons.priority_high, color: c.danger),
          ),
        ),
        const SizedBox(height: 14),
        Text('Task already taken', style: theme.titleLarge),
        const SizedBox(height: 6),
        Text('${taken.takenBy ?? 'Another staff member'} accepted this task first. The offer is now withdrawn.',
            style: theme.bodyMedium?.copyWith(color: c.textMuted)),
        const SizedBox(height: 14),
        AppCard(
          color: c.surface2,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text(offer.title, style: const TextStyle(fontWeight: FontWeight.w600))),
              Text(offer.sourceCode, style: theme.bodySmall),
            ]),
            const SizedBox(height: 4),
            Text(
              [
                offer.zoneName.split(' · ').first,
                if (taken.takenBy != null) 'Accepted by ${taken.takenBy}${taken.takenAt == null ? '' : ' at ${hm(taken.takenAt!)}'}',
              ].join(' · '),
              style: theme.bodySmall,
            ),
          ]),
        ),
        const SizedBox(height: 18),
        FilledButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Back to my tasks')),
      ]),
    );
  }
}

class _EscalatedView extends StatelessWidget {
  const _EscalatedView({required this.offer});
  final TaskOffer offer;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('Offer passed to the Operator', style: theme.titleLarge),
        const SizedBox(height: 6),
        Text('Nobody accepted "${offer.title}" after ${offer.maxAttempts} offers, so the Operator will assign it.',
            style: theme.bodyMedium),
        const SizedBox(height: 18),
        FilledButton(onPressed: () => Navigator.of(context).pop(), child: const Text('OK')),
      ]),
    );
  }
}

class _ClearedView extends StatelessWidget {
  const _ClearedView({required this.offer});
  final TaskOffer offer;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final theme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Align(
          alignment: Alignment.centerLeft,
          child: Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(color: c.successTint, shape: BoxShape.circle),
            child: Icon(Icons.check, color: c.success),
          ),
        ),
        const SizedBox(height: 14),
        Text('No longer needed', style: theme.titleLarge),
        const SizedBox(height: 6),
        Text(
          'The camera shows ${offer.zoneName.split(' · ').first} back to normal, so this offer was withdrawn. Nothing to do.',
          style: theme.bodyMedium?.copyWith(color: c.textMuted),
        ),
        const SizedBox(height: 14),
        AppCard(
          color: c.surface2,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text(offer.title, style: const TextStyle(fontWeight: FontWeight.w600))),
              Text(offer.sourceCode, style: theme.bodySmall),
            ]),
            const SizedBox(height: 4),
            Text('Cleared at ${hm(offer.eventClearedAt!)}', style: theme.bodySmall),
          ]),
        ),
        const SizedBox(height: 18),
        FilledButton(onPressed: () => Navigator.of(context).pop(), child: const Text('OK')),
      ]),
    );
  }
}

/// Closed for another reason, e.g. the Operator assigned the task by hand.
class _WithdrawnView extends StatelessWidget {
  const _WithdrawnView({required this.offer});
  final TaskOffer offer;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('Offer withdrawn', style: theme.titleLarge),
        const SizedBox(height: 6),
        Text('"${offer.title}" is no longer offered to you. The Operator may have assigned it to someone.', style: theme.bodyMedium),
        const SizedBox(height: 18),
        FilledButton(onPressed: () => Navigator.of(context).pop(), child: const Text('OK')),
      ]),
    );
  }
}
