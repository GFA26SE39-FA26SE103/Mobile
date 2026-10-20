import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../data/models.dart';
import '../../data/providers.dart';
import '../../shared/format.dart';
import '../../shared/widgets.dart';

class MyTasksScreen extends ConsumerStatefulWidget {
  const MyTasksScreen({super.key});

  @override
  ConsumerState<MyTasksScreen> createState() => _MyTasksScreenState();
}

class _MyTasksScreenState extends ConsumerState<MyTasksScreen> {
  TaskStatus _tab = TaskStatus.accepted;

  @override
  Widget build(BuildContext context) {
    final tasks = ref.watch(tasksProvider).valueOrNull ?? const <StaffTask>[];
    final eligibility = ref.watch(eligibilityProvider).valueOrNull;
    final openOffers = ref.watch(openOffersProvider).valueOrNull ?? const [];
    final now = ref.watch(clockProvider)();
    final visible = tasks.where((t) => t.status == _tab).toList()
      ..sort((a, b) => (a.plannedStartAt ?? a.acceptedAt).compareTo(b.plannedStartAt ?? b.acceptedAt));

    return Scaffold(
      appBar: AppBar(
        title: const Text('My tasks'),
        actions: [
          Padding(padding: const EdgeInsets.only(right: 16), child: ShiftStatusPill(onShift: eligibility?.checkedIn ?? false)),
        ],
      ),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 14, 16, 28), children: [
        _Segments(
          value: _tab,
          counts: {for (final s in TaskStatus.values) s: tasks.where((t) => t.status == s).length},
          onChanged: (s) => setState(() => _tab = s),
        ),
        const SizedBox(height: 14),
        if (openOffers.isNotEmpty) ...[
          InfoBanner(
            tone: BannerTone.danger,
            icon: Icons.notifications_active_outlined,
            title: '${openOffers.length} task offer${openOffers.length == 1 ? '' : 's'} waiting for you',
            body: openOffers.first.title,
            action: TextButton(
              style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(0, 36)),
              onPressed: () => context.go('/alerts'),
              child: const Text('Open offers'),
            ),
          ),
          const SizedBox(height: 12),
        ],
        if (eligibility != null && eligibility.checkedIn && eligibility.atWorkloadLimit) ...[
          InfoBanner(
            tone: BannerTone.warning,
            icon: Icons.pause_circle_outline,
            title: 'New offers are paused',
            body: 'You have ${eligibility.limit} active tasks. Finish one to receive new task offers.',
          ),
          const SizedBox(height: 12),
        ],
        if (visible.isEmpty)
          _emptyFor(_tab, eligibility)
        else
          for (final t in visible) ...[
            _TaskCard(task: t, now: now, onTap: () => context.go('/tasks/${t.taskId}')),
            const SizedBox(height: 10),
          ],
      ]),
    );
  }

  Widget _emptyFor(TaskStatus tab, Eligibility? e) => switch (tab) {
        TaskStatus.accepted => EmptyState(
            icon: Icons.inbox_outlined,
            title: 'No accepted tasks',
            body: e?.checkedIn ?? false
                ? 'Task offers for ${e!.zoneName} appear as they come in. Tasks you accept for later wait here.'
                : 'Check in to your shift to start receiving task offers for your zone.',
            action: e?.checkedIn ?? false
                ? null
                : OutlinedButton(onPressed: () => context.go('/shifts'), child: const Text('Go to my shifts')),
          ),
        TaskStatus.inProgress => const EmptyState(
            icon: Icons.play_circle_outline,
            title: 'Nothing in progress',
            body: 'Tasks you handle now or start later appear here.',
          ),
        TaskStatus.done => const EmptyState(
            icon: Icons.task_alt,
            title: 'No finished tasks yet',
            body: 'Completed tasks from this shift appear here.',
          ),
      };
}

