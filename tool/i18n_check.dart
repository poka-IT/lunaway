// CLI tool: print() is the intended output channel here, not logging.
// ignore_for_file: avoid_print
//
// i18n_check: the translation gate.
//
//   fvm dart tool/i18n_check.dart      # from the repository root; exits 1 on a breach
//
// For every slang source in app/lib/i18n/ (<locale>.i18n.json):
//   - the same keys as the base locale (en), no more, no fewer;
//   - the same parameters ($name, ${name}) in every translation of a key;
//   - no empty value;
//   - every key read somewhere in app/lib (as `.a.b.c`), else it is dead.
// Plural groups (maps whose keys are one/other/...) are compared as one key:
// languages legitimately use different plural forms.
//
// Dependency-free (dart:io, dart:convert) so it runs before `pub get`.

import 'dart:convert';
import 'dart:io';

const _dir = 'app/lib/i18n';
const _base = 'en';
const _pluralForms = {'zero', 'one', 'two', 'few', 'many', 'other'};
final _param = RegExp(r'\$\{?([A-Za-z_][A-Za-z0-9_]*)\}?');

/// Flattens nested maps into `a.b.c` paths; a plural group is one leaf whose
/// value joins its forms.
Map<String, String> _flatten(Map<String, dynamic> node, [String prefix = '']) {
  final out = <String, String>{};
  node.forEach((rawKey, value) {
    // slang modifiers (`key(plural)`) are not part of the access path.
    final key = rawKey.replaceAll(RegExp(r'\(.*\)$'), '');
    final path = prefix.isEmpty ? key : '$prefix.$key';
    if (value is Map<String, dynamic>) {
      if (value.isNotEmpty && value.keys.every(_pluralForms.contains)) {
        out[path] = value.values.join(' | ');
      } else {
        out.addAll(_flatten(value, path));
      }
    } else {
      out[path] = '$value';
    }
  });
  return out;
}

void main() {
  final dir = Directory(_dir);
  if (!dir.existsSync()) {
    stderr.writeln('i18n_check: $_dir not found; run it from the repository root.');
    exit(2);
  }
  final locales = <String, Map<String, String>>{};
  for (final f in dir.listSync().whereType<File>()) {
    final name = f.uri.pathSegments.last;
    if (!name.endsWith('.i18n.json')) continue;
    final locale = name.substring(0, name.length - '.i18n.json'.length);
    locales[locale] = _flatten(json.decode(f.readAsStringSync()) as Map<String, dynamic>);
  }
  final base = locales[_base];
  if (base == null) {
    stderr.writeln('i18n_check: no base locale file $_dir/$_base.i18n.json.');
    exit(1);
  }

  final problems = <String>[];
  for (final entry in locales.entries) {
    final locale = entry.key;
    final keys = entry.value;
    for (final k in base.keys.where((k) => !keys.containsKey(k))) {
      problems.add('$locale: missing key $k');
    }
    for (final k in keys.keys.where((k) => !base.containsKey(k))) {
      problems.add('$locale: key $k is not in the base locale ($_base)');
    }
    keys.forEach((k, v) {
      if (v.trim().isEmpty) problems.add('$locale: empty value for $k');
      final want = _param.allMatches(base[k] ?? '').map((m) => m.group(1)).toSet();
      final got = _param.allMatches(v).map((m) => m.group(1)).toSet();
      if (base.containsKey(k) && (want.length != got.length || !want.containsAll(got))) {
        problems.add('$locale: $k has parameters $got, the base has $want');
      }
    });
  }

  // Dead keys: every path must be read somewhere in app/lib as `.a.b.c`.
  final code = StringBuffer();
  for (final f in Directory('app/lib').listSync(recursive: true).whereType<File>()) {
    final p = f.path.replaceAll(r'\', '/');
    if (!p.endsWith('.dart') || p.startsWith('$_dir/strings')) continue;
    code.writeln(f.readAsStringSync());
  }
  final source = code.toString();
  for (final k in base.keys) {
    final pattern = RegExp('\\.${RegExp.escape(k)}(?![A-Za-z0-9_])');
    if (!pattern.hasMatch(source)) problems.add('$_base: key $k is read nowhere in app/lib; delete it');
  }

  if (problems.isNotEmpty) {
    stderr.writeln('i18n_check: ${problems.length} problem(s):');
    for (final p in problems) {
      stderr.writeln('  $p');
    }
    stderr.writeln('Fix the JSON in $_dir, then run `fvm dart run slang` in app/ (.claude/rules/translations.md).');
    exit(1);
  }
  print('i18n_check: OK (${locales.length} locales, ${base.length} keys).');
}
