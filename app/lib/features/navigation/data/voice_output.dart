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
Future<Uint8List> loadAlertChime() async {
  final data = await rootBundle.load(alertChimeAsset);
  // A view into a larger buffer, possibly: its own bytes only.
  return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
}

/// The spoken instructions, and the chime before an alert.
abstract interface class VoiceOutput {
  /// Picks the voice for [language] and tells whether one is ready; makes
  /// the chime ready too, which needs no voice. [fresh] asks the device
  /// anew: the user may have installed a voice, or chosen another engine,
  /// in another app since.
  Future<VoiceReadiness> prepare(RouteLanguage language, {bool fresh = false});

  /// The engine [installVoices] opens, as the system's settings name it,
  /// once [prepare] found a voice to download; null when the system
  /// chooses, or where there is a single engine.
  String? get installEngine;

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

/// [VoiceOutput] through the platform's speech engines (lunaway_nav).
///
/// On Android the device's default engine is asked first, and kept when it
/// has a voice of the language on the device; else the first other engine
/// that has one speaks. With none, the voice to download is the default
/// engine's when it knows the language, else the first engine's that does:
/// [installVoices] opens that engine's own page, rather than the system's
/// choice among all of them, from which the user could pick an engine the
/// app would not speak with (`plan/research/117-voix-energie-android.md`).
final class PlatformVoiceOutput implements VoiceOutput {
  new({this._voice = const nav.PlatformVoice(), this._chime = loadAlertChime});

  final nav.PlatformVoice _voice;
  final Future<Uint8List> Function() _chime;
  String _tag = RouteLanguage.fr.speechTag;
  String? _voiceId;
  nav.PlatformEngineInfo? _install;
  bool _chimes = false;
  bool _chimeAsked = false;

  /// An engine that does not answer within this is taken as having no
  /// voice. Google's, its process cold, took 6.3 s to bind on the
  /// emulator (0.5 s warm); one that never answers no longer holds the
  /// voice for the whole trip.
  static const engineWait = Duration(seconds: 20);

  @override
  bool get chimes => _chimes;

  @override
  String? get installEngine => _install?.label;

  /// The voice being picked, and for which language: the preview's
  /// warm-up and the start of the guidance share one listing of the
  /// voices.
  Future<VoiceReadiness>? _picking;
  RouteLanguage? _pickingFor;

  @override
  Future<VoiceReadiness> prepare(RouteLanguage language, {bool fresh = false}) {
    final running = _picking;
    if (running != null && _pickingFor == language && !fresh) return running;
    // A fresh look waits for the one running, whose engines it lets go of.
    final picking = running == null
        ? _pick(language, fresh: fresh)
        : running.then<VoiceReadiness>(
            (_) => _pick(language, fresh: fresh),
            onError: (Object _) => _pick(language, fresh: fresh),
          );
    _picking = picking;
    _pickingFor = language;
    picking.whenComplete(() {
      if (identical(_picking, picking)) _picking = null;
    }).ignore();
    return picking;
  }

  Future<VoiceReadiness> _pick(RouteLanguage language, {required bool fresh}) async {
    await _prepareChime();
    try {
      if (fresh) await _refresh();
      final engines = await _engines();
      final toDownload = <nav.PlatformEngineInfo?>[];
      for (final engine in engines ?? const <nav.PlatformEngineInfo?>[null]) {
        final offer = await _offer(
          engine?.name,
          language,
        ).timeout(engineWait, onTimeout: () => _Offer.none);
        if (offer.kind == _OfferKind.ready) {
          _tag = offer.voice?.locale ?? language.speechTag;
          _voiceId = offer.voice?.id;
          _install = null;
          if (engines != null) await _voice.useEngine(engine?.name);
          _log.fine('voice ${language.name}: ${engine?.name ?? "the engine"}, ${_voiceId ?? _tag}');
          return VoiceReadiness.ready;
        }
        if (offer.kind == _OfferKind.download) toDownload.add(engine);
      }
      _tag = language.speechTag;
      _voiceId = null;
      // The default engine comes first: its download when it has one.
      _install = toDownload.firstOrNull;
      _log.fine('voice ${language.name}: none on the device, to download in ${_install?.name}');
      return toDownload.isEmpty ? VoiceReadiness.none : VoiceReadiness.missingData;
    } on PlatformException catch (e) {
      _log.info('no speech engine: ${e.message}');
      return VoiceReadiness.none;
    } on MissingPluginException {
      return VoiceReadiness.none;
    }
  }

