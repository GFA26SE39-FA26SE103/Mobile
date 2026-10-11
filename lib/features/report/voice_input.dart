import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

/// Dictation for staff reports. Speech is turned into text on the device and only the
/// text is kept; how voice recordings would be stored and retained is still an open
/// decision (PROJECT_CONTEXT 1.0, open refinements).
abstract class VoiceInput {
  /// Starts listening; [onText] receives the words heard so far. Returns false when
  /// speech recognition is unavailable or the microphone permission was refused.
  Future<bool> start(void Function(String words, bool isFinal) onText, {void Function()? onDone});
  Future<void> stop();
}

class DeviceVoiceInput implements VoiceInput {
  final _speech = SpeechToText();
  bool _ready = false;
  void Function()? _onDone;

  @override
  Future<bool> start(void Function(String words, bool isFinal) onText, {void Function()? onDone}) async {
    _onDone = onDone;
    if (!_ready) {
      _ready = await _speech.initialize(
        onStatus: (status) {
          if (status == SpeechToText.doneStatus || status == SpeechToText.notListeningStatus) _onDone?.call();
        },
        onError: (_) => _onDone?.call(),
      );
    }
    if (!_ready) return false;
    // Prefer Vietnamese when the device has it; otherwise fall back to the system locale.
    final locales = await _speech.locales();
    final vi = locales.where((l) => l.localeId.toLowerCase().startsWith('vi')).firstOrNull;
    await _speech.listen(
      onResult: (SpeechRecognitionResult r) => onText(r.recognizedWords, r.finalResult),
      listenOptions: SpeechListenOptions(
        localeId: vi?.localeId,
        partialResults: true,
        listenFor: const Duration(seconds: 60),
        pauseFor: const Duration(seconds: 4),
        cancelOnError: true,
      ),
    );
    return true;
  }

  @override
  Future<void> stop() => _speech.stop();
}

final voiceInputProvider = Provider<VoiceInput>((ref) => DeviceVoiceInput());
