// CLI tool: print() is the intended output channel here, not logging.
// ignore_for_file: avoid_print
//
// structure_check: the architectural invariants of AGENTS.md that a grep can
// hold, in one gate. Each rule prints the file, the line, and what to do
// instead, so a failure is its own fix instruction.
//
//   fvm dart tool/structure_check.dart      # from the repository root; exits 1 on a breach
//
// Dependency-free (dart:io only) so it runs before `pub get`, in a git hook
// and in CI.
//
// Two files next to this one hold the data a rule needs:
//   - tool/allowed_hosts.txt: every host a URL literal in app/lib may name.
//     An app that talks to a new host is a privacy event; adding a line there
//     is a reviewed decision, not a side effect of a feature.
//   - tool/structure_ratchet.json: occurrences that predate a rule, per file.
//     A rule holds NEW occurrences at zero and lets a file shrink; it never
//     lets a file grow. It is empty and should stay so.

import 'dart:convert';
import 'dart:io';

const _hostsFile = 'tool/allowed_hosts.txt';
const _ratchetFile = 'tool/structure_ratchet.json';
const _appLib = 'app/lib/';

class _Hit {
  _Hit(this.file, this.line, this.text);
  final String file;
  final int line;
  final String text;
  @override
  String toString() => '$file:$line: ${text.trim()}';
}

class _Rule {
  const _Rule(this.id, this.why, this.fix, this.find);
  final String id;
  final String why;
  final String fix;
  final List<_Hit> Function(List<_Source>) find;
}

class _Source {
  _Source(this.path, this.lines) : code = _stripComments(lines);
  final String path;
  final List<String> lines;
  final List<String> code;

  bool under(String prefix) => path.startsWith(prefix);
  bool get generated => path.endsWith('.g.dart') || path.endsWith('.freezed.dart');
}

/// Blanks `//` comments so a rule quoted in a comment never trips it. Strings
/// are kept: a URL in a string is exactly what the host rule reads.
List<String> _stripComments(List<String> lines) {
  return lines.map((l) {
    var inSingle = false;
    var inDouble = false;
    for (var i = 0; i < l.length - 1; i++) {
      final c = l[i];
      if (c == r'\') {
        i++;
        continue;
      }
      if (c == "'" && !inDouble) inSingle = !inSingle;
      if (c == '"' && !inSingle) inDouble = !inDouble;
      if (!inSingle && !inDouble && c == '/' && l[i + 1] == '/') return l.substring(0, i);
    }
    return l;
  }).toList();
}

/// Lines of [sources] matching [re], minus those matching [unless]. Matching
/// is per line, so a rule anchors on a token the formatter cannot split.
List<_Hit> _grep(List<_Source> sources, RegExp re, {bool Function(_Source)? where, RegExp? unless}) {
  final hits = <_Hit>[];
  for (final s in sources) {
    if (where != null && !where(s)) continue;
    for (var i = 0; i < s.code.length; i++) {
      if (!re.hasMatch(s.code[i])) continue;
      if (unless != null && unless.hasMatch(s.code[i])) continue;
      hits.add(_Hit(s.path, i + 1, s.lines[i]));
    }
  }
  return hits;
}

final _rules = <_Rule>[
  _Rule(
    'no-legacy-provider',
    'Riverpod 3 state goes through generated providers (@riverpod); the legacy provider types and package:provider are out.',
    'Declare the provider with @riverpod / @Riverpod(keepAlive: true) and a Notifier class or a function (see .claude/rules/riverpod.md).',
    (s) => _grep(
      s,
      RegExp(
        r'package:provider/|riverpod/legacy\.dart|\bStateNotifierProvider\b|\bChangeNotifierProvider\b|\bStateProvider\b',
      ),
      where: (x) => x.under(_appLib) && !x.generated,
    ),
  ),
  _Rule(
    'no-print',
    'print() bypasses the logger and its levels.',
    "Use a Logger from package:logging (`final _log = Logger('feature');`).",
    (s) => _grep(s, RegExp(r'(?<![\w.$])print\('), where: (x) => x.under(_appLib) && !x.generated),
  ),
  _Rule(
    'allowed-hosts',
    'Every host the app may talk to is listed in $_hostsFile; a new host is a reviewed decision.',
    'Add the host to $_hostsFile in the same commit, with a one-line reason, or drop the URL.',
    _unknownHosts,
  ),
];

