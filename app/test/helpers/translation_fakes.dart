import 'dart:async';

import 'package:lunaway/features/translation/data/translation_source.dart';
import 'package:lunaway/features/translation/domain/translation.dart';

/// A translation server in memory: it answers [translationOf] for every text, or
/// fails with [failure], after [gate] when one is set, and records what it
/// was asked.
final class FakeTranslationSource implements TranslationSource {
  new({this.sourceLang = 'de', this.failure, this.sameLanguage = false});

  /// The language the server says the originals are in.
  String sourceLang;

  /// The next answers fail with it; null answers.
  TranslationFailure? failure;

  /// The originals are in the language asked: the server gives them back.
  bool sameLanguage;

  /// Thrown instead of an answer: what the client did not expect.
  Exception? unexpected;

  /// Holds every answer until completed, to see the wait.
  Completer<void>? gate;

  final List<(TranslatableItem, String)> asked = [];

  /// What the server makes of [item]'s text: a recognisable fake.
  static String translationOf(TranslatableItem item, String targetLang) =>
      '[$targetLang] ${item.kind.wire} ${item.id}';

  @override
  Future<Translation> translate(TranslatableItem item, String targetLang) async {
    asked.add((item, targetLang));
    await gate?.future;
    if (unexpected case final e?) throw e;
    if (failure case final f?) throw TranslationException(f);
    if (sameLanguage) {
      return Translation(text: 'original', sourceLang: targetLang, targetLang: targetLang);
    }
    return Translation(
      text: translationOf(item, targetLang),
      sourceLang: sourceLang,
      targetLang: targetLang,
      engine: 'opus-mt',
      model: '$sourceLang-$targetLang test',
    );
  }
}
