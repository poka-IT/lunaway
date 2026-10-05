---
paths:
  - "app/lib/i18n/**"
---
# Translations

slang, configured in `app/slang.yaml`: one JSON file per locale in
`app/lib/i18n/` (`en.i18n.json` is the base locale, `fr.i18n.json` the
second), generated code in `strings*.g.dart` by `fvm dart run slang` in
`app/`. Widgets read `context.t.<path>`.

## Rules

- **A key lands in every locale in the same commit**, with the same
  placeholders. Gate: `tool/i18n_check.dart` (post-edit hook, pre-commit, CI).
- **No unused key.** A key nothing reads is deleted. Gate: `tool/i18n_check.dart`.
- **French carries its typography**: accents on capitals (`À`, `É`), the
  apostrophe `'` (U+0027 or U+2019, one of them consistently per file), a
  narrow no-break space is not required before `:` `?` `!`. Never an em dash
  or en dash.
- **Keys name the meaning, not the screen position** (`profile.language`, not
  `profileScreen.text2`). Group by feature.
- **Plurals and parameters** use slang's syntax (`"spots(count)": {"one": "...", "other": "..."}`,
  `"hello": "Hello $name"`), never string concatenation in Dart.
- After editing a JSON file, regenerate (`fvm dart run slang`) and commit the
  generated files with it; the edit guard refuses hand edits to them.

## Adding a locale

Add `<code>.i18n.json` with every key, regenerate, add the locale to the
language picker, and to `tool/i18n_check.dart` if it lists locales. The
translation platform refines wording; it does not fill gaps.
