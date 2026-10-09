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

/// The chime played before a spoken alert (`tool/sounds/chime.py`).
const alertChimeAsset = 'assets/sounds/alert_chime.wav';

/// The bytes of [alertChimeAsset].
Future<Uint8List> loadAlertChime() async =>
    (await rootBundle.load(alertChimeAsset)).buffer.asUint8List();

/// The spoken instructions, and the chime before an alert.
abstract interface class VoiceOutput {
  /// Picks the voice for [language] and tells whether one is ready; makes
  /// the chime ready too, which needs no voice.
  Future<VoiceReadiness> prepare(RouteLanguage language);

  /// Whether the chime plays here, once [prepare] has run.
  bool get chimes;

  /// Says [text], after the chime when [chime]; an empty [text] with
  /// [chime] plays the chime alone. Completes once it is over: true when
  /// said to the end, false when [stop] cut it or it failed.
  Future<bool> say(String text, {bool chime = false});

  /// Cuts what is being said, and the chime.
  Future<void> stop();

  /// Opens the system's page that installs voices; false where there is
  /// none.
  Future<bool> installVoices();
}

/// [VoiceOutput] through the platform's speech engine (lunaway_nav).
final class PlatformVoiceOutput implements VoiceOutput {
  new({this._voice = const nav.PlatformVoice(), this._chime = loadAlertChime});

  final nav.PlatformVoice _voice;
  final Future<Uint8List> Function() _chime;
  String _tag = RouteLanguage.fr.speechTag;
  String? _voiceId;
  bool _chimes = false;
  bool _chimeAsked = false;

  @override
  bool get chimes => _chimes;

  @override
  Future<VoiceReadiness> prepare(RouteLanguage language) async {
    await _prepareChime();
    try {
      final code = language.name;
      final voices = await _voice.voices(code);
      final best = pickVoice(voices, preferred: language.speechTag);
      _tag = best?.locale ?? language.speechTag;
      _voiceId = best?.id;
      if (best != null) return VoiceReadiness.ready;
      // Voices of the language, each speaking through its vendor's server:
      // the one to install works offline and keeps the words on the device.
      if (voices.any((v) => !v.notInstalled)) return VoiceReadiness.missingData;
      // An engine that lists no voice may still speak the language, through
      // a voice nothing proves is on the device: the road names would leave
      // it. Asked to install one, the user gets a voice the app can check.
      return switch (await _voice.languageStatus(language.speechTag)) {
        nav.PlatformLanguageStatus.notSupported => VoiceReadiness.none,
        nav.PlatformLanguageStatus.available ||
        nav.PlatformLanguageStatus.missingData => VoiceReadiness.missingData,
      };
    } on PlatformException catch (e) {
      _log.info('no speech engine: ${e.message}');
      return VoiceReadiness.none;
    } on MissingPluginException {
      return VoiceReadiness.none;
    }
  }

  /// Hands the chime to the platform, once per run: the platform keeps it.
  Future<void> _prepareChime() async {
    if (_chimeAsked) return;
    _chimeAsked = true;
    try {
      _chimes = await _voice.setChime(await _chime());
    } on Object catch (e) {
      // An older platform side, or the asset missing: the alerts are said
      // without their chime.
      _log.info('no alert chime: $e');
      _chimes = false;
    }
  }

