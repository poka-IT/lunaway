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
  /// The automatic translation was asked once for this text: a failure is
  /// then the reader's to retry, not a loop.
  bool _asked = false;

  @override
  void didUpdateWidget(TranslatableText old) {
    super.didUpdateWidget(old);
    if (old.item != widget.item) _asked = false;
  }

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final appLanguage = t.$meta.locale.languageCode;
    final textWidget = Text(widget.text, style: widget.style);
    if (!offersTranslation(lang: widget.lang, text: widget.text, appLanguage: appLanguage)) {
      return textWidget;
    }
    final provider = itemTranslationProvider(widget.item, appLanguage);
    final state = ref.watch(provider);
    final offline = ref.watch(basemapReachabilityProvider) == false;
    if (widget.autoTranslate && !_asked && !offline && state is NotTranslated) {
      _asked = true;
      // Not during the build: the request changes the provider's state.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(ref.read(provider.notifier).translate());
      });
    }
    final shown = switch (state) {
      Translated(:final translation, showingOriginal: false) when translation.needed =>
        translation.text,
      _ => widget.text,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(shown, style: widget.style),
        _Controls(
          state: state,
          offline: offline,
          onTranslate: ref.read(provider.notifier).translate,
          onShowOriginal: ref.read(provider.notifier).showOriginal,
          onShowTranslation: ref.read(provider.notifier).showTranslation,
        ),
      ],
    );
  }
}

/// Whether the translation of [item] into [targetLang] shows in place of its
/// original: a screen then leaves out what it says of the original's
/// language, which the translation's own line says.
bool showsTranslation(WidgetRef ref, TranslatableItem item, String targetLang) =>
    switch (ref.watch(itemTranslationProvider(item, targetLang))) {
      Translated(:final translation, showingOriginal: false) => translation.needed,
      _ => false,
    };

/// The line under the text: the button, the wait, the mark of a translation
/// or why there is none.
class _Controls extends StatelessWidget {
  const new({
    required this.state,
    required this.offline,
    required this.onTranslate,
    required this.onShowOriginal,
    required this.onShowTranslation,
  });

  final TranslationState state;
  final bool offline;
  final VoidCallback onTranslate;
  final VoidCallback onShowOriginal;
  final VoidCallback onShowTranslation;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    Widget note(String text) => Text(text, style: muted);
    final translate = TextButton.icon(
      onPressed: offline ? null : onTranslate,
      icon: const Icon(AppIcons.translate, size: 18),
      label: Text(t.translation.translate),
    );
    final children = switch (state) {
      NotTranslated() => [translate, if (offline) note(t.translation.offline)],
      Translating() => [
        SizedBox(
          height: controlHeight(context, 48),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox.square(
                dimension: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: Space.s),
              note(t.translation.translating),
            ],
          ),
        ),
      ],
      // The original was in the app's language already: nothing to add.
      Translated(:final translation) when !translation.needed => const <Widget>[],
      Translated(:final translation, showingOriginal: false) => [
        note(t.translatedFrom(translation.sourceLang)),
        TextButton(onPressed: onShowOriginal, child: Text(t.translation.showOriginal)),
      ],
      Translated(showingOriginal: true) => [
        TextButton(onPressed: onShowTranslation, child: Text(t.translation.showTranslation)),
      ],
      TranslationFailed(failure: TranslationFailure.unsupported) => [
        note(t.translation.unsupported),
      ],
      TranslationFailed(failure: TranslationFailure.gone) => [note(t.translation.gone)],
      TranslationFailed(:final failure) => [
        note(switch (failure) {
          TranslationFailure.busy => t.translation.busy,
          TranslationFailure.offline => t.translation.failedOffline,
          _ => t.translation.unavailable,
        }),
        TextButton.icon(
          onPressed: offline ? null : onTranslate,
          icon: const Icon(AppIcons.retry, size: 18),
          label: Text(t.common.retry),
        ),
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
