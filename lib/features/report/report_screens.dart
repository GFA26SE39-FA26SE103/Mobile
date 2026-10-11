import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/theme/app_colors.dart';
import '../../data/models.dart';
import '../../data/providers.dart';
import '../../shared/format.dart';
import '../../shared/widgets.dart';
import 'voice_input.dart';

/// The draft being confirmed; lives outside the routes so it survives navigation.
final reportDraftProvider = StateProvider<ReportDraft?>((ref) => null);
final reportReceiptProvider = StateProvider<ReportReceipt?>((ref) => null);

/// Lets tests and other hosts replace the camera/gallery picker.
final imagePickerProvider = Provider<Future<String?> Function(ImageSource source)>((ref) {
  final picker = ImagePicker();
  return (source) async => (await picker.pickImage(source: source, maxWidth: 1600, imageQuality: 82))?.path;
});

const _maxNote = 500;
const _maxPhotos = 3;

class ReportDescribeScreen extends ConsumerStatefulWidget {
  const ReportDescribeScreen({super.key});

  @override
  ConsumerState<ReportDescribeScreen> createState() => _ReportDescribeScreenState();
}

class _ReportDescribeScreenState extends ConsumerState<ReportDescribeScreen> {
  final _note = TextEditingController();
  final _photos = <String>[];
  bool _extracting = false;
  bool _listening = false;
  bool _usedVoice = false;
  String _beforeVoice = '';
  String? _error;

  @override
  void initState() {
    super.initState();
    _note.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    if (_listening) ref.read(voiceInputProvider).stop();
    _note.dispose();
    super.dispose();
  }

  bool get _ready => _note.text.trim().length >= 5 || _photos.isNotEmpty;

  Future<void> _addPhoto(ImageSource source) async {
    try {
      final path = await ref.read(imagePickerProvider)(source);
      if (path != null && mounted) setState(() => _photos.add(path));
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not open the ${source == ImageSource.camera ? 'camera' : 'photo library'}. Check app permissions.');
    }
  }

  Future<void> _toggleVoice() async {
    final voice = ref.read(voiceInputProvider);
    if (_listening) {
      await voice.stop();
      if (mounted) setState(() => _listening = false);
      return;
    }
    _beforeVoice = _note.text.trim();
    setState(() {
      _error = null;
      _listening = true;
    });
    final started = await voice.start(
      (words, isFinal) {
        if (!mounted) return;
        final text = [_beforeVoice, words.trim()].where((s) => s.isNotEmpty).join(' ');
        _note.value = TextEditingValue(
          text: text.length > _maxNote ? text.substring(0, _maxNote) : text,
          selection: TextSelection.collapsed(offset: text.length > _maxNote ? _maxNote : text.length),
        );
        if (words.trim().isNotEmpty) _usedVoice = true;
      },
      onDone: () {
        if (mounted) setState(() => _listening = false);
      },
    );
    if (!started && mounted) {
      setState(() {
        _listening = false;
        _error = 'Voice input is not available. Allow microphone access, or type the report instead.';
      });
    }
  }