  @override
  Future<bool> say(String text, {bool chime = false}) async {
    try {
      return await _voice.speak(text, language: _tag, voiceId: _voiceId, chime: chime && _chimes);
    } on PlatformException catch (e) {
      _log.info('speech failed: ${e.message}');
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  @override
  Future<void> stop() async {
    try {
      await _voice.stop();
    } on PlatformException catch (e) {
      _log.info('speech stop failed: ${e.message}');
    } on MissingPluginException {
      return;
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

/// The voice to speak with among [voices]: installed ones on the device
/// only (one that speaks through its vendor's server fails in a valley
/// without signal and sends the road names there); the exact [preferred]
/// tag first (fr-FR before fr-CA); then the best quality.
@visibleForTesting
nav.PlatformVoiceInfo? pickVoice(List<nav.PlatformVoiceInfo> voices, {required String preferred}) {
  final usable = [
    for (final v in voices)
      if (!v.notInstalled && !v.networkRequired) v,
  ];
  if (usable.isEmpty) return null;
  int score(nav.PlatformVoiceInfo v) =>
      (v.locale.toLowerCase() == preferred.toLowerCase() ? 1000 : 0) + v.quality;
  usable.sort((a, b) => score(b).compareTo(score(a)));
  return usable.first;
}

/// The index of the voice to speak [language] with among [voices]: local
/// ones only, the exact [preferred] tag first (fr-FR before fr-CA), then the
/// browser's default. Null when none speaks the language on the device.
int? pickBrowserVoice(
  List<({String lang, bool local, bool isDefault})> voices, {
  required String language,
  required String preferred,
}) {
  int? best;
  var bestScore = -1;
  for (final (i, v) in voices.indexed) {
    final tag = v.lang.replaceAll('_', '-').toLowerCase();
    if (!v.local || !(tag == language || tag.startsWith('$language-'))) continue;
    final score = (tag == preferred.toLowerCase() ? 2 : 0) + (v.isDefault ? 1 : 0);
    if (score > bestScore) {
      best = i;
      bestScore = score;
    }
  }
  return best;
}

/// What a browser gives the voice: its speech synthesis (Web Speech API)
/// and its sound (Web Audio API), in `web_voice_web.dart`.
abstract interface class BrowserSpeech {
  /// The voices of the speech synthesis, once the browser has listed them.
  Future<List<({String lang, bool local, bool isDefault})>> voices();

  /// Says [text] with the voice at [voice] in [voices], tagged [tag];
  /// completes when it ends: true when said to the end.
  Future<bool> speak(String text, {required int voice, required String tag});

  /// Decodes [wav] for [playChime]; false where the browser cannot.
  Future<bool> loadChime(Uint8List wav);

  /// Plays the chime; completes when it ends: true when played to the end.
  Future<bool> playChime();

  /// Cuts the sentence and the chime being played.
  void cancel();
}

/// [VoiceOutput] in a browser, with the voices the device has itself: a
/// voice the browser marks as remote (`localService` false, such as the
/// "Google" voices of Chrome on a computer) sends each sentence, road names
/// included, to its vendor, the rule the phones follow too ([pickVoice]).
/// Without a local voice of the language the instructions stay on screen,
/// the guidance says so, and an alert still gets its chime.
final class BrowserVoiceOutput implements VoiceOutput {
  new(this._browser, {this._chime = loadAlertChime});

  final BrowserSpeech _browser;
  final Future<Uint8List> Function() _chime;
  int? _voice;
  String _tag = RouteLanguage.fr.speechTag;
  bool _chimes = false;
  bool _chimeAsked = false;

  /// Moves on at each [stop]: a sentence waiting for its chime to end is
  /// not said once stopped.
  int _turn = 0;

  @override
  bool get chimes => _chimes;

  @override
  Future<VoiceReadiness> prepare(RouteLanguage language) async {
    if (!_chimeAsked) {
      _chimeAsked = true;
      try {
        _chimes = await _browser.loadChime(await _chime());
      } on Object catch (e) {
        _log.info('no alert chime: $e');
      }
    }
    try {
      final voices = await _browser.voices();
      _tag = language.speechTag;
      _voice = pickBrowserVoice(voices, language: language.name, preferred: language.speechTag);
      return _voice == null ? VoiceReadiness.none : VoiceReadiness.ready;
    } on Object catch (e) {
      _log.info('no speech synthesis: $e');
      _voice = null;
      return VoiceReadiness.none;
    }
  }

  @override
  Future<bool> say(String text, {bool chime = false}) async {
    final turn = _turn;
    final voice = _voice;
    final withChime = chime && _chimes;
    if (text.isEmpty && !withChime) return false;
    try {
      if (withChime) {
        final played = await _browser.playChime();
        if (turn != _turn) return false;
        if (text.isEmpty) return played;
      }
      if (voice == null) return false;
      return await _browser.speak(text, voice: voice, tag: _tag);
    } on Object catch (e) {
      _log.info('speech failed: $e');
      return false;
    }
  }

  @override
  Future<void> stop() async {
    _turn++;
    try {
      _browser.cancel();
    } on Object catch (e) {
      _log.info('speech stop failed: $e');
    }
  }

  @override
  Future<bool> installVoices() async => false;
}

/// No voice and no sound: Windows, and tests.
final class SilentVoice implements VoiceOutput {
  const new();

  @override
  Future<VoiceReadiness> prepare(RouteLanguage language) async => VoiceReadiness.none;

  @override
  bool get chimes => false;

  @override
  Future<bool> say(String text, {bool chime = false}) async => false;

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
