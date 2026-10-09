import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunaway/features/navigation/application/voice_queue.dart';
import 'package:lunaway/features/navigation/domain/route_settings.dart';

import '../../helpers/navigation.dart';

const _camera = 'Radar dans 400 mètres.';
const _closure = 'Route fermée dans 2 kilomètres.';
const _turn = 'Tournez à droite.';
const _turnLater = 'Tournez à gauche.';
const _limit = 'Vitesse limitée à 50.';

void main() {
  /// A queue over a voice whose sentences last until finished, on the
  /// clock of [async]; ready to speak unless told otherwise.
  (VoiceQueue, RecordingVoice) queueOn(
    FakeAsync async, {
    VoiceMode mode = VoiceMode.full,
    bool ready = true,
    bool chimes = true,
    bool hold = true,
  }) {
    final start = DateTime.utc(2026, 10, 9, 9);
    final voice = RecordingVoice(chimes: chimes)..hold = hold;
    final queue = VoiceQueue(output: voice, now: () => start.add(async.elapsed), mode: mode)
      ..ready = ready;
    return (queue, voice);
  }

  /// Ends the sentence being said, and lets the next one start.
  void finish(FakeAsync async, RecordingVoice voice) {
    voice.finish();
    async.flushMicrotasks();
  }

  group('one sentence at a time', () {
    test('the next starts only once the last one ended', () {
      fakeAsync((async) {
        final (queue, voice) = queueOn(async);
        queue
          ..say(_turn, kind: SpeechKind.maneuver, key: 'm1')
          ..say(_camera, kind: SpeechKind.alert, key: 'a1')
          ..say(_limit, kind: SpeechKind.info, key: 'i1');
        async.flushMicrotasks();
        expect(voice.said, [_turn]);
        finish(async, voice);
        expect(voice.said, [_turn, _camera]);
        finish(async, voice);
        expect(voice.said, [_turn, _camera, _limit]);
        expect(voice.mostAtOnce, 1);
      });
    });

    test('alerts go before the instructions and reminders waiting', () {
      fakeAsync((async) {
        final (queue, voice) = queueOn(async);
        queue
          ..say(_closure, kind: SpeechKind.alert, key: 'a0')
          ..say(_limit, kind: SpeechKind.info, key: 'i1')
          ..say(_turn, kind: SpeechKind.maneuver, key: 'm1')
          ..say(_camera, kind: SpeechKind.alert, key: 'a1');
        for (var i = 0; i < 4; i++) {
          finish(async, voice);
        }
        expect(voice.said, [_closure, _camera, _turn, _limit]);
      });
    });

    test('an alert waits for the end of the instruction being said, never cuts it', () {
      fakeAsync((async) {
        final (queue, voice) = queueOn(async);
        queue.say(_turn, kind: SpeechKind.maneuver, key: 'm1');
        async.flushMicrotasks();
        queue.say(_camera, kind: SpeechKind.alert, key: 'a1');
        async.flushMicrotasks();
        expect(voice.stops, 0);
        expect(voice.said, [_turn]);
        finish(async, voice);
        expect(voice.said, [_turn, _camera]);
      });
    });

    test('an instruction that comes during an alert waits for its end', () {
      fakeAsync((async) {
        final (queue, voice) = queueOn(async);
        queue.say(_camera, kind: SpeechKind.alert, key: 'a1');
        async.flushMicrotasks();
        queue.say(_turn, kind: SpeechKind.maneuver, key: 'm1');
        async.flushMicrotasks();
        expect(voice.stops, 0);
        expect(voice.said, [_camera]);
        finish(async, voice);
        expect(voice.said, [_camera, _turn]);
      });
    });

    test('a new instruction cuts the one being said: the latest is the only right one', () {
      fakeAsync((async) {
        final (queue, voice) = queueOn(async);
        queue.say(_turn, kind: SpeechKind.maneuver, key: 'm1');
        async.flushMicrotasks();
        queue.say(_turnLater, kind: SpeechKind.maneuver, key: 'm2');
        async.flushMicrotasks();
        expect(voice.stops, 1);
        expect(voice.said, [_turn, _turnLater]);
        // The end of the sentence cut is not the end of the new one: an
        // alert still waits for it.
        queue.say(_camera, kind: SpeechKind.alert, key: 'a1');
        async.flushMicrotasks();
        expect(voice.said, [_turn, _turnLater]);
        finish(async, voice);
        expect(voice.said, [_turn, _turnLater, _camera]);
        expect(voice.mostAtOnce, 1);
      });
    });

    test('a new instruction takes the place of one waiting', () {
      fakeAsync((async) {
        final (queue, voice) = queueOn(async);
        queue
          ..say(_camera, kind: SpeechKind.alert, key: 'a1')
          ..say(_turn, kind: SpeechKind.maneuver, key: 'm1')
          ..say(_turnLater, kind: SpeechKind.maneuver, key: 'm2');
        async.flushMicrotasks();
        expect(voice.stops, 0, reason: 'the alert goes on');
        finish(async, voice);
        finish(async, voice);
        expect(voice.said, [_camera, _turnLater]);
      });
    });

    test('a platform that never says the end frees the queue after a while', () {
      fakeAsync((async) {
        final (queue, voice) = queueOn(async);
        queue
          ..say(_turn, kind: SpeechKind.maneuver, key: 'm1')
          ..say(_camera, kind: SpeechKind.alert, key: 'a1');
        async.elapse(speechTimeout(_turn, chime: false) - const Duration(milliseconds: 1));
        expect(voice.said, [_turn]);
        async.elapse(const Duration(milliseconds: 2));
        expect(voice.said, [_turn, _camera]);
      });
    });

    test('the wait for a silent platform follows the length, within bounds', () {
      expect(speechTimeout('Ok.', chime: false), const Duration(seconds: 4));
      expect(speechTimeout('x' * 1000, chime: true), const Duration(seconds: 30));
      expect(
        speechTimeout(_closure, chime: true),
        greaterThan(speechTimeout(_closure, chime: false)),
      );
    });
  });

  group('the chime', () {
    test('comes before each alert, never before an instruction or a reminder', () {
      fakeAsync((async) {
        final (queue, voice) = queueOn(async, hold: false);
        queue
          ..say(_camera, kind: SpeechKind.alert, key: 'a1')
          ..say(_turn, kind: SpeechKind.maneuver, key: 'm1')
          ..say(_limit, kind: SpeechKind.info, key: 'i1')
          ..say(_closure, kind: SpeechKind.alert, key: 'a2');
        async.flushMicrotasks();
        expect(voice.calls, [
          (text: _camera, chime: true),
          (text: _closure, chime: true),
          (text: _turn, chime: false),
          (text: _limit, chime: false),
        ]);
      });
    });

    test('alone for an alert when no voice is ready, and nothing for the rest', () {
      fakeAsync((async) {
        final (queue, voice) = queueOn(async, ready: false, hold: false);
        queue
          ..say(_turn, kind: SpeechKind.maneuver, key: 'm1')
          ..say(_camera, kind: SpeechKind.alert, key: 'a1')
          ..say(_limit, kind: SpeechKind.info, key: 'i1');
        async.flushMicrotasks();
        expect(voice.calls, [(text: '', chime: true)]);
        expect(voice.said, isEmpty);
      });
    });

    test('without a voice nor a chime, nothing at all', () {
      fakeAsync((async) {
        final (queue, voice) = queueOn(async, ready: false, chimes: false, hold: false);
        queue.say(_camera, kind: SpeechKind.alert, key: 'a1');
        async.flushMicrotasks();
        expect(voice.calls, isEmpty);
      });
    });

    test('an alert said where the chime cannot play is said without it', () {
      fakeAsync((async) {
        final (queue, voice) = queueOn(async, chimes: false, hold: false);
        queue.say(_camera, kind: SpeechKind.alert, key: 'a1');
        async.flushMicrotasks();
        expect(voice.calls, [(text: _camera, chime: false)]);
      });
    });
  });

  group('the modes', () {
    test('muted says nothing, not even the chime', () {
      fakeAsync((async) {
        final (queue, voice) = queueOn(async, mode: VoiceMode.muted, hold: false);
        queue
          ..say(_camera, kind: SpeechKind.alert, key: 'a1')
          ..say(_turn, kind: SpeechKind.maneuver, key: 'm1');
        async.flushMicrotasks();
        expect(voice.calls, isEmpty);
      });
    });

    test('alerts only says the alerts, with their chime', () {
      fakeAsync((async) {
        final (queue, voice) = queueOn(async, mode: VoiceMode.alerts, hold: false);
        queue
          ..say(_turn, kind: SpeechKind.maneuver, key: 'm1')
          ..say(_limit, kind: SpeechKind.info, key: 'i1')
          ..say(_camera, kind: SpeechKind.alert, key: 'a1');
        async.flushMicrotasks();
        expect(voice.calls, [(text: _camera, chime: true)]);
      });
    });

    test('muted while speaking cuts the sentence and forgets those waiting', () {
      fakeAsync((async) {
        final (queue, voice) = queueOn(async);
        queue
          ..say(_closure, kind: SpeechKind.alert, key: 'a1')
          ..say(_turn, kind: SpeechKind.maneuver, key: 'm1')
          ..say(_camera, kind: SpeechKind.alert, key: 'a2');
        async.flushMicrotasks();
        queue.mode = VoiceMode.muted;
        async.flushMicrotasks();
        expect(voice.stops, 1);
        finish(async, voice);
        async.elapse(const Duration(seconds: 40));
        expect(voice.said, [_closure]);
        // Back to the full voice: what was forgotten stays so.
        queue.mode = VoiceMode.full;
        async.flushMicrotasks();
        expect(voice.said, [_closure]);
      });
    });

    test('alerts only while an instruction is said cuts it, and the alert waiting comes', () {
      fakeAsync((async) {
        final (queue, voice) = queueOn(async);
        queue
          ..say(_turn, kind: SpeechKind.maneuver, key: 'm1')
          ..say(_limit, kind: SpeechKind.info, key: 'i1')
          ..say(_camera, kind: SpeechKind.alert, key: 'a1');
        async.flushMicrotasks();
        queue.mode = VoiceMode.alerts;
        async.flushMicrotasks();
        expect(voice.stops, 1);
        expect(voice.said, [_turn, _camera]);
        finish(async, voice);
        expect(voice.said, [_turn, _camera], reason: 'the reminder is forgotten');
      });
    });

    test('alerts only while an alert is said lets it end, and drops the instruction waiting', () {
      fakeAsync((async) {
        final (queue, voice) = queueOn(async);
        queue
          ..say(_camera, kind: SpeechKind.alert, key: 'a1')
          ..say(_turn, kind: SpeechKind.maneuver, key: 'm1');
        async.flushMicrotasks();
        queue.mode = VoiceMode.alerts;
        async.flushMicrotasks();
        expect(voice.stops, 0);
        finish(async, voice);
        expect(voice.said, [_camera]);
      });
    });
  });

  group('what is said', () {
    test('an alert that waited is written again when said: the distance left then', () {
      fakeAsync((async) {
        final (queue, voice) = queueOn(async);
        var ahead = 400;
        String camera() => 'Radar dans $ahead mètres.';
        queue
          ..say(_turn, kind: SpeechKind.maneuver, key: 'm1')
          ..say(camera(), kind: SpeechKind.alert, key: 'a1', fresh: camera);
        async.flushMicrotasks();
        // The vehicle drives on while the instruction is said.
        ahead = 300;
        finish(async, voice);
        expect(voice.said, [_turn, 'Radar dans 300 mètres.']);
      });
    });

    test('an alert whose camera was passed while it waited is not said, nor its chime', () {
      fakeAsync((async) {
        final (queue, voice) = queueOn(async);
        queue
          ..say(_turn, kind: SpeechKind.maneuver, key: 'm1')
          ..say(_camera, kind: SpeechKind.alert, key: 'a1', fresh: () => '')
          ..say(_closure, kind: SpeechKind.alert, key: 'a2');
        async.flushMicrotasks();
        finish(async, voice);
        expect(voice.said, [_turn, _closure]);
        expect(voice.calls.where((c) => c.chime), hasLength(1), reason: 'the closure only');
      });
    });

    test('a key said or waiting is not taken again', () {
      fakeAsync((async) {
        final (queue, voice) = queueOn(async);
        queue
          ..say(_camera, kind: SpeechKind.alert, key: 'camera-7')
          ..say(_closure, kind: SpeechKind.alert, key: 'closure-3')
          ..say(_closure, kind: SpeechKind.alert, key: 'closure-3');
        finish(async, voice);
        finish(async, voice);
        queue.say(_camera, kind: SpeechKind.alert, key: 'camera-7');
        finish(async, voice);
        expect(voice.said, [_camera, _closure]);
      });
    });

    test('an instruction that waited more than a few seconds is no longer said', () {
      fakeAsync((async) {
        final (queue, voice) = queueOn(async);
        // A long alert: the platform's own end, not the queue's timeout,
        // decides when it is over.
        final long = 'Attention, ${'très ' * 40}long.';
        queue
          ..say(long, kind: SpeechKind.alert, key: 'a1')
          ..say(_turn, kind: SpeechKind.maneuver, key: 'm1')
          ..say(_limit, kind: SpeechKind.info, key: 'i1');
        async.elapse(SpeechKind.maneuver.maxWait + const Duration(seconds: 1));
        finish(async, voice);
        expect(voice.said, [long]);
      });
    });

    test('an alert waits longer, within its own bound', () {
      fakeAsync((async) {
        final (queue, voice) = queueOn(async);
        final long = 'Attention, ${'très ' * 40}long.';
        queue
          ..say(long, kind: SpeechKind.alert, key: 'a1')
          ..say(_camera, kind: SpeechKind.alert, key: 'a2');
        async.elapse(SpeechKind.alert.maxWait - const Duration(seconds: 1));
        finish(async, voice);
        expect(voice.said, [long, _camera]);
        finish(async, voice);
        queue
          ..say(long, kind: SpeechKind.alert, key: 'a3')
          ..say(_closure, kind: SpeechKind.alert, key: 'a4');
        async.elapse(SpeechKind.alert.maxWait + const Duration(seconds: 1));
        finish(async, voice);
        expect(voice.said, [long, _camera, long], reason: 'the closure waited too long');
      });
    });

    test('the end of the guidance stops the sentence and says nothing more', () {
      fakeAsync((async) {
        final (queue, voice) = queueOn(async);
        queue
          ..say(_camera, kind: SpeechKind.alert, key: 'a1')
          ..say(_turn, kind: SpeechKind.maneuver, key: 'm1');
        async.flushMicrotasks();
        queue.close();
        async.flushMicrotasks();
        expect(voice.stops, 1);
        queue.say(_closure, kind: SpeechKind.alert, key: 'a2');
        async.elapse(const Duration(minutes: 1));
        expect(voice.said, [_camera]);
      });
    });
  });
}
