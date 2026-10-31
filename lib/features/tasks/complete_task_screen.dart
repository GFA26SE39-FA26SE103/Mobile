import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/theme/app_colors.dart';
import '../../data/models.dart';
import '../../data/providers.dart';
import '../../shared/format.dart';
import '../../shared/widgets.dart';
import '../report/report_screens.dart' show imagePickerProvider;

const _maxNote = 2000;

/// One photo slot while it is being filled: the picked file, and how its upload went.
class _Slot {
  String? localPath;
  bool uploading = false;
  String? error;
}

/// Report 3 §3.9.4–3.9.5 (Figures 20, 34, 35): completion note and photo evidence, then submit for Operator verification.
class CompleteTaskScreen extends ConsumerStatefulWidget {
  const CompleteTaskScreen({super.key, required this.taskId});
  final String taskId;

  @override
  ConsumerState<CompleteTaskScreen> createState() => _CompleteTaskScreenState();
}

class _CompleteTaskScreenState extends ConsumerState<CompleteTaskScreen> {
  final _note = TextEditingController();
  final _slots = {for (final k in EvidenceKind.values) k: _Slot()};
  TaskEvidenceState? _evidence;
  String? _loadError;
  String? _error;
  bool _submitting = false;
  bool _submitted = false;

  @override
  void initState() {
    super.initState();
    _note.addListener(() => setState(() {}));
    _load();
  }

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loadError = null);
    try {
      final evidence = await ref.read(operationsRepositoryProvider).taskEvidence(widget.taskId);
      if (mounted) setState(() => _evidence = evidence);
    } on OperationFailed catch (e) {
      if (mounted) setState(() => _loadError = e.message);
    }
  }

  bool get _uploading => _slots.values.any((s) => s.uploading);

  bool get _ready {
    final e = _evidence;
    if (e == null || _note.text.trim().isEmpty || _uploading || _submitting) return false;
    return EvidenceKind.values.every((k) => !e.requires(k) || e.draft(k) != null);
  }

  Future<void> _pick(EvidenceKind kind, ImageSource source) async {
    String? path;
    try {
      path = await ref.read(imagePickerProvider)(source);
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not open the ${source == ImageSource.camera ? 'camera' : 'photo library'}. Check app permissions.');
      return;
    }
    if (path == null || !mounted) return;
    _slots[kind]!.localPath = path;
    await _upload(kind);
  }

  /// Uploads the slot's file. A retry sends the same file again; the server replaces the draft, so nothing is duplicated.
  Future<void> _upload(EvidenceKind kind) async {
    final slot = _slots[kind]!;
    final path = slot.localPath;
    if (path == null) return;
    setState(() {
      slot.uploading = true;
      slot.error = null;
      _error = null;
    });
    try {
      final evidence = await ref.read(operationsRepositoryProvider).uploadEvidence(widget.taskId, kind, path);
      if (mounted) setState(() => _evidence = evidence);
    } on OperationFailed catch (e) {
      if (mounted) setState(() => slot.error = e.message);
    } catch (_) {
      if (mounted) setState(() => slot.error = 'Upload failed. Check your connection and retry.');
    } finally {
      if (mounted) setState(() => slot.uploading = false);
    }
  }

  Future<void> _remove(EvidenceKind kind) async {
    final slot = _slots[kind]!;
    final draft = _evidence?.draft(kind);
    setState(() {
      slot.localPath = null;
      slot.error = null;
    });
    if (draft == null) return;
    try {
      final evidence = await ref.read(operationsRepositoryProvider).removeEvidence(widget.taskId, draft.evidenceId);
      if (mounted) setState(() => _evidence = evidence);
    } on OperationFailed catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  Future<void> _submit() async {
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await ref.read(operationsRepositoryProvider).submitTask(widget.taskId, _note.text);
      if (mounted) setState(() => _submitted = true);
    } on OperationFailed catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    final task = ref.watch(tasksProvider).valueOrNull?.where((t) => t.taskId == widget.taskId).firstOrNull;
    if (_submitted) return _SubmittedView(title: task?.title ?? 'Task');

    final evidence = _evidence;
    return Scaffold(
      appBar: AppBar(title: const Text('Complete task')),
      body: evidence == null
          ? (_loadError == null
              ? const Center(child: CircularProgressIndicator())
              : EmptyState(
                  icon: Icons.cloud_off,
                  title: 'Could not load this task',
                  body: _loadError!,
                  action: OutlinedButton(onPressed: _load, child: const Text('Retry')),
                ))
          : ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 28), children: [
              if (task != null) ...[
                Text(task.title, style: theme.titleLarge),
                const SizedBox(height: 4),
                Text(place(task.zoneName, task.location), style: theme.bodySmall),
                const SizedBox(height: 14),
              ],
              if (evidence.inRework) ...[
                InfoBanner(
                  tone: BannerTone.danger,
                  icon: Icons.replay,
                  title: 'Rework needed',
                  body: evidence.latest!.rejectReason ?? 'The Operator returned this task.',
                ),
                const SizedBox(height: 12),
              ],
              InfoBanner(
                tone: BannerTone.brand,
                icon: Icons.fact_check_outlined,
                title: evidence.requiresAfter ? 'Photo evidence is required' : 'Add a completion note',
                body: evidence.requiresAfter
                    ? 'Take an after photo when the work is done${evidence.requiresBefore ? ', and a before photo of the problem' : ''}. The Operator checks them before the task is verified.'
                    : 'Say what you did. Photos are optional but help the Operator verify the work.',
              ),
              const SizedBox(height: 16),
              for (final kind in EvidenceKind.values) ...[
                _PhotoSlot(
                  kind: kind,
                  required: evidence.requires(kind),
                  slot: _slots[kind]!,
                  uploaded: evidence.draft(kind),
                  onPick: (source) => _pick(kind, source),
                  onRetry: () => _upload(kind),
                  onRemove: () => _remove(kind),
                ),
                const SizedBox(height: 12),
              ],
              TextField(
                controller: _note,
                maxLength: _maxNote,
                minLines: 3,
                maxLines: 6,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Completion note',
                  hintText: 'What did you do? For example: opened counter 4, the queue is cleared.',
                  alignLabelWithHint: true,
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                InfoBanner(tone: BannerTone.danger, icon: Icons.error_outline, title: _error!),
              ],
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _ready ? _submit : null,
                icon: _submitting
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.send),
                label: Text(_submitting ? 'Submitting…' : 'Submit for verification'),
              ),
              const SizedBox(height: 6),
              Text(
                _uploading ? 'Waiting for the photo upload to finish.' : 'The task stays in progress until the Operator verifies it.',
                textAlign: TextAlign.center,
                style: theme.bodySmall,
              ),
            ]),
    );
  }
}