  /// The engines of the device, the default one first; null where the
  /// platform has a single one, which answers unnamed (iOS, macOS).
  Future<List<nav.PlatformEngineInfo>?> _engines() async {
    try {
      return await _voice.engines();
    } on MissingPluginException {
      return null;
    }
  }

  Future<void> _refresh() async {
    try {
      await _voice.refresh();
    } on MissingPluginException {
      return;
    }
  }

  /// What [engine] offers for [language]: a voice it lists on the device
  /// first. An engine that lists none of the language is taken at its
  /// word, unless it speaks the language through its vendor's server only
  /// (Android's network synthesis feature), which would send the road
  /// names there.
  Future<_Offer> _offer(String? engine, RouteLanguage language) async {
    final List<nav.PlatformVoiceInfo> voices;
    try {
      voices = await _voice.voices(language.name, engine: engine);
    } on PlatformException catch (e) {
      // An engine that does not start (removed, broken) has no voice.
      _log.info('speech engine $engine: ${e.message}');
      return _Offer.none;
    }
    final best = pickVoice(voices, preferred: language.speechTag);
    if (best != null) return _Offer(_OfferKind.ready, best);
    // Voices of the language, none of them on the device: each speaks
    // through its vendor's server, or is not downloaded. The one to
    // install works offline and keeps the words on the device.
    if (voices.isNotEmpty) return _Offer.download;
    return switch (await _voice.languageStatus(language.speechTag, engine: engine)) {
      nav.PlatformLanguageStatus.available => const _Offer(_OfferKind.ready),
      nav.PlatformLanguageStatus.network ||
      nav.PlatformLanguageStatus.missingData => _Offer.download,
      nav.PlatformLanguageStatus.notSupported => _Offer.none,
    };
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
      final said = await _voice.speak(
        text,
        language: _tag,
        voiceId: _voiceId,
        chime: chime && _chimes,
      );
      _log.fine('sentence of ${text.length} characters ${said ? 'said' : 'not said'}');
      return said;
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
      return await _voice.installVoiceData(engine: _install?.name);
    } on PlatformException {
      return false;
    }
  }
}

/// What an engine offers for a language: a voice that speaks on the
/// device ([voice] null when the engine lists none but speaks it), a voice
/// to download, or nothing.
final class _Offer {
  const new(this.kind, [this.voice]);

  static const download = _Offer(_OfferKind.download);
  static const none = _Offer(_OfferKind.none);

  final _OfferKind kind;
  final nav.PlatformVoiceInfo? voice;
}

enum _OfferKind { ready, download, none }

/// The voice to speak with among [voices]: installed ones on the device
/// only (one that speaks through its vendor's server fails in a valley
/// without signal and sends the road names there); the exact [preferred]
/// tag first (fr-FR before fr-CA), then the language alone (eSpeak NG's
/// `es` before its `es-419`); then the best quality.
@visibleForTesting
nav.PlatformVoiceInfo? pickVoice(List<nav.PlatformVoiceInfo> voices, {required String preferred}) {
  final usable = [
    for (final v in voices)
      if (!v.notInstalled && !v.networkRequired) v,
  ];
  if (usable.isEmpty) return null;
  int score(nav.PlatformVoiceInfo v) {
    final tag = v.locale.toLowerCase().replaceAll('_', '-');
    final region = tag == preferred.toLowerCase()
        ? 2000
        : tag.contains('-')
        ? 0
        : 1000;
    return region + v.quality;
  }

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
  String? get installEngine => null;

  @override
  Future<VoiceReadiness> prepare(RouteLanguage language, {bool fresh = false}) async {
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
  Future<VoiceReadiness> prepare(RouteLanguage language, {bool fresh = false}) async =>
      VoiceReadiness.none;

  @override
  String? get installEngine => null;

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