final _hostRe = RegExp(r'''https?://(?:[^\s'"@/]+@)?([A-Za-z0-9.-]+\.[A-Za-z]{2,})''');

List<_Hit> _unknownHosts(List<_Source> sources) {
  final entries = File(_hostsFile).existsSync()
      ? File(_hostsFile).readAsLinesSync().map((l) => l.split('#').first.trim()).where((l) => l.isNotEmpty).toList()
      : <String>[];
  final allowed = entries.where((e) => !e.startsWith('file:')).toSet();
  final exemptFiles = entries.where((e) => e.startsWith('file:')).map((e) => e.substring(5).trim()).toSet();
  final hits = <_Hit>[];
  for (final s in sources) {
    if (!s.under(_appLib) || exemptFiles.contains(s.path)) continue;
    for (var i = 0; i < s.code.length; i++) {
      for (final m in _hostRe.allMatches(s.code[i])) {
        final host = m.group(1)!.toLowerCase();
        final ok = allowed.any(
          (a) => a.startsWith('*.') ? host.endsWith(a.substring(1)) || host == a.substring(2) : host == a,
        );
        if (!ok) hits.add(_Hit(s.path, i + 1, '$host  <- ${s.lines[i].trim()}'));
      }
    }
  }
  return hits;
}

void main(List<String> args) {
  if (!File('AGENTS.md').existsSync() || !Directory(_appLib).existsSync()) {
    stderr.writeln('structure_check: run it from the repository root.');
    exit(2);
  }
  final sources = <_Source>[];
  for (final f in Directory(_appLib).listSync(recursive: true).whereType<File>()) {
    if (!f.path.endsWith('.dart')) continue;
    sources.add(_Source(f.path.replaceAll(r'\', '/'), f.readAsLinesSync()));
  }

  final ratchet = _loadRatchet();
  var failed = false;
  final tightenable = <String>[];

  for (final rule in _rules) {
    final byFile = <String, List<_Hit>>{};
    for (final h in rule.find(sources)) {
      byFile.putIfAbsent(h.file, () => []).add(h);
    }
    final allowedByFile = ratchet[rule.id] ?? const <String, int>{};
    final breaches = <_Hit>[];
    for (final e in byFile.entries) {
      final allowed = allowedByFile[e.key] ?? 0;
      if (e.value.length > allowed) breaches.addAll(e.value);
      if (allowed > 0 && e.value.length < allowed) {
        tightenable.add('${rule.id}: ${e.key} has ${e.value.length} occurrence(s), ratchet says $allowed: lower it.');
      }
    }
    for (final e in allowedByFile.entries) {
      if (!byFile.containsKey(e.key)) tightenable.add('${rule.id}: ${e.key} is clean, remove its ratchet entry.');
    }
    if (breaches.isNotEmpty) {
      failed = true;
      stderr.writeln('structure_check [${rule.id}]: ${rule.why}');
      for (final h in breaches) {
        stderr.writeln('  $h');
      }
      stderr
        ..writeln('  Fix: ${rule.fix}')
        ..writeln();
    }
  }

  for (final t in tightenable) {
    print('note: $t');
  }
  if (failed) {
    stderr.writeln('structure_check: breach. Rules: AGENTS.md, section "Binding rules".');
    exit(1);
  }
  print('structure_check: OK (${_rules.length} rules, ${sources.length} files).');
}

Map<String, Map<String, int>> _loadRatchet() {
  final f = File(_ratchetFile);
  if (!f.existsSync()) return {};
  final decoded = json.decode(f.readAsStringSync()) as Map<String, dynamic>;
  return decoded.map(
    (rule, files) => MapEntry(rule, (files as Map<String, dynamic>).map((k, v) => MapEntry(k, v as int))),
  );
}