class _Segments extends StatelessWidget {
  const _Segments({required this.value, required this.counts, required this.onChanged});
  final TaskStatus value;
  final Map<TaskStatus, int> counts;
  final ValueChanged<TaskStatus> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(color: c.track, borderRadius: BorderRadius.circular(12)),
      child: Row(children: [
        for (final s in TaskStatus.values)
          Expanded(
            child: Semantics(
              selected: s == value,
              button: true,
              child: GestureDetector(
                onTap: () => onChanged(s),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeOutCubic,
                  height: 38,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: s == value ? c.surface : Colors.transparent,
                    borderRadius: BorderRadius.circular(10),
                    boxShadow: s == value
                        ? [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 6, offset: const Offset(0, 2))]
                        : null,
                  ),
                  child: Text(
                    s == TaskStatus.done ? s.label : '${s.label} · ${counts[s] ?? 0}',
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: s == value ? FontWeight.w600 : FontWeight.w500,
                      color: s == value ? c.text : c.textMuted,
                    ),
                  ),
                ),
              ),
            ),
          ),
      ]),
    );
  }
}

/// "Starts by 21:45" / "Overdue" for deferred tasks; null otherwise.
Widget? _scheduleChip(BuildContext context, StaffTask task, DateTime now) {
  if (!task.isDeferred) return null;
  final c = context.colors;
  return task.isOverdueAt(now)
      ? Pill(label: 'Overdue · was ${hm(task.plannedStartAt!)}', fg: c.danger, bg: c.dangerTint, dot: true)
      : Pill(label: 'Starts by ${hm(task.plannedStartAt!)}', fg: c.info, bg: c.infoTint);
}

/// What happened to the source OperationalEvent since the task was accepted.
List<Widget> _eventChips(BuildContext context, StaffTask task) {
  final c = context.colors;
  return [
    if (task.raisedFrom != null && task.isActive) Pill(label: 'Raised from ${task.raisedFrom!.label}', fg: c.danger, bg: c.dangerTint, dot: true),
    if (task.eventClearedAt != null) Pill(label: 'Event cleared ${hm(task.eventClearedAt!)}', fg: c.success, bg: c.successTint),
  ];
}

class _TaskCard extends StatelessWidget {
  const _TaskCard({required this.task, required this.now, required this.onTap});
  final StaffTask task;
  final DateTime now;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final urgent = task.isActive && (task.priority == Severity.critical || task.isOverdueAt(now));
    final chips = [?_scheduleChip(context, task, now), ..._eventChips(context, task)];
    return AppCard(
      onTap: onTap,
      borderColor: urgent ? c.danger : null,
      padding: const EdgeInsets.fromLTRB(16, 14, 10, 14),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              SeverityChip(task.priority),
              const SizedBox(width: 6),
              Flexible(child: Text(task.origin.label, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.bodySmall)),
              const Spacer(),
              Text(timeAgo(task.acceptedAt, now), style: Theme.of(context).textTheme.bodySmall),
            ]),
            const SizedBox(height: 8),
            Text(task.title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            const SizedBox(height: 4),
            Row(children: [
              Icon(Icons.place_outlined, size: 16, color: c.textMuted),
              const SizedBox(width: 4),
              Expanded(
                child: Text(place(task.zoneName, task.location), style: TextStyle(color: c.textMuted, fontSize: 13.5)),
              ),
            ]),
            if (chips.isNotEmpty) ...[const SizedBox(height: 8), Wrap(spacing: 6, runSpacing: 6, children: chips)],
          ]),
        ),
        const SizedBox(width: 6),
        Icon(Icons.chevron_right, color: c.textDim),
      ]),
    );
  }
}

class TaskDetailScreen extends ConsumerStatefulWidget {
  const TaskDetailScreen({super.key, required this.taskId});
  final String taskId;

  @override
  ConsumerState<TaskDetailScreen> createState() => _TaskDetailScreenState();
}

class _TaskDetailScreenState extends ConsumerState<TaskDetailScreen> {
  bool _starting = false;

