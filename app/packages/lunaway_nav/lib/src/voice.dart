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

  /// Supported, but its voice data must be downloaded first.
  missingData,

  /// Not supported by the engine.
  notSupported,
}

/// The device's speech engine, through this package's platform code
/// (Android's `TextToSpeech`, iOS's and macOS's `AVSpeechSynthesizer`),
/// and the chime played before an alert.
class PlatformVoice {
  const PlatformVoice();

  static const _channel = MethodChannel('lunaway_nav/voice');

  /// The voices of [language] (`fr`, `en`).
  Future<List<PlatformVoiceInfo>> voices(String language) async {
    final list = await _channel.invokeListMethod<Object?>('voices', {'language': language});
    return [
      for (final v in list ?? const <Object?>[])
        if (v is Map<Object?, Object?>) PlatformVoiceInfo.fromMap(v),
    ];
  }

  /// Whether the engine speaks [language] now.
  Future<PlatformLanguageStatus> languageStatus(String language) async {
    final status = await _channel.invokeMethod<String>('languageStatus', {'language': language});
    return PlatformLanguageStatus.values.asNameMap()[status] ?? PlatformLanguageStatus.notSupported;
  }

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

  /// Opens the system's page that installs voice data; false where there is
  /// none (iOS).
  Future<bool> installVoiceData() async =>
      await _channel.invokeMethod<bool>('installVoiceData') ?? false;
}
