import 'package:flutter/services.dart';
import 'package:meta/meta.dart';

/// A voice of the device's speech engine.
@immutable
final class PlatformVoiceInfo {
  const PlatformVoiceInfo({
    required this.id,
    required this.locale,
    required this.networkRequired,
    required this.notInstalled,
    required this.quality,
  });

  factory PlatformVoiceInfo.fromMap(Map<Object?, Object?> map) => PlatformVoiceInfo(
    id: '${map['id']}',
    locale: '${map['locale']}',
    networkRequired: map['networkRequired'] == true,
    notInstalled: map['notInstalled'] == true,
    quality: (map['quality'] as num?)?.toInt() ?? 300,
  );

  /// The engine's name for it.
  final String id;

  /// Its language tag (`fr-FR`).
  final String locale;

  /// It speaks through a server of the engine's vendor: unusable without
  /// network, and the instruction leaves the device.
  final bool networkRequired;

  /// Listed, but its data is not on the device yet.
  final bool notInstalled;

  /// Android's scale: 300 normal, 400 high, 500 very high.
  final int quality;
}

/// Whether the engine speaks a language.
enum PlatformLanguageStatus {
  /// Ready.
  available,

  /// Through its vendor's server only.
  network,

  /// Supported, but its voice data must be downloaded first.
  missingData,

  /// Not supported by the engine.
  notSupported,
}

/// A speech engine of the device (Android): Google's, the maker's, eSpeak
/// NG, RHVoice.
@immutable
final class PlatformEngineInfo {
  const PlatformEngineInfo({required this.name, required this.label, required this.isDefault});

  factory PlatformEngineInfo.fromMap(Map<Object?, Object?> map) => PlatformEngineInfo(
    name: '${map['name']}',
    label: '${map['label']}',
    isDefault: map['isDefault'] == true,
  );

  /// Its package.
  final String name;

  /// Its name as the system's settings show it.
  final String label;

  /// The one chosen in the system's settings.
  final bool isDefault;
}

/// The device's speech engine, through this package's platform code
/// (Android's `TextToSpeech`, iOS's and macOS's `AVSpeechSynthesizer`),
/// and the chime played before an alert.
class PlatformVoice {
  const PlatformVoice();

  static const _channel = MethodChannel('lunaway_nav/voice');

  /// The speech engines of the device, the default one first. Throws a
  /// [MissingPluginException] where the platform has a single engine (iOS,
  /// macOS), and a [PlatformException] where it has none.
  Future<List<PlatformEngineInfo>> engines() async {
    final list = await _channel.invokeListMethod<Object?>('engines');
    return [
      for (final e in list ?? const <Object?>[])
        if (e is Map<Object?, Object?>) PlatformEngineInfo.fromMap(e),
    ];
  }

  /// The voices of [language] (`fr`, `en`) in [engine], the default
  /// engine's when null.
  Future<List<PlatformVoiceInfo>> voices(String language, {String? engine}) async {
    final list = await _channel.invokeListMethod<Object?>('voices', {
      'language': language,
      'engine': engine,
    });
    return [
      for (final v in list ?? const <Object?>[])
        if (v is Map<Object?, Object?>) PlatformVoiceInfo.fromMap(v),
    ];
  }

  /// Whether [engine] (the default one when null) speaks [language] now.
  Future<PlatformLanguageStatus> languageStatus(String language, {String? engine}) async {
    final status = await _channel.invokeMethod<String>('languageStatus', {
      'language': language,
      'engine': engine,
    });
    return PlatformLanguageStatus.values.asNameMap()[status] ?? PlatformLanguageStatus.notSupported;
  }

  /// Speaks from now on with [engine], one of [engines]; null for the
  /// default one. The other engines asked about are let go.
  Future<void> useEngine(String? engine) =>
      _channel.invokeMethod<void>('useEngine', {'engine': engine});

  /// Lets go of every engine, to bind them anew at the next question: what
  /// was installed, or the default engine changed, since shows then. Never
  /// while a sentence is said.
  Future<void> refresh() => _channel.invokeMethod<void>('refresh');

  /// Hands the platform the chime [speak] plays before an alert: the bytes
  /// of a WAV file, kept for the run. True once it can be played.
  Future<bool> setChime(Uint8List wav) async =>
      await _channel.invokeMethod<bool>('setChime', {'wav': wav}) ?? false;

  /// Says [text] in [language] (a tag, `fr-FR`), with the voice [voiceId]
  /// when given, after what was being said; after the chime of [setChime]
  /// when [chime], and an empty [text] then plays the chime alone.
  ///
  /// Completes once it is over: true when said to the end, false when
  /// [stop] cut it or the engine failed.
  Future<bool> speak(
    String text, {
    required String language,
    String? voiceId,
    double rate = 1,
    bool chime = false,
  }) async =>
      await _channel.invokeMethod<bool>('speak', {
        'text': text,
        'language': language,
        'voiceId': voiceId,
        'rate': rate,
        'chime': chime,
      }) ??
      false;

  /// Stops speaking, and the chime: every [speak] still running completes
  /// with false.
  Future<void> stop() => _channel.invokeMethod<void>('stop');

  /// Opens the page of [engine] that installs voice data, or the system's
  /// choice among its engines when null; false where there is none (iOS).
  Future<bool> installVoiceData({String? engine}) async =>
      await _channel.invokeMethod<bool>('installVoiceData', {'engine': engine}) ?? false;
}
