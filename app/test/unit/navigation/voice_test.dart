import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunaway/features/navigation/application/voice_queue.dart';
import 'package:lunaway/features/navigation/data/voice_output.dart';
import 'package:lunaway/features/navigation/domain/route_settings.dart';
import 'package:lunaway_nav/lunaway_nav.dart';

PlatformVoiceInfo voice(
  String id, {
  String locale = 'fr-FR',
  bool network = false,
  bool installed = true,
  int quality = 300,
}) => PlatformVoiceInfo(
  id: id,
  locale: locale,
  networkRequired: network,
  notInstalled: !installed,
  quality: quality,
);

/// The engine's answers, set by each test, and what it was asked to say.
final class FakePlatformVoice extends PlatformVoice {
  new(this.list, this.status, {this.chimeError});

  final List<PlatformVoiceInfo> list;
  final PlatformLanguageStatus status;

  /// Thrown when the chime is handed over: an older platform side.
  final Exception? chimeError;
  final List<Uint8List> chimesSet = [];
  final List<({String text, bool chime})> spoken = [];

  @override
  Future<List<PlatformVoiceInfo>> voices(String language) async => list;

  @override
  Future<PlatformLanguageStatus> languageStatus(String language) async => status;

  @override
  Future<bool> setChime(Uint8List wav) async {
    if (chimeError case final e?) throw e;
    chimesSet.add(wav);
    return true;
  }

  @override
  Future<bool> speak(
    String text, {
    required String language,
    String? voiceId,
    double rate = 1,
    bool chime = false,
  }) async {
    spoken.add((text: text, chime: chime));
    return true;
  }
}

/// A browser with the voices given, whose chime ends when [chimeEnd] says.
final class FakeBrowser implements BrowserSpeech {
  new(this.list, {this.webAudio = true});

  final List<({String lang, bool local, bool isDefault})> list;

  /// Whether the browser decodes the chime (Web Audio).
  final bool webAudio;
  int chimesPlayed = 0;
  final List<String> spoken = [];
  int cancels = 0;

  /// Holds the chime until completed; it ends at once without.
  Completer<bool>? chimeEnd;

  @override
  Future<List<({String lang, bool local, bool isDefault})>> voices() async => list;

  @override
  Future<bool> speak(String text, {required int voice, required String tag}) async {
    spoken.add(text);
    return true;
  }

  @override
  Future<bool> loadChime(Uint8List wav) async {
    if (!webAudio) throw UnsupportedError('no AudioContext');
    return true;
  }

  @override
  Future<bool> playChime() async {
    chimesPlayed++;
    return await chimeEnd?.future ?? true;
  }

  @override
  void cancel() {
    cancels++;
    chimeEnd?.complete(false);
  }
}

Future<Uint8List> _wav() async => Uint8List.fromList([82, 73, 70, 70]);

