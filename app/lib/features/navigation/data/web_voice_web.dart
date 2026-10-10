import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:lunaway/features/navigation/data/voice_output.dart';
import 'package:web/web.dart' as web;

/// The browser's speech synthesis, and the chime through Web Audio.
VoiceOutput browserVoice() => BrowserVoiceOutput(WebBrowserSpeech());

/// The audio context the chime plays in, made once for the page.
web.AudioContext? _pageAudio;

/// Opens the speech synthesis and the sound for the page, from the user's
/// tap that starts a guidance. Safari on iOS starts neither outside a
/// user's gesture (WebKit holds a page's first `speak` back until it comes
/// within one), and the guidance speaks its first sentence after a few
/// awaits, out of the tap: a silent sentence and the audio context resumed
/// in the tap itself open both for the sentences and the chimes that
/// follow. Nothing where the browser has neither.
void primeBrowserSpeech() {
  try {
    final silent = web.SpeechSynthesisUtterance('')..volume = 0;
    web.window.speechSynthesis.speak(silent);
  } on Object {
    // No speech synthesis: the guidance says so once it starts.
  }
  try {
    final audio = _pageAudio ??= web.AudioContext();
    if (audio.state == 'suspended') {
      unawaited(audio.resume().toDart.then((_) {}, onError: (Object _) {}));
    }
  } on Object {
    // No Web Audio: alerts go without their chime.
  }
}

/// [BrowserSpeech] over `speechSynthesis` and an `AudioContext`.
final class WebBrowserSpeech implements BrowserSpeech {
  web.SpeechSynthesis get _synth => web.window.speechSynthesis;
  List<web.SpeechSynthesisVoice> _voices = const [];

  web.AudioContext? _audio;
  web.AudioBuffer? _chime;
  web.AudioBufferSourceNode? _source;
  Completer<bool>? _chimeEnd;

  /// Counts the cuts: a chime still waiting for its context is not played
  /// after one.
  int _cancels = 0;

  /// The sentence being said, held: Chrome drops the events of an
  /// utterance nothing references any more, and its end would never come.
  web.SpeechSynthesisUtterance? _utterance;
  Completer<bool>? _spoken;

  @override
  Future<List<({String lang, bool local, bool isDefault})>> voices() async {
    _voices = await _listed();
    return [for (final v in _voices) (lang: v.lang, local: v.localService, isDefault: v.default_)];
  }

  /// The voices, once the browser has listed them: Chrome fills the list
  /// after the page loads and says so with `voiceschanged`.
  Future<List<web.SpeechSynthesisVoice>> _listed() async {
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
  Future<bool> speak(String text, {required int voice, required String tag}) async {
    if (voice < 0 || voice >= _voices.length) return false;
    final done = Completer<bool>();
    void end({required bool said}) {
      if (!done.isCompleted) done.complete(said);
    }

    final utterance = web.SpeechSynthesisUtterance(text)
      ..voice = _voices[voice]
      ..lang = tag
      ..onend = ((web.Event _) => end(said: true)).toJS
      // A sentence cut by cancel() ends here too ("interrupted").
      ..onerror = ((web.Event _) => end(said: false)).toJS;
    _utterance = utterance;
    _spoken = done;
    _synth.speak(utterance);
    try {
      return await done.future;
    } finally {
      if (identical(_utterance, utterance)) _utterance = null;
    }
  }

  @override
  Future<bool> loadChime(Uint8List wav) async {
    final audio = _audio ??= _pageAudio ??= web.AudioContext();
    // decodeAudioData takes the buffer over: a copy is handed to it.
    final bytes = Uint8List.fromList(wav);
    _chime = await audio.decodeAudioData(bytes.buffer.toJS).toDart;
    return true;
  }

  @override
  Future<bool> playChime() async {
    final audio = _audio;
    final chime = _chime;
    if (audio == null || chime == null) return false;
    // A context made before the page was touched starts suspended; the
    // guidance starts from a tap, which lets it resume.
    if (audio.state == 'suspended') {
      final cancels = _cancels;
      try {
        await audio.resume().toDart.timeout(const Duration(seconds: 1));
      } on Object {
        return false;
      }
      // Muted or ended while the context woke up: no chime after it.
      if (cancels != _cancels) return false;
    }
    final done = Completer<bool>();
    final source = audio.createBufferSource()
      ..buffer = chime
      ..onended = ((web.Event _) {
        if (!done.isCompleted) done.complete(true);
      }).toJS;
    _source = source;
    _chimeEnd = done;
    source
      ..connect(audio.destination)
      ..start();
    // A context that stays silent never ends the source.
    return await done.future.timeout(const Duration(seconds: 2), onTimeout: () => false);
  }

  @override
  void cancel() {
    _cancels++;
    _synth.cancel();
    final source = _source;
    _source = null;
    if (source != null) {
      try {
        source.stop();
      } on Object {
        // Already over.
      }
    }
    if (_chimeEnd case final end? when !end.isCompleted) end.complete(false);
    if (_spoken case final spoken? when !spoken.isCompleted) spoken.complete(false);
  }
}
