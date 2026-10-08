import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lunaway/features/offline/application/offline_providers.dart';
import 'package:lunaway/features/translation/application/translation_providers.dart';
import 'package:lunaway/features/translation/domain/translation.dart';
import 'package:lunaway/i18n/strings.g.dart';
import 'package:lunaway/shared/labels.dart';
import 'package:lunaway/shared/theme/app_icons.dart';
import 'package:lunaway/shared/theme/tokens.dart';

/// A review or a description, with what it takes to read it in the app's
/// language when it is written in another one: "Translate", then the
/// translation marked as made automatically, with its original language and
/// the original one touch away. The translation is made by Lunaway's own
/// server; offline the button stays, disabled, with the reason.
///
/// With [autoTranslate] (the reader's setting, for reviews), the
/// translation is asked as soon as the text is built, online only.
class TranslatableText extends ConsumerStatefulWidget {
  const new({
    required this.item,
    required this.text,
    required this.lang,
    this.style,
    this.autoTranslate = false,
    super.key,
  });

  final TranslatableItem item;

  /// The original.
  final String text;

  /// Its language as the source said, or as the server guessed it; null or
  /// `und` when unknown.
  final String? lang;
  final TextStyle? style;
  final bool autoTranslate;

  @override
  ConsumerState<TranslatableText> createState() => _TranslatableTextState();
}

class _TranslatableTextState extends ConsumerState<TranslatableText> {
  /// The translation the setting asked by itself, once: a failure is then
  /// the reader's to retry, not a loop. A provider and not a flag, so a new
  /// text or a new app language is asked again.
  ItemTranslationProvider? _askedFor;

  /// The translation the reader asked for by touching "Translate" or
  /// "Retry": only its notes are announced to a screen reader. A translation
  /// the setting asks for, one kept from earlier, or another text this
  /// widget comes to show, appears without a word.
  ItemTranslationProvider? _touchedFor;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final appLanguage = t.$meta.locale.languageCode;
    final original = primaryLanguage(widget.lang);
    // The language of what is read out, so a screen reader speaks a German
    // review with a German voice.
    Widget text(String data, String? language) => Text.rich(
      TextSpan(text: data, locale: language == null ? null : Locale(language)),
      style: widget.style,
    );
    if (!offersTranslation(lang: widget.lang, text: widget.text, appLanguage: appLanguage)) {
      return text(widget.text, original);
    }
    final provider = itemTranslationProvider(widget.item, appLanguage, widget.text);
    final state = ref.watch(provider);
    final offline = ref.watch(basemapReachabilityProvider) == false;
    if (widget.autoTranslate && _askedFor != provider && !offline && state is NotTranslated) {
      _askedFor = provider;
      // Not during the build: the request changes the provider's state.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(ref.read(provider.notifier).translate(automatic: true));
      });
    }
    final translated = switch (state) {
      Translated(:final translation, showingOriginal: false) when translation.needed => translation,
      _ => null,
    };
    // The server says the original's language when the source did not.
    final originalLanguage = switch (state) {
      Translated(:final translation) => original ?? primaryLanguage(translation.sourceLang),
      _ => original,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (translated != null)
          text(translated.text, appLanguage)
        else
          text(widget.text, originalLanguage),
        _Controls(
          state: state,
          offline: offline,
          announce: _touchedFor == provider,
          onTranslate: () {
            setState(() => _touchedFor = provider);
            unawaited(ref.read(provider.notifier).translate());
          },
          onShowOriginal: ref.read(provider.notifier).showOriginal,
          onShowTranslation: ref.read(provider.notifier).showTranslation,
        ),
      ],
    );
  }
}

/// Whether the translation of [item], whose text is [original], into
/// [targetLang] shows in place of its original: a screen then leaves out
/// what it says of the original's language, which the translation's own
/// line says.
bool showsTranslation(WidgetRef ref, TranslatableItem item, String targetLang, String original) =>
    switch (ref.watch(itemTranslationProvider(item, targetLang, original))) {
      Translated(:final translation, showingOriginal: false) => translation.needed,
      _ => false,
    };

/// The line under the text: the button, the wait, the mark of a translation
/// or why there is none.
class _Controls extends StatelessWidget {
  const new({
    required this.state,
    required this.offline,
    required this.announce,
    required this.onTranslate,
    required this.onShowOriginal,
    required this.onShowTranslation,
  });

  final TranslationState state;
  final bool offline;

  /// Whether the notes are said as they appear: after the reader's touch
  /// only, or every review the setting translates would speak up.
  final bool announce;
  final VoidCallback onTranslate;
  final VoidCallback onShowOriginal;
  final VoidCallback onShowTranslation;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    Widget note(String text) => Text(text, style: muted);
    // What a touch changed, said by a screen reader as it appears: the
    // button that was touched is gone, and with it the reader's focus.
    Widget status(String text) => Semantics(liveRegion: announce, child: note(text));
    final translate = TextButton.icon(
      onPressed: offline ? null : onTranslate,
      icon: const Icon(AppIcons.translate, size: 18),
      label: Text(t.translation.translate),
    );
    final children = switch (state) {
      NotTranslated() => [translate, if (offline) note(t.translation.offline)],
      Translating() => [
        // The height of the button it replaces at least, so the card does
        // not jump; more when the words wrap at a large text size.
        ConstrainedBox(
          constraints: BoxConstraints(minHeight: controlHeight(context, 48)),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox.square(
                dimension: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: Space.s),
              // At a large text size the words wrap rather than run past
              // the card's edge.
              Flexible(child: status(t.translation.translating)),
            ],
          ),
        ),
      ],
      // The original was in the app's language already: nothing to add.
      Translated(:final translation) when !translation.needed => const <Widget>[],
      Translated(:final translation, showingOriginal: false) => [
        status(t.translatedFrom(translation.sourceLang)),
        TextButton(onPressed: onShowOriginal, child: Text(t.translation.showOriginal)),
      ],
      Translated(showingOriginal: true) => [
        TextButton(onPressed: onShowTranslation, child: Text(t.translation.showTranslation)),
      ],
      TranslationFailed(failure: TranslationFailure.unsupported) => [
        status(t.translation.unsupported),
      ],
      TranslationFailed(failure: TranslationFailure.gone) => [status(t.translation.gone)],
      TranslationFailed(:final failure) => [
        status(switch (failure) {
          TranslationFailure.busy => t.translation.busy,
          TranslationFailure.offline => t.translation.failedOffline,
          _ => t.translation.unavailable,
        }),
        TextButton.icon(
          onPressed: offline ? null : onTranslate,
          icon: const Icon(AppIcons.retry, size: 18),
          label: Text(t.common.retry),
        ),
        // A disabled button says why, as before the first touch.
        if (offline) note(t.translation.offline),
      ],
    };
    if (children.isEmpty) return const SizedBox.shrink();
    // A wrap: at a large text size the button goes under the note instead
    // of past the card's edge.
    return Padding(
      padding: const EdgeInsets.only(top: Space.xxs),
      child: Wrap(
        spacing: Space.s,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: children,
      ),
    );
  }
}