void main() {
  group('the voice chosen', () {
    test('speaks on the device, never through its vendor', () {
      final picked = pickVoice([
        voice('cloud', network: true, quality: 500),
        voice('local'),
      ], preferred: 'fr-FR');
      expect(picked?.id, 'local');
      expect(pickVoice([voice('cloud', network: true)], preferred: 'fr-FR'), isNull);
    });

    test('of the exact language first, then the best one, installed only', () {
      final picked = pickVoice([
        voice('quebec', locale: 'fr-CA', quality: 500),
        voice('france'),
        voice('better', quality: 400, installed: false),
      ], preferred: 'fr-FR');
      expect(picked?.id, 'france');
    });
  });

  test('voices that all need the network mean a voice to install', () async {
    final output = PlatformVoiceOutput(
      voice: FakePlatformVoice([voice('cloud', network: true)], PlatformLanguageStatus.available),
      chime: _wav,
    );
    expect(await output.prepare(RouteLanguage.fr), VoiceReadiness.missingData);
  });

  test('an engine that lists no voice is not trusted to speak on the device', () async {
    final output = PlatformVoiceOutput(
      voice: FakePlatformVoice(const [], PlatformLanguageStatus.available),
      chime: _wav,
    );
    expect(await output.prepare(RouteLanguage.en), VoiceReadiness.missingData);
  });

  test('nor one that does not know the language', () async {
    final output = PlatformVoiceOutput(
      voice: FakePlatformVoice(const [], PlatformLanguageStatus.notSupported),
      chime: _wav,
    );
    expect(await output.prepare(RouteLanguage.en), VoiceReadiness.none);
  });

  group('the chime on a phone or a Mac', () {
    test('is handed to the platform once, and plays before what asks for it', () async {
      final platform = FakePlatformVoice([voice('local')], PlatformLanguageStatus.available);
      final output = PlatformVoiceOutput(voice: platform, chime: _wav);
      await output.prepare(RouteLanguage.fr);
      await output.prepare(RouteLanguage.fr);
      expect(platform.chimesSet, [await _wav()]);
      expect(output.chimes, isTrue);
      await output.say('Radar dans 400 mètres.', chime: true);
      await output.say('Tournez à droite.');
      expect(platform.spoken, [
        (text: 'Radar dans 400 mètres.', chime: true),
        (text: 'Tournez à droite.', chime: false),
      ]);
    });

    test('a platform side without it says the alerts without it', () async {
      final platform = FakePlatformVoice(
        [voice('local')],
        PlatformLanguageStatus.available,
        chimeError: MissingPluginException('setChime'),
      );
      final output = PlatformVoiceOutput(voice: platform, chime: _wav);
      expect(await output.prepare(RouteLanguage.fr), VoiceReadiness.ready);
      expect(output.chimes, isFalse);
      await output.say('Radar dans 400 mètres.', chime: true);
      expect(platform.spoken, [(text: 'Radar dans 400 mètres.', chime: false)]);
    });
  });

  group('in a browser', () {
    test('without a local voice, an alert is the chime alone, with no error', () {
      fakeAsync((async) {
        // Chrome on a computer: its French voice speaks through Google.
        final browser = FakeBrowser([(lang: 'fr-FR', local: false, isDefault: true)]);
        final output = BrowserVoiceOutput(browser, chime: _wav);
        VoiceReadiness? readiness;
        unawaited(output.prepare(RouteLanguage.fr).then((r) => readiness = r));
        async.flushMicrotasks();
        expect(readiness, VoiceReadiness.none);
        expect(output.chimes, isTrue);
        final queue = VoiceQueue(output: output, now: () => DateTime.utc(2026))
          ..ready = readiness == VoiceReadiness.ready
          ..say('Tournez à droite.', kind: SpeechKind.maneuver, key: 'm1')
          ..say('Radar dans 400 mètres.', kind: SpeechKind.alert, key: 'a1');
        async.elapse(const Duration(seconds: 1));
        expect(browser.chimesPlayed, 1);
        expect(browser.spoken, isEmpty);
        queue.close();
      });
    });

    test('with a local voice, the sentence follows the chime, and a stop during the chime '
        'leaves it unsaid', () async {
      final browser = FakeBrowser([(lang: 'fr-FR', local: true, isDefault: true)]);
      final output = BrowserVoiceOutput(browser, chime: _wav);
      expect(await output.prepare(RouteLanguage.fr), VoiceReadiness.ready);
      expect(await output.say('Radar dans 400 mètres.', chime: true), isTrue);
      expect(browser.spoken, ['Radar dans 400 mètres.']);
      browser.chimeEnd = Completer<bool>();
      final cut = output.say('Zone de danger.', chime: true);
      await output.stop();
      expect(await cut, isFalse);
      expect(browser.spoken, ['Radar dans 400 mètres.']);
    });

    test('without Web Audio, the voice still speaks, without the chime', () async {
      final browser = FakeBrowser([(lang: 'fr-FR', local: true, isDefault: true)], webAudio: false);
      final output = BrowserVoiceOutput(browser, chime: _wav);
      expect(await output.prepare(RouteLanguage.fr), VoiceReadiness.ready);
      expect(output.chimes, isFalse);
      await output.say('Radar dans 400 mètres.', chime: true);
      expect(browser.chimesPlayed, 0);
      expect(browser.spoken, ['Radar dans 400 mètres.']);
    });
  });

  test('a device with no voice and no sound (Windows) says nothing and plays nothing', () async {
    const output = SilentVoice();
    expect(await output.prepare(RouteLanguage.fr), VoiceReadiness.none);
    expect(output.chimes, isFalse);
    expect(await output.say('Radar dans 400 mètres.', chime: true), isFalse);
  });
}
