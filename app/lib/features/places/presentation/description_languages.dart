import 'package:flutter/material.dart';
import 'package:lunaway/features/places/domain/place_content.dart';
import 'package:lunaway/features/translation/domain/translation.dart';
import 'package:lunaway/features/translation/presentation/translatable_text.dart';
import 'package:lunaway/i18n/strings.g.dart';
import 'package:lunaway/shared/labels.dart';
import 'package:lunaway/shared/theme/tokens.dart';

/// A description's [text], with "Translate" when it is in another language
/// than the reader's and no source wrote it in the reader's: when one did,
/// its chip shows that text, and a translation would only say it again.
class DescriptionText extends StatelessWidget {
  const new({
    required this.item,
    required this.text,
    required this.languages,
    required this.appLanguage,
    this.style,
    super.key,
  });

  final TranslatableItem item;
  final LocalizedText text;

  /// The languages the sources wrote it in (`descriptionLanguages`).
  final List<String> languages;
  final String appLanguage;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    if (text.lang != appLanguage && languages.contains(appLanguage)) {
      return Text.rich(
        TextSpan(text: text.text, locale: Locale(text.lang)),
        style: style,
      );
    }
    return TranslatableText(item: item, text: text.text, lang: text.lang, style: style);
  }
}

/// The languages a description is written in, as small chips under it, the
/// reader's own first: a touch shows the text the source wrote in that
/// language, with no translation between. Nothing when it has one language
/// only; "Translate" stays for a language no source wrote.
class DescriptionLanguageChips extends StatelessWidget {
  const new({required this.languages, required this.selected, required this.onSelected, super.key});

  /// In the order shown (`descriptionLanguages`).
  final List<String> languages;

  /// The language of the text shown.
  final String selected;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    if (languages.length < 2) return const SizedBox.shrink();
    final t = context.t;
    return Padding(
      padding: const EdgeInsets.only(top: Space.xs),
      child: Wrap(
        spacing: Space.xs,
        runSpacing: Space.xs,
        children: [
          for (final lang in languages)
            ChoiceChip(
              // The code, short as the chips of other apps write it; the
              // language's name for a screen reader and on hover.
              label: Text(
                lang.toUpperCase(),
                semanticsLabel: t.place.descriptionIn(language: t.languageName(lang)),
              ),
              tooltip: t.place.descriptionIn(language: t.languageName(lang)),
              selected: lang == selected,
              showCheckmark: false,
              mouseCursor: WidgetStateMouseCursor.clickable,
              onSelected: (_) => onSelected(lang),
            ),
        ],
      ),
    );
  }
}
