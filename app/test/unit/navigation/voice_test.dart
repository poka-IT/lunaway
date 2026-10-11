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
  new(this.list, this.status, {this.chimeError, this.engine = true});

  final List<PlatformVoiceInfo> list;
  final PlatformLanguageStatus status;

  /// Thrown when the chime is handed over: an older platform side.
  final Exception? chimeError;

  /// Whether the device has a speech engine. Without one, Android answers
  /// `unavailable` to all that needs it, and plays the chime alone.
  final bool engine;
  final List<Uint8List> chimesSet = [];
  final List<({String text, bool chime})> spoken = [];

  static final _noEngine = PlatformException(
    code: 'unavailable',
    message: 'no speech engine on this device',
  );

  /// How many times the voices were listed.
  int listings = 0;

  /// A single engine, unnamed, as on iOS and macOS.
  @override
  Future<List<PlatformEngineInfo>> engines() async => throw MissingPluginException('engines');

  @override
  Future<void> refresh() async => throw MissingPluginException('refresh');

  @override
  Future<List<PlatformVoiceInfo>> voices(String language, {String? engine}) async {
    listings++;
    return this.engine ? list : throw _noEngine;
  }

  @override
  Future<PlatformLanguageStatus> languageStatus(String language, {String? engine}) async =>
      this.engine ? status : throw _noEngine;

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
    if (!engine && text.isNotEmpty) throw _noEngine;
    spoken.add((text: text, chime: chime));
    return true;
  }
}

/// An engine of a [FakeDevice]: its voices and its word on each language,
/// by language code (`fr`) and by tag (`fr-FR`).
final class FakeEngine {
  new(
    this.name, {
    String? label,
    this.voices = const {},
    this.status = const {},
    this.starts = true,
    this.answers = true,
  }) : label = label ?? name;

  final String name;
  final String label;
  Map<String, List<PlatformVoiceInfo>> voices;
  final Map<String, PlatformLanguageStatus> status;

  /// False: binding it fails, as Android answers for a broken engine.
  final bool starts;

  /// False: it never answers.
  final bool answers;
}

/// An Android device with [installed] engines, the first one the default.
final class FakeDevice extends PlatformVoice {
  new(this.installed);

  final List<FakeEngine> installed;

  /// What the app asked, in order.
  final List<String> calls = [];

  /// The engines whose voices were listed.
  final List<String> asked = [];

  /// The engine the app speaks with.
  String? used;
  final List<String?> installedFrom = [];
  final List<String?> spokenWith = [];
  final List<String> spokenIn = [];

  FakeEngine _engine(String? name) =>
      installed.firstWhere((e) => e.name == (name ?? installed.first.name));

  @override
  Future<List<PlatformEngineInfo>> engines() async {
    calls.add('engines');
    return [
      for (final (i, e) in installed.indexed)
        PlatformEngineInfo(name: e.name, label: e.label, isDefault: i == 0),
    ];
  }

  @override
  Future<List<PlatformVoiceInfo>> voices(String language, {String? engine}) async {
    final e = _engine(engine);
    calls.add('voices ${e.name}');
    asked.add(e.name);
    if (!e.answers) await Completer<void>().future;
    if (!e.starts) throw PlatformException(code: 'unavailable', message: 'no speech engine');
    return e.voices[language] ?? const [];
  }

  @override
  Future<PlatformLanguageStatus> languageStatus(String language, {String? engine}) async =>
      _engine(engine).status[language] ?? PlatformLanguageStatus.notSupported;

  @override
  Future<void> useEngine(String? engine) async {
    calls.add('use $engine');
    used = engine;
  }

  @override
  Future<void> refresh() async => calls.add('refresh');

  @override
  Future<bool> setChime(Uint8List wav) async => true;

  @override
  Future<bool> speak(
    String text, {
    required String language,
    String? voiceId,
    double rate = 1,
    bool chime = false,
  }) async {
    spokenWith.add(voiceId);
    spokenIn.add(language);
    return true;
  }

