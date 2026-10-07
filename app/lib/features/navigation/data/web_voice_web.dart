import 'dart:async';
import 'dart:js_interop';

import 'package:logging/logging.dart';
import 'package:lunaway/features/navigation/data/voice_output.dart';
import 'package:lunaway/features/navigation/domain/route_settings.dart';
import 'package:web/web.dart' as web;

final _log = Logger('voice');

/// The browser's speech synthesis (Web Speech API).
VoiceOutput browserVoice() => WebSpeechVoice();

/// [VoiceOutput] through `speechSynthesis`, with the voices the device has
/// itself: a voice the browser marks as remote (`localService` false, such
/// as the "Google" voices of Chrome on a computer) sends each sentence, road
/// names included, to its vendor, the rule the phones follow too
/// ([pickVoice]). Without a local voice of the language the instructions
/// stay on screen and the guidance says so.
final class WebSpeechVoice implements VoiceOutput {
  web.SpeechSynthesisVoice? _voice;
  String _tag = RouteLanguage.fr.speechTag;

  web.SpeechSynthesis get _synth => web.window.speechSynthesis;

  @override
  Future<VoiceReadiness> prepare(RouteLanguage language) async {
    try {
      final voices = await _voices();
      _tag = language.speechTag;
      final best = pickBrowserVoice(
        [for (final v in voices) (lang: v.lang, local: v.localService, isDefault: v.default_)],
        language: language.name,
        preferred: language.speechTag,
      );
      _voice = best == null ? null : voices[best];
      return _voice == null ? VoiceReadiness.none : VoiceReadiness.ready;
    } on Object catch (e) {
      _log.info('no speech synthesis: $e');
      return VoiceReadiness.none;
    }
  }

  /// The voices, once the browser has listed them: Chrome fills the list
  /// after the page loads and says so with `voiceschanged`.
  Future<List<web.SpeechSynthesisVoice>> _voices() async {
    final list = _synth.getVoices().toDart;
    if (list.isNotEmpty) return list;
    final changed = Completer<void>();
    void done(web.Event _) {
      if (!changed.isCompleted) changed.complete();
    }

    final listener = done.toJS;
    _synth.addEventListener('voiceschanged', listener);
    try {
      await changed.future.timeout(const Duration(seconds: 2), onTimeout: () {});
    } finally {
      _synth.removeEventListener('voiceschanged', listener);
    }
    return _synth.getVoices().toDart;
  }

  @override
  Future<void> say(String text, {bool queue = false}) async {
    final voice = _voice;
    if (voice == null) return;
    // The browser queues what it is given: a new instruction cuts the one
    // being said, a warning waits for it.
    if (!queue) _synth.cancel();
    _synth.speak(
      web.SpeechSynthesisUtterance(text)
        ..voice = voice
        ..lang = _tag,
    );
  }

  @override
  Future<void> stop() async => _synth.cancel();

  @override
  Future<bool> installVoices() async => false;
}
