import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:lunaway/features/navigation/data/voice_output.dart';
import 'package:lunaway/features/navigation/domain/route_settings.dart';

/// The platform's voice on a real device (Android, iOS, macOS): the chime
/// before an alert plays from the app's asset, and a sentence is answered
/// only once it has been heard, which the guidance's queue waits for
/// before the next one. A stop cuts it and answers at once.
///
///   fvm flutter test integration_test/voice_chime_test.dart -d emulator-5554 --flavor store --no-uninstall
///
/// The sentence needs a voice installed for French or English; without
/// one, the chime alone is checked.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('the chime and a sentence end once played, and a stop cuts a sentence', (
    tester,
  ) async {
    final voice = PlatformVoiceOutput();
    VoiceReadiness? readiness;
    RouteLanguage? language;
    for (final l in [RouteLanguage.fr, RouteLanguage.en]) {
      readiness = await voice.prepare(l);
      language = l;
      if (readiness == VoiceReadiness.ready) break;
    }
    expect(voice.chimes, isTrue, reason: 'the asset reached the platform');

    final watch = Stopwatch()..start();
    expect(await voice.say('', chime: true), isTrue);
    // The chime lasts 300 ms: an answer before it is over would let the
    // next sentence start over it.
    expect(watch.elapsedMilliseconds, greaterThanOrEqualTo(250));
    debugPrint('VOICE chime alone ${watch.elapsedMilliseconds} ms, voice $readiness ($language)');

    if (readiness != VoiceReadiness.ready) return;
    final sentence = language == RouteLanguage.fr
        ? 'Radar dans 400 mètres.'
        : 'Speed camera in 400 metres.';
    watch.reset();
    expect(await voice.say(sentence, chime: true), isTrue);
    expect(watch.elapsedMilliseconds, greaterThan(1000), reason: 'the chime, then the sentence');
    debugPrint('VOICE chime and sentence ${watch.elapsedMilliseconds} ms');

    final long = language == RouteLanguage.fr
        ? 'Attention, gabarit limité par des travaux dans 2 kilomètres. Vérifiez la hauteur.'
        : 'Caution, size limit for roadworks in 2 kilometres. Check the height.';
    final cut = voice.say(long);
    await Future<void>.delayed(const Duration(milliseconds: 700));
    watch.reset();
    await voice.stop();
    expect(await cut, isFalse, reason: 'cut, not said to the end');
    expect(watch.elapsedMilliseconds, lessThan(1000));
  });
}
