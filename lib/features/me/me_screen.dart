import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/config.dart';
import '../../core/theme/app_colors.dart';
import '../../data/providers.dart';
import '../../shared/widgets.dart';
import '../auth/auth_controller.dart';

class MeScreen extends ConsumerWidget {
  const MeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final theme = Theme.of(context).textTheme;
    final user = ref.watch(authControllerProvider).session?.user;
    final shift = ref.watch(todayShiftProvider);
    final demo = ref.watch(demoControlsProvider);
    if (user == null) return const SizedBox.shrink();

    void report(String? problem, String ok) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(problem ?? ok)));
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Me')),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 28), children: [
        AppCard(
          child: Row(children: [
            Avatar(user.initials, size: 52),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(user.fullName.isEmpty ? user.email : user.fullName, style: theme.titleMedium),
                Text(user.email, style: theme.bodySmall),
                const SizedBox(height: 6),
                Pill(label: 'STAFF', fg: c.primary, bg: c.primaryTint),
              ]),
            ),
          ]),
        ),
        const SizedBox(height: 12),
        AppCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text('Today', style: theme.titleMedium)),
              ShiftStatusPill(onShift: shift?.isCheckedIn ?? false),
            ]),
            const SizedBox(height: 6),
            Text(
              shift == null
                  ? 'No shift today.'
                  : '${[shift.zoneName, shift.storeName].where((s) => s.isNotEmpty).join(' · ')}${shift.isCheckedIn ? '' : '. Check in to receive alerts.'}',
              style: theme.bodySmall,
            ),
          ]),
        ),
        if (demo != null) ...[
          const GroupLabel('Demo tools'),
          AppCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text(
                'Shifts, tasks, alerts and swaps run on demo data inside the app (demo sign-in or DEMO_OPS). Swap buttons play the colleague and the Manager.',
                style: theme.bodySmall,
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () => report(demo.simulateEventTask(), 'Operational event raised; its task was offered to your zone.'),
                icon: const Icon(Icons.videocam_outlined),
                label: const Text('Raise an AI event task'),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () => report(demo.simulateEventTask(takenByOther: true), 'Task offered. Another staff member will accept it in a few seconds.'),
                icon: const Icon(Icons.people_outline),
                label: const Text('Offer someone else accepts first'),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () => report(demo.escalateLatestEvent(), 'The event is now CRITICAL. Its offer or task was updated.'),
                icon: const Icon(Icons.trending_up),
                label: const Text('Escalate latest event to CRITICAL'),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () => report(demo.clearLatestEvent(), 'The event cleared: the area is back to normal.'),
                icon: const Icon(Icons.check_circle_outline),
                label: const Text('Clear latest event'),
              ),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => report(demo.advanceLatestSwap(approve: true), 'The latest swap request moved one step forward.'),
                    child: const Text('Accept swap step'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => report(demo.advanceLatestSwap(approve: false), 'The latest swap request was turned down.'),
                    child: const Text('Turn down'),
                  ),
                ),
              ]),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () => report(demo.receiveSwapRequest(), 'A colleague asked to swap one of your shifts.'),
                icon: const Icon(Icons.swap_horiz),
                label: const Text('Receive a swap request'),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () {
                  demo.completeActiveTasks();
                  report(null, 'Active tasks submitted; they wait for the Operator to verify them.');
                },
                icon: const Icon(Icons.done_all),
                label: const Text('Submit my active tasks'),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () => report(demo.reviewLatestSubmission(approve: true), 'The Operator verified your latest submission.'),
                icon: const Icon(Icons.verified_outlined),
                label: const Text('Operator verifies latest submission'),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () => report(demo.reviewLatestSubmission(approve: false), 'The Operator asked for rework on your latest submission.'),
                icon: const Icon(Icons.replay),
                label: const Text('Operator rejects latest submission'),
              ),
            ]),
          ),
        ],
        const GroupLabel('Account'),
        AppCard(
          padding: EdgeInsets.zero,
          child: Column(children: [
            ListTile(
              leading: Icon(Icons.dns_outlined, color: c.textMuted),
              title: const Text('Server'),
              subtitle: Text(AppConfig.mockAuth
                  ? 'Demo sign-in (no server)'
                  : '${AppConfig.apiUrl}${AppConfig.demoOperations ? ' · shifts and tasks on demo data' : ''}'),
            ),
            Divider(height: 1, color: c.border),
            ListTile(
              leading: Icon(Icons.logout, color: c.danger),
              title: Text('Sign out', style: TextStyle(color: c.danger, fontWeight: FontWeight.w600)),
              onTap: () async {
                await ref.read(authControllerProvider.notifier).signOut();
                if (context.mounted) context.go('/sign-in');
              },
            ),
          ]),
        ),
      ]),
    );
  }
}
