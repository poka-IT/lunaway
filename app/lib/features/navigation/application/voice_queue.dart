import 'dart:async';
import 'dart:math' as math;

import 'package:logging/logging.dart';
import 'package:lunaway/features/navigation/data/voice_output.dart';
import 'package:lunaway/features/navigation/domain/route_settings.dart';
import 'package:meta/meta.dart';

final _log = Logger('voice');

/// What a sentence of the guidance is: which voice modes say it, in what
/// order, and how long it may wait its turn.
enum SpeechKind {
  /// A safety alert: a speed camera or a danger zone, a closure, works or
  /// a size limit coming, a restriction of the route, a new route or a stop
  /// moved, the position lost. Said in every mode that speaks, after the
  /// chime, before what waits.
  ///
  /// It speaks of what lies 400 m to 2 km ahead, 20 s and more away at the
  /// speeds it is given for: after 15 s behind other sentences, the thing
  /// may be passed, or a new route may have changed the picture.
  alert(Duration(seconds: 15)),

  /// An instruction of the routing engine, or the arrival. Given about
  /// 300 m before a turn in town, some 20 s at 50 km/h: one that waited
  /// 6 s, about 100 m, comes too late to be safe, and the next one is
  /// already on its way.
  maneuver(Duration(seconds: 6)),

  /// A reminder: the road's limit, when the driver goes over it. It tells
  /// the speed of this moment, out of date within seconds.
  info(Duration(seconds: 5));

  new(this.maxWait);

  /// Waiting longer than this, it is no longer said.
  final Duration maxWait;
}

/// How long the queue waits for [VoiceOutput.say] to end before it moves
/// on by itself: the platform says when a sentence ends, this only covers
/// one that never answers. Twelve characters a second, a slow voice, plus
/// the chime and a margin, within 4 to 30 seconds.
@visibleForTesting
Duration speechTimeout(String text, {required bool chime}) => Duration(
  milliseconds: math.min(30000, math.max(4000, (chime ? 500 : 0) + text.length * 85 + 2000)),
);

/// The guidance's sentences, said one at a time, in the order a driver
/// needs them, as the voice mode allows.
///
/// - [VoiceMode.full] says everything, [VoiceMode.alerts] the alerts only,
///   [VoiceMode.muted] nothing, and plays no chime.
/// - A short chime comes before each alert, never before an instruction.
/// - One sentence at a time: the next starts once the platform says the
///   last one ended.
/// - Alerts go before the instructions and reminders waiting. An alert
///   waits for the instruction being said; an instruction waits for the
///   alert. A new instruction takes the place of one waiting and cuts one
///   being said: the latest is the only right one.
/// - A key said or waiting is not taken again.
/// - Without a voice ready, an alert is the chime alone; without a chime
///   either, nothing.
///
/// A plain object the guidance holds, with the clock injected: testable
/// without a container.
final class VoiceQueue {
  new({required this._output, required this._now, this._mode = VoiceMode.full});

  final VoiceOutput _output;
  final DateTime Function() _now;
  VoiceMode _mode;

  /// Whether a voice of the guidance's language is ready; without one, an
  /// alert is the chime alone.
  bool ready = false;
  bool _closed = false;
  final Set<String> _keys = {};
  final List<_Speech> _waiting = [];
  _Speech? _playing;
  Timer? _timeout;

  /// Moves on with each sentence started, cut or ended: the end of a
  /// sentence cut is not the end of the next one.
  int _turn = 0;

  VoiceMode get mode => _mode;

  /// Muted cuts the sentence being said and forgets those waiting; alerts
  /// only cuts an instruction or a reminder being said and forgets those
  /// waiting.
  set mode(VoiceMode mode) {
    if (_closed || mode == _mode) return;
    _mode = mode;
    switch (mode) {
      case VoiceMode.full:
        return;
      case VoiceMode.alerts:
        _waiting.removeWhere((s) => s.kind != SpeechKind.alert);
        if (_playing case final playing? when playing.kind != SpeechKind.alert) {
          _cut();
          _next();
        }
      case VoiceMode.muted:
        _waiting.clear();
        // Stopped even with nothing known to be playing: a sentence the
        // timeout gave up on may still be heard.
        _cut();
    }
  }

  /// Says [text], a sentence of [kind], unless [key] was said or waits
  /// already. [fresh], when given, writes the sentence again at the moment
  /// it is said, after a wait behind another: a distance said then is the
  /// one left then; an empty sentence is no longer worth saying.
  void say(String text, {required SpeechKind kind, required String key, String Function()? fresh}) {
    if (_closed || text.isEmpty || !_admits(kind) || !_keys.add(key)) return;
    if (kind == SpeechKind.maneuver) {
      _waiting.removeWhere((s) => s.kind == SpeechKind.maneuver);
      if (_playing?.kind == SpeechKind.maneuver) _cut();
    }
    _waiting.add(_Speech(text: text, kind: kind, at: _now(), fresh: fresh));
    _next();
  }

  /// The end of the guidance: the sentence being said stops, the others
  /// are forgotten, nothing more is said.
  void close() {
    if (_closed) return;
    _closed = true;
    _waiting.clear();
    _cut();
  }

  bool _admits(SpeechKind kind) => switch (_mode) {
    VoiceMode.full => true,
    VoiceMode.alerts => kind == SpeechKind.alert,
    VoiceMode.muted => false,
  };

  void _next() {
    if (_closed || _playing != null) return;
    final now = _now();
    _waiting.removeWhere((s) => now.difference(s.at) > s.kind.maxWait);
    while (_waiting.isNotEmpty) {
      final speech = _waiting.removeAt(_first());
      final sentence = speech.fresh?.call() ?? speech.text;
      // Past what it spoke of while it waited: not said, not even its chime.
      if (sentence.isEmpty) continue;
      final chime = speech.kind == SpeechKind.alert && _output.chimes;
      final text = ready ? sentence : '';
      if (text.isEmpty && !chime) continue;
      _play(speech, text: text, chime: chime);
      return;
    }
  }

  /// The index of the sentence to say next: the first alert, else the
  /// instruction, else the first reminder.
  int _first() {
    for (final kind in SpeechKind.values) {
      final i = _waiting.indexWhere((s) => s.kind == kind);
      if (i >= 0) return i;
    }
    return 0;
  }

  void _play(_Speech speech, {required String text, required bool chime}) {
    _playing = speech;
    final turn = ++_turn;
    _timeout = Timer(speechTimeout(text, chime: chime), () => _ended(turn));
    unawaited(
      _output
          .say(text, chime: chime)
          .then(
            (_) => _ended(turn),
            onError: (Object e) {
              _log.info('speech failed: $e');
              _ended(turn);
            },
          ),
    );
  }

  void _ended(int turn) {
    if (turn != _turn || _playing == null) return;
    _timeout?.cancel();
    _timeout = null;
    _playing = null;
    _next();
  }

  /// Stops the sentence being said; its end, when the platform tells it,
  /// is ignored.
  void _cut() {
    _turn++;
    _timeout?.cancel();
    _timeout = null;
    _playing = null;
    unawaited(_output.stop());
  }
}

final class _Speech {
  const new({required this.text, required this.kind, required this.at, this.fresh});

  final String text;
  final SpeechKind kind;

  /// The sentence as it reads when it is said ([VoiceQueue.say]).
  final String Function()? fresh;

  /// When it was given, to drop it once it waited too long.
  final DateTime at;
}
