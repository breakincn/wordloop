import 'package:flutter_tts/flutter_tts.dart';

class TtsService {
  TtsService() {
    _tts = FlutterTts();
  }

  late final FlutterTts _tts;
  bool _configured = false;

  Future<void> configure() async {
    if (_configured) return;
    await _tts.setLanguage('en-US');
    await _tts.setSpeechRate(0.45);
    await _tts.setPitch(1.0);
    _configured = true;
  }

  Future<void> speak(String text) async {
    if (text.trim().isEmpty) return;
    await configure();
    await _tts.stop();
    await _tts.speak(text);
  }

  Future<void> stop() async {
    await _tts.stop();
  }

  Future<void> dispose() async {
    await _tts.stop();
  }
}