  Future<void> _extract() async {
    if (_listening) await _toggleVoice();
    setState(() {
      _extracting = true;
      _error = null;
    });
    try {
      final draft = await ref.read(operationsRepositoryProvider).extractReport(_note.text, List.of(_photos), fromVoice: _usedVoice);
      ref.read(reportDraftProvider.notifier).state = draft;
      if (mounted) context.go('/report/review');
    } catch (_) {
      if (mounted) setState(() => _error = 'AI could not read the report. Try again, or fill it in yourself on the next screen.');
    } finally {
      if (mounted) setState(() => _extracting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final theme = Theme.of(context).textTheme;
    final shift = ref.watch(todayShiftProvider);
    final onShift = shift?.isCheckedIn ?? false;
    // The tab stays alive between reports; start fresh once a report has been sent.
    ref.listen(reportReceiptProvider, (previous, next) {
      if (next != null && next != previous) {
        _note.clear();
        _usedVoice = false;
        setState(_photos.clear);
      }
    });
    return Scaffold(
      appBar: AppBar(title: const Text('Report an issue')),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 18, 16, 16), children: [
        Text('What happened?', style: theme.titleLarge),
        const SizedBox(height: 4),
        Text('Type, speak or add a photo. AI fills in the report and you check it before anything is sent.', style: theme.bodySmall),
        const SizedBox(height: 14),
        TextField(
          controller: _note,
          minLines: 4,
          maxLines: 7,
          maxLength: _maxNote,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(hintText: 'E.g. A bottle broke at the end of aisle 4, the floor is wet and slippery.'),
        ),
        const SizedBox(height: 4),
        Wrap(spacing: 10, runSpacing: 10, children: [
          _AddTile(
            icon: _listening ? Icons.stop_circle_outlined : Icons.mic_none,
            label: _listening ? 'Listening… tap to stop' : 'Speak',
            active: _listening,
            onTap: _toggleVoice,
          ),
          for (var i = 0; i < _photos.length; i++) _PhotoThumb(path: _photos[i], onRemove: () => setState(() => _photos.removeAt(i))),
          if (_photos.length < _maxPhotos) ...[
            _AddTile(icon: Icons.photo_camera_outlined, label: 'Take photo', onTap: () => _addPhoto(ImageSource.camera)),
            _AddTile(icon: Icons.photo_library_outlined, label: 'From gallery', onTap: () => _addPhoto(ImageSource.gallery)),
          ],
        ]),
        const SizedBox(height: 14),
        if (onShift)
          FactLine(icon: Icons.place_outlined, text: 'You are on shift in ${shift!.zoneName}', strong: true)
        else
          const InfoBanner(
            tone: BannerTone.warning,
            icon: Icons.place_outlined,
            title: 'You are not checked in',
            body: 'You can still report. Add the location yourself on the next screen.',
          ),
        if (_error != null) ...[
          const SizedBox(height: 12),
          InfoBanner(tone: BannerTone.danger, icon: Icons.error_outline, title: _error!),
        ],
        const SizedBox(height: 22),
        FilledButton.icon(
          onPressed: _ready && !_extracting ? _extract : null,
          icon: _extracting
              ? SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: c.textDim))
              : const Icon(Icons.auto_awesome),
          label: Text(_extracting ? 'Reading your report…' : 'Let AI fill the report'),
        ),
        const SizedBox(height: 10),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(Icons.lock_outline, size: 14, color: c.textDim),
          const SizedBox(width: 4),
          Flexible(child: Text('Nothing is sent until you confirm', style: theme.bodySmall?.copyWith(color: c.textDim))),
        ]),
      ]),
    );
  }
}

class _PhotoThumb extends StatelessWidget {
  const _PhotoThumb({required this.path, required this.onRemove});
  final String path;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Stack(clipBehavior: Clip.none, children: [
      ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: SizedBox(
          width: 84,
          height: 84,
          child: Image.file(File(path), fit: BoxFit.cover, errorBuilder: (_, _, _) => ColoredBox(color: c.placeholder, child: Icon(Icons.image_outlined, color: c.textMuted))),
        ),
      ),
      Positioned(
        top: -8,
        right: -8,
        child: Material(
          color: c.text,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onRemove,
            child: Padding(padding: const EdgeInsets.all(6), child: Icon(Icons.close, size: 14, color: c.bg, semanticLabel: 'Remove photo')),
          ),
        ),
      ),
    ]);
  }
}

class _AddTile extends StatelessWidget {
  const _AddTile({required this.icon, required this.label, required this.onTap, this.active = false});
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final fg = active ? c.danger : c.textMuted;
    return Material(
      color: active ? c.dangerTint : c.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: active ? c.danger : c.border)),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: SizedBox(
          width: 84,
          height: 84,
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(icon, color: fg),
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text(label, textAlign: TextAlign.center, style: TextStyle(fontSize: 11.5, color: fg)),
            ),
          ]),
        ),
      ),
    );
  }
}

class ReportReviewScreen extends ConsumerStatefulWidget {
  const ReportReviewScreen({super.key});

  @override
  ConsumerState<ReportReviewScreen> createState() => _ReportReviewScreenState();
}

class _ReportReviewScreenState extends ConsumerState<ReportReviewScreen> {
  bool _sending = false;
  String? _error;

  void _update(ReportDraft next) => ref.read(reportDraftProvider.notifier).state = next;

