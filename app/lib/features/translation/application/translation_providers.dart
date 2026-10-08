import 'package:flutter/foundation.dart';
import 'package:lunaway/features/places/application/places_providers.dart';
import 'package:lunaway/features/translation/data/translation_source.dart';
import 'package:lunaway/features/translation/domain/translation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'translation_providers.g.dart';

// keepAlive: a stateless reader over the app-wide client.
@Riverpod(keepAlive: true)
TranslationSource translationSource(Ref ref) =>
    GraphQLTranslationSource(ref.watch(graphQLClientProvider));

/// The translations made during this run, the most recent [capacity]: a
/// review scrolled out of a card's list and back shows its translation
/// again without asking the server. In memory only, gone with the run.
final class TranslationMemory {
  new({this.capacity = 300});

  final int capacity;
  // A map literal keeps the order of insertion: the oldest goes first.
  final _kept = <(TranslatableItem, String), Translation>{};

  Translation? read(TranslatableItem item, String targetLang) => _kept[(item, targetLang)];

  void keep(TranslatableItem item, String targetLang, Translation translation) {
    _kept
      ..remove((item, targetLang))
      ..[(item, targetLang)] = translation;
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

/// The original shows; nothing was asked.
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

/// The translation of [item] into [targetLang], asked when the reader
/// touches "Translate" (or by itself, for a review, when the setting says
/// so). Going back and forth between the original and the translation asks
/// nothing more of the server.
@riverpod
class ItemTranslation extends _$ItemTranslation {
  @override
  TranslationState build(TranslatableItem item, String targetLang) {
    final kept = ref.watch(translationMemoryProvider).read(item, targetLang);
    return kept == null ? const NotTranslated() : Translated(kept);
  }

  Future<void> translate() async {
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
    try {
      final translation = await source.translate(item, targetLang);
      // Kept even when the card went meanwhile: it shows at once when the
      // review comes back into view.
      memory.keep(item, targetLang, translation);
      if (!ref.mounted) return;
      state = Translated(translation);
    } on TranslationException catch (e) {
      if (!ref.mounted) return;
      state = TranslationFailed(e.failure);
    }
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
