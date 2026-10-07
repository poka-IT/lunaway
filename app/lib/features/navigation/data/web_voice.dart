import 'package:lunaway/features/navigation/data/voice_output.dart';

/// The browser's speech synthesis; only the web build has one (see
/// `web_voice_web.dart`).
VoiceOutput browserVoice() => const SilentVoice();