  Future<void> _editText(ReportDraft draft, ReportField field, String label, String current, {int maxLines = 1}) async {
    final value = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _EditTextSheet(label: label, initial: current, maxLines: maxLines),
    );
    if (value != null && value != current) _update(draft.edit(field, text: value));
  }

  Future<void> _pickType(ReportDraft draft) async {
    final value = await showModalBottomSheet<String>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      builder: (context) => ListView(shrinkWrap: true, padding: const EdgeInsets.only(bottom: 16), children: [
        for (final kind in ReportKind.values) ...[
          Padding(padding: const EdgeInsets.fromLTRB(20, 8, 20, 4), child: GroupLabel(kind.label)),
          for (final cat in reportCategories.where((c) => c.kind == kind))
            ListTile(
              title: Text(cat.name),
              trailing: cat.name == draft.type ? Icon(Icons.check, color: context.colors.primary) : null,
              onTap: () => Navigator.of(context).pop(cat.name),
            ),
        ],
      ]),
    );
    if (value != null && value != draft.type) _update(draft.edit(ReportField.type, text: value));
  }

  Future<void> _send(ReportDraft draft) async {
    final problem = draft.validate();
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      final receipt = await ref.read(operationsRepositoryProvider).submitReport(draft);
      ref.read(reportReceiptProvider.notifier).state = receipt;
      ref.read(reportDraftProvider.notifier).state = null;
      if (mounted) context.go('/report/submitted');
    } catch (_) {
      if (mounted) setState(() => _error = 'The report was not sent. Check your connection and try again; your edits are kept.');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final draft = ref.watch(reportDraftProvider);
    if (draft == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Review report')),
        body: EmptyState(
          icon: Icons.edit_note,
          title: 'No report in progress',
          body: 'Start by describing what happened.',
          action: OutlinedButton(onPressed: () => context.go('/report'), child: const Text('Report an issue')),
        ),
      );
    }
    final c = context.colors;
    final theme = Theme.of(context).textTheme;
    final shift = ref.watch(todayShiftProvider);
    final zone = shift != null && shift.isCheckedIn ? shift.zoneName : 'the zone';
    final source = [if (draft.fromVoice) 'voice note' else if (draft.note.isNotEmpty) 'note', if (draft.photoPaths.isNotEmpty) 'photo'];
    return Scaffold(
      appBar: AppBar(
        title: const Text('Review report'),
        leading: BackButton(onPressed: () => context.go('/report')),
      ),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 16), children: [
        if (draft.aiFields.isNotEmpty)
          InfoBanner(
            tone: BannerTone.brand,
            icon: Icons.auto_awesome,
            title: 'AI filled ${draft.aiFields.length} field${draft.aiFields.length == 1 ? '' : 's'}',
            body: 'From your ${source.join(' and ')}. Tap any field to change it.',
          )
        else
          const InfoBanner(
            tone: BannerTone.warning,
            icon: Icons.edit_outlined,
            title: 'Fill in the report',
            body: 'AI could not read enough from a photo alone. Add a title and location.',
          ),
        GroupLabel('Report as', trailing: draft.aiFields.contains(ReportField.kind) ? Pill(label: 'AI', fg: c.primary, bg: c.primaryTint) : null),
        Row(children: [
          for (final kind in ReportKind.values) ...[
            Expanded(
              child: _KindCard(
                kind: kind,
                selected: draft.kind == kind,
                onTap: () => _update(draft.edit(ReportField.kind, kind: kind)),
              ),
            ),
            if (kind != ReportKind.values.last) const SizedBox(width: 10),
          ],
        ]),
        const SizedBox(height: 12),
        AppCard(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(children: [
            _Field(label: 'Category', value: draft.type, ai: draft.aiFields.contains(ReportField.type), onTap: () => _pickType(draft)),
            Divider(height: 1, color: c.border),
            _Field(
              label: 'Location',
              value: draft.location,
              ai: draft.aiFields.contains(ReportField.location),
              onTap: () => _editText(draft, ReportField.location, 'Where is it?', draft.location),
            ),
            Divider(height: 1, color: c.border),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                _FieldLabel('Severity', ai: draft.aiFields.contains(ReportField.severity)),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: SegmentedButton<ReportSeverity>(
                    showSelectedIcon: false,
                    segments: [for (final s in ReportSeverity.values) ButtonSegment(value: s, label: Text(s.label))],
                    selected: {draft.severity},
                    style: ButtonStyle(
                      backgroundColor: WidgetStateProperty.resolveWith((states) => states.contains(WidgetState.selected)
                          ? severityColors(context, draft.severity.severity).fg
                          : c.surface2),
                      foregroundColor: WidgetStateProperty.resolveWith(
                          (states) => states.contains(WidgetState.selected) ? c.onPrimary : c.textMuted),
                      side: WidgetStatePropertyAll(BorderSide(color: c.border)),
                    ),
                    onSelectionChanged: (s) => _update(draft.edit(ReportField.severity, severity: s.first)),
                  ),
                ),
              ]),
            ),
            Divider(height: 1, color: c.border),
            _Field(
              label: 'Title',
              value: draft.title,
              ai: draft.aiFields.contains(ReportField.title),
              onTap: () => _editText(draft, ReportField.title, 'Short title', draft.title),
            ),
            Divider(height: 1, color: c.border),
            _Field(
              label: 'Suggested action',
              value: draft.suggestedAction,
              ai: draft.aiFields.contains(ReportField.suggestedAction),
              onTap: () => _editText(draft, ReportField.suggestedAction, 'What should staff do?', draft.suggestedAction, maxLines: 4),
            ),
          ]),
        ),
        if (draft.note.isNotEmpty) ...[
          GroupLabel(draft.fromVoice ? 'What you said' : 'Your note'),
          Text(draft.note, style: theme.bodyMedium?.copyWith(color: c.textMuted)),
        ],
        const SizedBox(height: 14),
        FactLine(
          icon: draft.kind == ReportKind.routineRequest ? Icons.groups_outlined : Icons.health_and_safety_outlined,
          text: draft.kind == ReportKind.routineRequest
              ? 'A task is offered to staff on shift in $zone. No incident is opened.'
              : 'Checked against the incident rules. If it qualifies, an incident opens and a corrective task goes to $zone right away.',
        ),
        if (_error != null) ...[
          const SizedBox(height: 12),
          InfoBanner(tone: BannerTone.danger, icon: Icons.error_outline, title: _error!),
        ],
        const SizedBox(height: 18),
        FilledButton.icon(
          onPressed: _sending ? null : () => _send(draft),
          icon: _sending
              ? SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: c.textDim))
              : const Icon(Icons.send_outlined),
          label: Text(_sending ? 'Sending…' : 'Confirm and send'),
        ),
      ]),
    );
  }
}

