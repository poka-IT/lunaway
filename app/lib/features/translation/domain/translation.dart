import 'package:meta/meta.dart';

/// What the API translates, as `TranslatableKind` names it.
enum TranslatableKind {
  /// A review of Lunaway's community, by its id.
  review('REVIEW'),

  /// A review of another source (the external community source, Mangrove),
  /// by its id.
  externalReview('EXTERNAL_REVIEW'),

  /// One of the place's own descriptions: the place's id, the
  /// description's source and language.
  description('DESCRIPTION'),

  /// A description of an open source: the place's id, the description's
  /// source and language.
  externalDescription('EXTERNAL_DESCRIPTION');

  new(this.wire);

  final String wire;
}

/// A stored text the server can translate, named the way the API names it:
/// the app never sends the text itself, so the server translates only what
/// it holds.
@immutable
final class TranslatableItem {
  const new review(this.id) : kind = TranslatableKind.review, sourceId = null, lang = null;

  const new externalReview(this.id)
    : kind = TranslatableKind.externalReview,
      sourceId = null,
      lang = null;

  const new description({
    required String placeId,
    required String this.sourceId,
    required String this.lang,
  }) : kind = TranslatableKind.description,
       id = placeId;

  const new externalDescription({
    required String placeId,
    required String this.sourceId,
    required String this.lang,
  }) : kind = TranslatableKind.externalDescription,
       id = placeId;

  final TranslatableKind kind;

  /// The review's id, or the place's for a description.
  final String id;

  /// A description's source; null for a review.
  final String? sourceId;

  /// A description's language tag, as the place lists it; null for a review.
  final String? lang;

  @override
  bool operator ==(Object other) =>
      other is TranslatableItem &&
      other.kind == kind &&
      other.id == id &&
      other.sourceId == sourceId &&
      other.lang == lang;

  @override
  int get hashCode => Object.hash(kind, id, sourceId, lang);

  @override
  String toString() => 'TranslatableItem(${kind.wire} $id ${sourceId ?? ''} ${lang ?? ''})';
}

/// A text in the reader's language, as the server made it.
@immutable
final class Translation {
  const new({
    required this.text,
    required this.sourceLang,
    required this.targetLang,
    this.engine,
    this.model,
  });

  /// The translation, or the original when it was in [targetLang] already.
  final String text;

  /// The language of the original, as its source said or as the server
  /// guessed it.
  final String sourceLang;
  final String targetLang;

  /// The engine that translated it; null when nothing needed translating.
  final String? engine;
  final String? model;

  /// The original was in the language asked: there is nothing to show
  /// beside it.
  bool get needed => engine != null;

  @override
  bool operator ==(Object other) =>
      other is Translation &&
      other.text == text &&
      other.sourceLang == sourceLang &&
      other.targetLang == targetLang &&
      other.engine == engine &&
      other.model == model;

  @override
  int get hashCode => Object.hash(text, sourceLang, targetLang, engine, model);
}

/// Why a translation did not come.
enum TranslationFailure {
  /// No model translates this language, or its language is not known: the
  /// app stops offering it.
  unsupported,

  /// The server is busy or the client's quota is spent: worth trying again
  /// in a moment.
  busy,

  /// The translation server is down.
  unavailable,

  /// The text is gone (deleted, hidden) since it was shown.
  gone,

  /// No answer: the device is offline or the network failed.
  offline,
}

/// A failed translation, with why.
final class TranslationException implements Exception {
  const new(this.failure);

  final TranslationFailure failure;

  @override
  String toString() => 'TranslationException(${failure.name})';
}

/// Fewest letters a text without a known language needs before the app
/// offers to translate it: the server cannot tell the language of fewer
/// either (`lunaway_domain::translation`), and a word or a name needs no
/// translation.
const minLettersToTranslate = 12;

/// The primary subtag of a BCP 47 tag, lower case; null for none or `und`.
String? primaryLanguage(String? tag) {
  final primary = tag?.trim().split(RegExp('[-_]')).first.toLowerCase();
  if (primary == null || primary.isEmpty || primary == 'und') return null;
  return primary;
}

/// Whether a text in [lang] is worth offering to translate for a reader of
/// [appLanguage]: its language differs, or it is not known and the text is
/// long enough to have one.
bool offersTranslation({required String? lang, required String text, required String appLanguage}) {
  final primary = primaryLanguage(lang);
  if (primary != null) return primary != appLanguage;
  final letters = text.runes.where((r) {
    final c = String.fromCharCode(r);
    return c.toLowerCase() != c.toUpperCase();
  }).length;
  return letters >= minLettersToTranslate;
}