  Future<void> _start() async {
    setState(() => _starting = true);
    try {
      await ref.read(operationsRepositoryProvider).startTask(widget.taskId);
    } on OperationFailed catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final theme = Theme.of(context).textTheme;
    final now = ref.watch(clockProvider)();
    final tasks = ref.watch(tasksProvider).valueOrNull;
    final task = tasks?.where((t) => t.taskId == widget.taskId).firstOrNull;
    if (task == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Task detail')),
        body: tasks == null
            ? const Center(child: CircularProgressIndicator())
            : const EmptyState(icon: Icons.search_off, title: 'Task not found', body: 'It may have been reassigned by the Operator.'),
      );
    }
    final priority = switch (task.priority) {
      Severity.critical => ('High', c.danger),
      Severity.warning => ('Medium', c.warning),
      Severity.info => ('Low', c.info),
    };
    final chips = [?_scheduleChip(context, task, now), ..._eventChips(context, task)];
    return Scaffold(
      appBar: AppBar(title: const Text('Task detail')),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 28), children: [
        Container(
          height: 150,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: c.placeholder, borderRadius: BorderRadius.circular(14)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SeverityChip(task.priority, solid: task.priority == Severity.critical),
            const Spacer(),
            Row(children: [
              Icon(task.cameraCode != null ? Icons.videocam_outlined : Icons.photo_outlined, size: 16, color: c.textMuted),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  task.cameraCode != null ? 'Snapshot · ${task.cameraCode}' : 'Reported by staff',
                  style: theme.bodySmall,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ]),
          ]),
        ),
        const SizedBox(height: 16),
        Text(task.title, style: theme.titleLarge),
        const SizedBox(height: 4),
        Text('${task.origin.label} · ${task.sourceCode} · ${task.status.label}', style: theme.bodySmall),
        if (chips.isNotEmpty) ...[const SizedBox(height: 8), Wrap(spacing: 6, runSpacing: 6, children: chips)],
        if (task.eventClearedAt != null && task.isActive) ...[
          const SizedBox(height: 12),
          InfoBanner(
            tone: BannerTone.success,
            icon: Icons.check_circle_outline,
            title: 'The camera shows this area back to normal',
            body: 'The event cleared at ${hm(task.eventClearedAt!)}. Check the area quickly, then finish the task.',
          ),
        ],
        const SizedBox(height: 14),
        AppCard(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(children: [
            _Row('Location', place(task.zoneName, task.location)),
            Divider(height: 1, color: c.border),
            _Row('Raised', hm(task.createdAt)),
            Divider(height: 1, color: c.border),
            _Row('Accepted', hm(task.acceptedAt)),
            if (task.startedAt != null) ...[
              Divider(height: 1, color: c.border),
              _Row('Started', hm(task.startedAt!)),
            ],
            Divider(height: 1, color: c.border),
            _Row('Priority', task.raisedFrom == null ? priority.$1 : '${priority.$1} · raised', valueColor: priority.$2),
          ]),
        ),
        const SizedBox(height: 12),
        InfoBanner(
          tone: BannerTone.brand,
          icon: Icons.assignment_outlined,
          title: 'What to do',
          body: task.instructions.isEmpty ? 'Check the area and resolve the issue.' : task.instructions,
        ),
        const SizedBox(height: 20),
        if (task.status == TaskStatus.accepted) ...[
          FilledButton.icon(
            onPressed: _starting ? null : _start,
            icon: const Icon(Icons.play_arrow),
            label: Text(_starting ? 'Starting…' : 'Start now'),
          ),
          const SizedBox(height: 10),
        ],
        OutlinedButton(onPressed: () => context.go('/tasks'), child: const Text('Back to my tasks')),
      ]),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row(this.label, this.value, {this.valueColor});
  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 13),
      child: Row(children: [
        Text(label, style: TextStyle(color: c.textMuted, fontSize: 14)),
        const SizedBox(width: 12),
        Expanded(
          child: Text(value,
              textAlign: TextAlign.right, style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: valueColor ?? c.text)),
        ),
      ]),
    );
  }
}