class _KindCard extends StatelessWidget {
  const _KindCard({required this.kind, required this.selected, required this.onTap});
  final ReportKind kind;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final accent = kind == ReportKind.potentialIncident ? c.danger : c.primary;
    return Semantics(
      selected: selected,
      button: true,
      child: AppCard(
        onTap: onTap,
        color: selected ? (kind == ReportKind.potentialIncident ? c.dangerTint : c.primaryTint) : c.surface,
        borderColor: selected ? accent : null,
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(kind == ReportKind.potentialIncident ? Icons.warning_amber_rounded : Icons.handyman_outlined, size: 18, color: accent),
            const SizedBox(width: 6),
            Expanded(child: Text(kind.label, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5, color: selected ? accent : c.text))),
          ]),
          const SizedBox(height: 4),
          Text(kind.hint, style: Theme.of(context).textTheme.bodySmall),
        ]),
      ),
    );
  }
}

/// Owns its controller so it outlives the sheet's closing animation.
class _EditTextSheet extends StatefulWidget {
  const _EditTextSheet({required this.label, required this.initial, required this.maxLines});
  final String label;
  final String initial;
  final int maxLines;

  @override
  State<_EditTextSheet> createState() => _EditTextSheetState();
}

class _EditTextSheetState extends State<_EditTextSheet> {
  late final _controller = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(widget.label, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 12),
        TextField(
          controller: _controller,
          autofocus: true,
          minLines: 1,
          maxLines: widget.maxLines,
          maxLength: widget.maxLines > 1 ? 200 : 80,
          textCapitalization: TextCapitalization.sentences,
        ),
        const SizedBox(height: 8),
        FilledButton(onPressed: () => Navigator.of(context).pop(_controller.text.trim()), child: const Text('Save')),
      ]),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.label, {required this.ai});
  final String label;
  final bool ai;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Row(children: [
      Text(label, style: TextStyle(color: c.textMuted, fontSize: 13)),
      if (ai) ...[
        const SizedBox(width: 8),
        Pill(label: 'AI', fg: c.primary, bg: c.primaryTint),
      ],
    ]);
  }
}