  @override
  Future<bool> installVoiceData({String? engine}) async {
    installedFrom.add(engine);
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

    test("of the language's own country, then of the language alone, before another's", () {
      final picked = pickVoice([
        voice('es-419', locale: 'es-MX', quality: 400),
        voice('es', locale: 'es'),
      ], preferred: 'es-ES');
      expect(picked?.id, 'es', reason: "eSpeak NG's voices of Spanish");
      expect(
        pickVoice([
          voice('es', locale: 'es'),
          voice('es-es', locale: 'es-ES'),
        ], preferred: 'es-ES')?.id,
        'es-es',
      );
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

  test('an engine that lists no voice but speaks the language on the device is taken at its '
      'word', () async {
    final platform = FakePlatformVoice(const [], PlatformLanguageStatus.available);
    final output = PlatformVoiceOutput(voice: platform, chime: _wav);
    expect(await output.prepare(RouteLanguage.en), VoiceReadiness.ready);
    await output.say('Turn right.');
    expect(platform.spoken.single.text, 'Turn right.');
  });

  test("one that speaks it through its vendor's server only means a voice to download", () async {
    final output = PlatformVoiceOutput(
      voice: FakePlatformVoice(const [], PlatformLanguageStatus.network),
      chime: _wav,
    );
    expect(await output.prepare(RouteLanguage.en), VoiceReadiness.missingData);
  });

  group('a device with several engines', () {
    const samsung = 'com.samsung.SMT';
    const google = 'com.google.android.tts';

    test('a voice installed in another engine than the default is found, and speaks', () async {
      final device = FakeDevice([
        FakeEngine(
          samsung,
          voices: {
            'fr': [voice('fr-FR-SMTf00', installed: false)],
          },
        ),
        FakeEngine(
          google,
          voices: {
            'fr': [voice('fr-fr-x-frc-local'), voice('fr-fr-x-frc-network', network: true)],
          },
        ),
      ]);
      final output = PlatformVoiceOutput(voice: device, chime: _wav);
      expect(await output.prepare(RouteLanguage.fr), VoiceReadiness.ready);
      expect(device.used, google);
      await output.say('Tournez à droite.');
      expect(device.spokenWith, ['fr-fr-x-frc-local']);
    });

    test('the default engine speaks when it has the voice, and no other is asked', () async {
      final device = FakeDevice([
        FakeEngine(
          samsung,
          voices: {
            'fr': [voice('fr-FR-SMTf00')],
          },
        ),
        FakeEngine(
          google,
          voices: {
            'fr': [voice('fr-fr-x-frc-local', quality: 500)],
          },
        ),
      ]);
      final output = PlatformVoiceOutput(voice: device, chime: _wav);
      expect(await output.prepare(RouteLanguage.fr), VoiceReadiness.ready);
      expect(device.used, samsung);
      expect(device.asked, [samsung]);
    });

    test("with no voice anywhere, the download offered is the default engine's, and its own "
        'installer opens', () async {
      final device = FakeDevice([
        FakeEngine(
          samsung,
          label: 'Moteur Samsung',
          status: {'fr-FR': PlatformLanguageStatus.missingData},
        ),
        FakeEngine(
          google,
          voices: {
            'fr': [voice('fr-fr-x-frc-local', installed: false)],
          },
        ),
      ]);
      final output = PlatformVoiceOutput(voice: device, chime: _wav);
      expect(await output.prepare(RouteLanguage.fr), VoiceReadiness.missingData);
      expect(output.installEngine, 'Moteur Samsung');
      expect(await output.installVoices(), isTrue);
      expect(device.installedFrom, [samsung]);
    });

    test('a default engine without the language leaves the download to one that has it', () async {
      final device = FakeDevice([
        FakeEngine('com.github.olga_yakovleva.rhvoice.android', label: 'RHVoice'),
        FakeEngine(
          google,
          label: 'Google',
          voices: {
            'fr': [voice('fr-fr-x-frc-local', installed: false)],
          },
        ),
      ]);
      final output = PlatformVoiceOutput(voice: device, chime: _wav);
      expect(await output.prepare(RouteLanguage.fr), VoiceReadiness.missingData);
      expect(output.installEngine, 'Google');
      await output.installVoices();
      expect(device.installedFrom, [google]);
    });

    test(
      "no engine with the language: no voice, and the installer is the system's choice",
      () async {
        final device = FakeDevice([FakeEngine('com.github.olga_yakovleva.rhvoice.android')]);
        final output = PlatformVoiceOutput(voice: device, chime: _wav);
        expect(await output.prepare(RouteLanguage.fr), VoiceReadiness.none);
        expect(output.installEngine, isNull);
      },
    );

    test('an engine that does not start is passed over', () async {
      final device = FakeDevice([
        FakeEngine(samsung, starts: false),
        FakeEngine(
          google,
          voices: {
            'fr': [voice('fr-fr-x-frc-local')],
          },
        ),
      ]);
      final output = PlatformVoiceOutput(voice: device, chime: _wav);
      expect(await output.prepare(RouteLanguage.fr), VoiceReadiness.ready);
      expect(device.used, google);
    });

    test('so is one that never answers, after a while', () {
      fakeAsync((async) {
        final device = FakeDevice([
          FakeEngine(samsung, answers: false),
          FakeEngine(
            google,
            voices: {
              'fr': [voice('fr-fr-x-frc-local')],
            },
          ),
        ]);
        final output = PlatformVoiceOutput(voice: device, chime: _wav);
        VoiceReadiness? readiness;
        unawaited(output.prepare(RouteLanguage.fr).then((r) => readiness = r));
        async.elapse(PlatformVoiceOutput.engineWait - const Duration(milliseconds: 100));
        expect(readiness, isNull);
        async.elapse(const Duration(milliseconds: 200));
        expect(readiness, VoiceReadiness.ready);
        expect(device.used, google);
      });
    });

    test(
      'a fresh look lets go of the engines first, and sees what was installed meanwhile',
      () async {
        final samsungEngine = FakeEngine(
          samsung,
          voices: {
            'fr': [voice('fr-FR-SMTf00', installed: false)],
          },
        );
        final device = FakeDevice([samsungEngine]);
        final output = PlatformVoiceOutput(voice: device, chime: _wav);
        expect(await output.prepare(RouteLanguage.fr), VoiceReadiness.missingData);
        samsungEngine.voices = {
          'fr': [voice('fr-FR-SMTf00')],
        };
        expect(await output.prepare(RouteLanguage.fr, fresh: true), VoiceReadiness.ready);
        expect(device.calls, [
          'engines',
          'voices $samsung',
          'refresh',
          'engines',
          'voices $samsung',
          'use $samsung',
        ]);
      },
    );

    test('each of the six languages finds its voice in the engine that has it', () async {
      for (final language in RouteLanguage.values) {
        final code = language.name;
        final device = FakeDevice([
          FakeEngine(samsung),
          // eSpeak NG names some voices by language alone.
          FakeEngine(
            'com.reecedunn.espeak',
            voices: {
              code: [voice('espeak-$code', locale: code)],
            },
          ),
        ]);
        final output = PlatformVoiceOutput(voice: device, chime: _wav);
        expect(await output.prepare(language), VoiceReadiness.ready, reason: code);
        expect(device.used, 'com.reecedunn.espeak', reason: code);
        await output.say('Bonjour.');
        expect(device.spokenWith, ['espeak-$code'], reason: code);
        expect(device.spokenIn, [code], reason: 'its own tag');
      }
    });
  });

  test("the preview's warm-up and the start share one listing of the voices", () async {
    final platform = FakePlatformVoice([voice('local')], PlatformLanguageStatus.available);
    final output = PlatformVoiceOutput(voice: platform, chime: _wav);
    final warm = output.prepare(RouteLanguage.fr);
    final start = output.prepare(RouteLanguage.fr);
    expect(await warm, VoiceReadiness.ready);
    expect(await start, VoiceReadiness.ready);
    expect(platform.listings, 1, reason: 'one listing at a time for a language');
    expect(await output.prepare(RouteLanguage.fr), VoiceReadiness.ready);
    expect(platform.listings, 2, reason: 'listed again once the last one is over');
  });

  test('nor one that does not know the language', () async {
    final output = PlatformVoiceOutput(
      voice: FakePlatformVoice(const [], PlatformLanguageStatus.notSupported),
      chime: _wav,
    );
    expect(await output.prepare(RouteLanguage.en), VoiceReadiness.none);
  });

  group('the chime on a phone or a Mac', () {
    test('on a phone without a speech engine, an alert asks for the chime alone, and gets it', () {
      fakeAsync((async) {
        final platform = FakePlatformVoice(
          const [],
          PlatformLanguageStatus.notSupported,
          engine: false,
        );
        final output = PlatformVoiceOutput(voice: platform, chime: _wav);
        VoiceReadiness? readiness;
        unawaited(output.prepare(RouteLanguage.fr).then((r) => readiness = r));
        async.flushMicrotasks();
        expect(readiness, VoiceReadiness.none);
        expect(output.chimes, isTrue, reason: 'handed over without an engine');
        final queue = VoiceQueue(output: output, now: () => DateTime.utc(2026))
          ..ready = readiness == VoiceReadiness.ready
          ..say('Tournez à droite.', kind: SpeechKind.maneuver, key: 'm1')
          ..say('Radar dans 400 mètres.', kind: SpeechKind.alert, key: 'a1');
        async.elapse(const Duration(seconds: 1));
        expect(platform.spoken, [(text: '', chime: true)]);
        queue.close();
      });
    });

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
