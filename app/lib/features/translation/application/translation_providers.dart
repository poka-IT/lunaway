import 'package:flutter/foundation.dart';
import 'package:logging/logging.dart';
import 'package:lunaway/features/places/application/places_providers.dart';
import 'package:lunaway/features/translation/data/translation_source.dart';
import 'package:lunaway/features/translation/domain/translation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'translation_providers.g.dart';

final _log = Logger('translation');

// keepAlive: a stateless reader over the app-wide client.
@Riverpod(keepAlive: true)
TranslationSource translationSource(Ref ref) =>
    GraphQLTranslationSource(ref.watch(graphQLClientProvider));

/// The translations made during this run, the most recent [capacity]: a
/// review scrolled out of a card's list and back shows its translation
/// again without asking the server. In memory only, gone with the run.
/// Each is kept with the original it was made from, so a review edited
/// since shows no translation of its old text.
final class TranslationMemory {
  new({this.capacity = 300});

  final int capacity;
  // A map literal keeps the order of insertion: the oldest goes first.
  final _kept = <(TranslatableItem, String, String), Translation>{};

  Translation? read(TranslatableItem item, String targetLang, String original) =>
      _kept[(item, targetLang, original)];

  void keep(TranslatableItem item, String targetLang, String original, Translation translation) {
    final key = (item, targetLang, original);
    _kept
      ..remove(key)
      ..[key] = translation;
    while (_kept.length > capacity) {
      _kept.remove(_kept.keys.first);
    }
  }
}

// keepAlive: it holds the run's translations while the cards that showed
// them come and go.
@Riverpod(keepAlive: true)
TranslationMemory translationMemory(Ref ref) => TranslationMemory();

/// Where the translation of one text stands.
@immutable
sealed class TranslationState {
  const new();
}

/// The original shows; nothing was asked, or an automatic attempt failed
/// and the reader is left to ask.
final class NotTranslated extends TranslationState {
  const new();
}

/// The server is translating.
final class Translating extends TranslationState {
  const new();
}

/// The server answered. [showingOriginal]: the reader went back to the
/// original, which the translation is one touch away from.
final class Translated extends TranslationState {
  const new(this.translation, {this.showingOriginal = false});

  final Translation translation;
  final bool showingOriginal;

  @override
  bool operator ==(Object other) =>
      other is Translated &&
      other.translation == translation &&
      other.showingOriginal == showingOriginal;

  @override
  int get hashCode => Object.hash(translation, showingOriginal);
}

/// The translation did not come, and why.
final class TranslationFailed extends TranslationState {
  const new(this.failure);

  final TranslationFailure failure;

  @override
  bool operator ==(Object other) => other is TranslationFailed && other.failure == failure;

  @override
  int get hashCode => failure.hashCode;
}

/// The translation of [item], whose text is [original], into [targetLang],
/// asked when the reader touches "Translate" (or by itself, for a review,
/// when the setting says so). Going back and forth between the original and
/// the translation asks nothing more of the server. The text is part of the
/// key: an edited review starts again from its original.
@riverpod
class ItemTranslation extends _$ItemTranslation {
  @override
  TranslationState build(TranslatableItem item, String targetLang, String original) {
    final kept = ref.watch(translationMemoryProvider).read(item, targetLang, original);
    return kept == null ? const NotTranslated() : Translated(kept);
  }

  /// Asks the server. With [automatic] (the reader's setting asked, not the
  /// reader), a failure the reader could retry leaves the plain button
  /// rather than an error under every review; one that says the text
  /// cannot be translated, or is gone, still shows.
  Future<void> translate({bool automatic = false}) async {
    switch (state) {
      case Translating():
        return;
      case Translated(:final translation):
        state = Translated(translation);
        return;
      case NotTranslated() || TranslationFailed():
        break;
    }
    final source = ref.read(translationSourceProvider);
    final memory = ref.read(translationMemoryProvider);
    state = const Translating();
    TranslationFailure failure;
    try {
      final translation = await source.translate(item, targetLang);
      // Kept even when the card went meanwhile: it shows at once when the
      // review comes back into view.
      memory.keep(item, targetLang, original, translation);
      if (!ref.mounted) return;
      state = Translated(translation);
      return;
    } on TranslationException catch (e) {
      failure = e.failure;
    } on Object catch (e, st) {
      // An answer the app did not expect: the reader sees the server as
      // unavailable rather than a spinner that never stops. The item's ids
      // only, never its text.
      _log.warning('translation of $item failed', e, st);
      failure = TranslationFailure.unavailable;
    }
    if (!ref.mounted) return;
    final quiet =
        automatic &&
        failure != TranslationFailure.unsupported &&
        failure != TranslationFailure.gone;
    state = quiet ? const NotTranslated() : TranslationFailed(failure);
  }

  void showOriginal() {
    if (state case Translated(:final translation)) {
      state = Translated(translation, showingOriginal: true);
    }
  }

  void showTranslation() {
    if (state case Translated(:final translation)) state = Translated(translation);
  }
}