class _Field extends StatelessWidget {
  const _Field({required this.label, required this.value, required this.ai, required this.onTap});
  final String label;
  final String value;
  final bool ai;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              _FieldLabel(label, ai: ai),
              const SizedBox(height: 4),
              Text(
                value.isEmpty ? 'Tap to add' : value,
                style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w600, color: value.isEmpty ? c.danger : c.text),
              ),
            ]),
          ),
          Icon(Icons.edit_outlined, size: 18, color: c.textDim, semanticLabel: 'Edit $label'),
        ]),
      ),
    );
  }
}

class ReportSubmittedScreen extends ConsumerWidget {
  const ReportSubmittedScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final receipt = ref.watch(reportReceiptProvider);
    final c = context.colors;
    final theme = Theme.of(context).textTheme;
    if (receipt == null) {
      return Scaffold(appBar: AppBar(title: const Text('Report submitted')), body: const SizedBox.shrink());
    }
    final (headline, detail, chip) = switch (receipt.outcome) {
      ReportOutcome.routineTask => (
          'Request sent',
          'A task was offered to ${receipt.offeredTo} staff on shift in ${receipt.zoneName}.',
          'ROUTINE REQUEST',
        ),
      ReportOutcome.incidentQualified => (
          'Incident ${receipt.incidentCode} opened',
          'A corrective task was offered to ${receipt.offeredTo} staff in ${receipt.zoneName}. No Operator review is needed first.',
          'INCIDENT',
        ),
      ReportOutcome.awaitingQualification => (
          'Report recorded',
          'It did not meet the incident rules on its own. The Operator can still open an incident or create a task.',
          'POTENTIAL INCIDENT',
        ),
    };
    final incident = receipt.outcome == ReportOutcome.incidentQualified;
    return Scaffold(
      appBar: AppBar(title: const Text('Report submitted'), automaticallyImplyLeading: false),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 28), children: [
        AppCard(
          color: incident ? c.dangerTint : c.successTint,
          borderColor: incident ? c.dangerTint : c.successTint,
          padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
          child: Column(children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(color: incident ? c.danger : c.success, shape: BoxShape.circle),
              child: Icon(incident ? Icons.priority_high : Icons.check, color: c.onPrimary, size: 30),
            ),
            const SizedBox(height: 12),
            Text(headline, textAlign: TextAlign.center, style: theme.titleLarge?.copyWith(color: incident ? c.danger : c.success)),
            const SizedBox(height: 4),
            Text(detail, textAlign: TextAlign.center),
          ]),
        ),
        const SizedBox(height: 12),
        AppCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text(receipt.title, style: theme.titleMedium)),
              Pill(label: chip, fg: incident ? c.danger : c.primary, bg: incident ? c.dangerTint : c.primaryTint),
            ]),
            const SizedBox(height: 4),
            Text('${receipt.location} · ${receipt.reportCode}', style: theme.bodySmall),
            Divider(height: 24, color: c.border),
            Row(children: [
              Expanded(child: _Meta('Sent', 'Today · ${hm(receipt.submittedAt)}')),
              Expanded(child: _Meta('AI draft', receipt.edited ? 'Checked and edited' : 'Checked, no changes')),
            ]),
          ]),
        ),
        if (receipt.offeredTo > 0) ...[
          const SizedBox(height: 12),
          Text('The first staff member to accept gets the task. You will see it in Alerts when someone takes it.', style: theme.bodySmall),
        ],
        const SizedBox(height: 22),
        FilledButton(onPressed: () => context.go('/tasks'), child: const Text('Back to my tasks')),
        const SizedBox(height: 10),
        OutlinedButton(onPressed: () => context.go('/report'), child: const Text('Report another issue')),
      ]),
    );
  }
}

class _Meta extends StatelessWidget {
  const _Meta(this.label, this.value);
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label.toUpperCase(), style: Theme.of(context).textTheme.labelSmall),
        const SizedBox(height: 4),
        Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
      ]);
}
