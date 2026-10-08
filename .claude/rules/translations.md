---
paths:
  - "app/lib/i18n/**"
---
# Translations

slang, configured in `app/slang.yaml`: one JSON file per locale in
`app/lib/i18n/` (`en.i18n.json` is the base locale; French carries the
meaning; German, Spanish, Italian and Dutch follow), generated code in
`strings*.g.dart` by `fvm dart run slang` in `app/`. Widgets read
`context.t.<path>`. Register, formats and trade terms of every language:
`docs/translation-glossary.md`.

## Rules

- **A key lands in all six locales in the same commit**, with the same
  placeholders. Gate: `tool/i18n_check.dart` (post-edit hook, pre-commit, CI).
- **No unused key.** A key nothing reads is deleted. Gate: `tool/i18n_check.dart`.
- **Each language reads as written in it**: the register and the terms of
  the glossary (Sie, tú, tu, je), its quotes and number formats, short
  forms on chips and buttons. French carries its typography: accents on
  capitals (`À`, `É`), the apostrophe `'` (U+0027 or U+2019, one of them
  consistently per file), no narrow no-break space required before `:` `?`
  `!`. Never an em dash or en dash, in any language.
- **Keys name the meaning, not the screen position** (`profile.language`, not
  `profileScreen.text2`). Group by feature.
- **Plurals and parameters** use slang's syntax (`"spots(count)": {"one": "...", "other": "..."}`,
  `"hello": "Hello $name"`), never string concatenation in Dart. A language
  slang has no plural rule for gets one in `app/lib/core/plural_rules.dart`
  (Dutch).
- After editing a JSON file, regenerate (`fvm dart run slang`) and commit the
  generated files with it; the edit guard refuses hand edits to them.

## Adding a locale

Add `<code>.i18n.json` with every key, regenerate, then the language reaches
every place that lists the app's languages:

- `_locales` in `tool/i18n_check.dart`, and the picker (`_Language` in
  `profile_screen.dart`);
- the guidance: `RouteLanguage` in the app (`route_settings.dart`) and in
  the API (`routing_types.rs`, then export the schema), which names the
  routing engine's narrative language;
- the map labels: `basemapLanguages` (`basemap_style.dart`), `LANGUAGES` in
  `app/tool/map_style/style.mjs`, the list in `app/web/premap.js`;
- the region packs: `APP_LANGUAGES` in `lunaway-api/src/packs.rs` (a test
  reads this folder);
- iOS and macOS: `CFBundleLocalizations` in each `Info.plist`, an
  `<code>.lproj/InfoPlist.strings` with every permission reason, and the
  file in the Xcode project's `InfoPlist.strings` variant group;
- the glossary, with the register and the terms.

The translation platform refines wording; it does not fill gaps.
