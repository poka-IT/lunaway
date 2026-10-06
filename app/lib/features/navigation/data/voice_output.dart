import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:logging/logging.dart';
import 'package:lunaway/features/navigation/domain/route_settings.dart';
import 'package:lunaway_nav/lunaway_nav.dart' as nav;
import 'package:wakelock_plus/wakelock_plus.dart';

final _log = Logger('voice');

/// Whether the device can say the instructions of a language.
enum VoiceReadiness {
  /// A voice is installed.
  ready,

  /// The engine speaks it once its voice data is downloaded.
  missingData,

  /// No voice for it, or no speech engine.
  none,
}

/// The spoken instructions.
abstract interface class VoiceOutput {
  /// Picks the voice for [language] and tells whether one is ready.
  Future<VoiceReadiness> prepare(RouteLanguage language);

  /// Says [text]: at once, cutting what was being said, unless [queue],
  /// which waits for it (a warning after a maneuver).
  Future<void> say(String text, {bool queue = false});

  Future<void> stop();

  /// Opens the system's page that installs voices; false where there is
  /// none.
  Future<bool> installVoices();
}

/// [VoiceOutput] through the platform's speech engine (lunaway_nav).
final class PlatformVoiceOutput implements VoiceOutput {
  new({this._voice = const nav.PlatformVoice()});

  final nav.PlatformVoice _voice;
  String _tag = RouteLanguage.fr.speechTag;
  String? _voiceId;

  @override
  Future<VoiceReadiness> prepare(RouteLanguage language) async {
    try {
      final code = language.name;
      final voices = await _voice.voices(code);
      final best = pickVoice(voices, preferred: language.speechTag);
      _tag = best?.locale ?? language.speechTag;
      _voiceId = best?.id;
      if (best != null) return VoiceReadiness.ready;
      return switch (await _voice.languageStatus(language.speechTag)) {
        nav.PlatformLanguageStatus.available => VoiceReadiness.ready,
        nav.PlatformLanguageStatus.missingData => VoiceReadiness.missingData,
        nav.PlatformLanguageStatus.notSupported => VoiceReadiness.none,
      };
    } on PlatformException catch (e) {
      _log.info('no speech engine: ${e.message}');
      return VoiceReadiness.none;
    } on MissingPluginException {
      return VoiceReadiness.none;
    }
  }

  @override
  Future<void> say(String text, {bool queue = false}) async {
    try {
      await _voice.speak(text, language: _tag, voiceId: _voiceId, queue: queue);
    } on PlatformException catch (e) {
      _log.info('speech failed: ${e.message}');
    }
  }

  @override
  Future<void> stop() async {
    try {
      await _voice.stop();
    } on PlatformException catch (e) {
      _log.info('speech stop failed: ${e.message}');
    }
  }

  @override
  Future<bool> installVoices() async {
    try {
      return await _voice.installVoiceData();
    } on PlatformException {
      return false;
    }
  }
}

/// The voice to speak with among [voices]: installed ones only; one that
/// needs no network first (it works in a valley without signal and keeps
/// the instructions on the device); the exact [preferred] tag first (fr-FR
/// before fr-CA); then the best quality.
@visibleForTesting
nav.PlatformVoiceInfo? pickVoice(List<nav.PlatformVoiceInfo> voices, {required String preferred}) {
  final usable = [
    for (final v in voices)
      if (!v.notInstalled) v,
  ];
  if (usable.isEmpty) return null;
  int score(nav.PlatformVoiceInfo v) =>
      (v.networkRequired ? 0 : 10000) +
      (v.locale.toLowerCase() == preferred.toLowerCase() ? 1000 : 0) +
      v.quality;
  usable.sort((a, b) => score(b).compareTo(score(a)));
  return usable.first;
}

/// No voice: desktop, web, and tests.
final class SilentVoice implements VoiceOutput {
  const new();

  @override
  Future<VoiceReadiness> prepare(RouteLanguage language) async => VoiceReadiness.none;

  @override
  Future<void> say(String text, {bool queue = false}) async {}

  @override
  Future<void> stop() async {}

  @override
  Future<bool> installVoices() async => false;
}

/// Keeps the screen on while guiding.
abstract interface class ScreenWake {
  Future<void> keepOn({required bool on});
}

final class WakelockScreenWake implements ScreenWake {
  const new();

  @override
  Future<void> keepOn({required bool on}) async {
    try {
      await WakelockPlus.toggle(enable: on);
    } on Object catch (e) {
      _log.info('screen wake lock: $e');
    }
  }
}