class _PhotoSlot extends StatelessWidget {
  const _PhotoSlot({
    required this.kind,
    required this.required,
    required this.slot,
    required this.uploaded,
    required this.onPick,
    required this.onRetry,
    required this.onRemove,
  });
  final EvidenceKind kind;
  final bool required;
  final _Slot slot;
  final EvidencePhoto? uploaded;
  final ValueChanged<ImageSource> onPick;
  final VoidCallback onRetry;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final theme = Theme.of(context).textTheme;
    final hasPhoto = slot.localPath != null || uploaded != null;
    return AppCard(
      padding: const EdgeInsets.all(12),
      borderColor: slot.error != null ? c.danger : null,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Text('${kind.label} photo', style: const TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(width: 8),
          Pill(
            label: required ? 'Required' : 'Optional',
            fg: required ? c.danger : c.textMuted,
            bg: required ? c.dangerTint : c.surface2,
          ),
          const Spacer(),
          if (uploaded != null && !slot.uploading) Icon(Icons.cloud_done_outlined, size: 18, color: c.success),
        ]),
        const SizedBox(height: 10),
        if (hasPhoto)
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: SizedBox(
              height: 170,
              child: Stack(fit: StackFit.expand, children: [
                slot.localPath != null
                    ? Image.file(File(slot.localPath!), fit: BoxFit.cover, errorBuilder: (_, _, _) => Container(color: c.placeholder))
                    : EvidenceImage(url: uploaded!.imageUrl),
                if (slot.uploading)
                  Container(
                    color: Colors.black.withValues(alpha: 0.35),
                    alignment: Alignment.center,
                    child: const Column(mainAxisSize: MainAxisSize.min, children: [
                      CircularProgressIndicator(color: Colors.white),
                      SizedBox(height: 8),
                      Text('Uploading…', style: TextStyle(color: Colors.white)),
                    ]),
                  ),
              ]),
            ),
          )
        else
          Container(
            height: 96,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: c.placeholder, borderRadius: BorderRadius.circular(10)),
            child: Text(kind == EvidenceKind.before ? 'The problem as you found it' : 'The area after your work', style: theme.bodySmall),
          ),
        if (slot.error != null) ...[
          const SizedBox(height: 8),
          InfoBanner(
            tone: BannerTone.danger,
            icon: Icons.cloud_off,
            title: 'Upload failed',
            body: slot.error!,
            action: TextButton(onPressed: onRetry, child: const Text('Retry upload')),
          ),
        ],
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 4, children: [
          OutlinedButton.icon(
            onPressed: slot.uploading ? null : () => onPick(ImageSource.camera),
            icon: const Icon(Icons.photo_camera_outlined, size: 18),
            label: Text(hasPhoto ? 'Retake' : 'Take photo'),
          ),
          OutlinedButton.icon(
            onPressed: slot.uploading ? null : () => onPick(ImageSource.gallery),
            icon: const Icon(Icons.photo_library_outlined, size: 18),
            label: const Text('Choose'),
          ),
          if (hasPhoto)
            TextButton.icon(
              onPressed: slot.uploading ? null : onRemove,
              style: TextButton.styleFrom(foregroundColor: c.danger),
              icon: const Icon(Icons.delete_outline, size: 18),
              label: const Text('Remove'),
            ),
        ]),
      ]),
    );
  }
}

