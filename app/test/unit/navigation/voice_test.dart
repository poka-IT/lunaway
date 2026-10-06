import 'package:flutter_test/flutter_test.dart';
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

/// The engine's answers, set by each test.
final class FakePlatformVoice extends PlatformVoice {
  new(this.list, this.status);

  final List<PlatformVoiceInfo> list;
  final PlatformLanguageStatus status;

  @override
  Future<List<PlatformVoiceInfo>> voices(String language) async => list;

  @override
  Future<PlatformLanguageStatus> languageStatus(String language) async => status;
}

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
    );
    expect(await output.prepare(RouteLanguage.fr), VoiceReadiness.missingData);
  });

  test('an engine that lists no voice is not trusted to speak on the device', () async {
    final output = PlatformVoiceOutput(
      voice: FakePlatformVoice(const [], PlatformLanguageStatus.available),
    );
    expect(await output.prepare(RouteLanguage.en), VoiceReadiness.missingData);
  });

  test('nor one that does not know the language', () async {
    final output = PlatformVoiceOutput(
      voice: FakePlatformVoice(const [], PlatformLanguageStatus.notSupported),
    );
    expect(await output.prepare(RouteLanguage.en), VoiceReadiness.none);
  });
}
