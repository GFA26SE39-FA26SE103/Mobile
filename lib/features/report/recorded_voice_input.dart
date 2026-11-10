import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

abstract class ReportAudioRecorder {
  Future<bool> start();
  Future<String?> stop();
  Future<void> cancel();
  Future<void> dispose();
}

/// Records one bounded-duration M4A note; Backend validates its bytes and size.
class DeviceReportAudioRecorder implements ReportAudioRecorder {
  final AudioRecorder _recorder = AudioRecorder();
  bool _recording = false;

  @override
  Future<bool> start() async {
    if (!await _recorder.hasPermission()) return false;
    final directory = await getTemporaryDirectory();
    final path = '${directory.path}/staff-report-${DateTime.now().microsecondsSinceEpoch}.m4a';
    await _recorder.start(const RecordConfig(encoder: AudioEncoder.aacLc), path: path);
    _recording = true;
    return true;
  }

  @override
  Future<String?> stop() async {
    if (!_recording) return null;
    _recording = false;
    return _recorder.stop();
  }

  @override
  Future<void> cancel() async {
    if (_recording) {
      _recording = false;
      await _recorder.cancel();
    }
  }

  @override
  Future<void> dispose() => _recorder.dispose();
}

final reportAudioRecorderProvider = Provider<ReportAudioRecorder>((ref) {
  final recorder = DeviceReportAudioRecorder();
  ref.onDispose(() => unawaited(recorder.dispose()));
  return recorder;
});