/// A stored evidence photo, loaded with the signed-in session.
class EvidenceImage extends ConsumerWidget {
  const EvidenceImage({super.key, required this.url, this.fit = BoxFit.cover});
  final String url;
  final BoxFit fit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    return ref.watch(evidenceImageProvider(url)).when(
          data: (bytes) => Image.memory(Uint8List.fromList(bytes), fit: fit, gaplessPlayback: true,
              errorBuilder: (_, _, _) => Container(color: c.placeholder, alignment: Alignment.center, child: Icon(Icons.broken_image_outlined, color: c.textDim))),
          loading: () => Container(color: c.placeholder, alignment: Alignment.center, child: const CircularProgressIndicator(strokeWidth: 2)),
          error: (_, _) => Container(color: c.placeholder, alignment: Alignment.center, child: Icon(Icons.broken_image_outlined, color: c.textDim)),
        );
  }
}

/// Figure 35: the submission went through and waits for the Operator.
class _SubmittedView extends StatelessWidget {
  const _SubmittedView({required this.title});
  final String title;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final theme = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Submitted'), automaticallyImplyLeading: false),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Icon(Icons.hourglass_top, size: 56, color: c.info),
          const SizedBox(height: 16),
          Text('Waiting for verification', textAlign: TextAlign.center, style: theme.titleLarge),
          const SizedBox(height: 8),
          Text(
            '"$title" was submitted. The Operator reviews your note and photos; you get a notification when it is verified or needs rework.',
            textAlign: TextAlign.center,
            style: theme.bodyMedium,
          ),
          const SizedBox(height: 24),
          FilledButton(onPressed: () => context.go('/tasks'), child: const Text('Back to my tasks')),
        ]),
      ),
    );
  }
}
