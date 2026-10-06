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
//   - tool/allowed_hosts.txt: every host a URL literal in app/lib, app/web,
//     app/assets/map or the app's own packages (app/packages: Dart, Kotlin,
//     Swift, Rust) may name (a protocol-relative `//host`, a
//     `Uri.https('host', ...)` and a Dart `host: '...'` argument count too).
//     An app that talks to a new host is a privacy event; adding a line there
//     is a reviewed decision, not a side effect of a feature. Third-party
//     files listed in tool/harness/vendored.txt are not read.
//   - tool/structure_ratchet.json: occurrences that predate a rule, per file.
//     A rule holds NEW occurrences at zero and lets a file shrink; it never
//     lets a file grow. It is empty and should stay so.

import 'dart:convert';
import 'dart:io';

const _hostsFile = 'tool/allowed_hosts.txt';
const _ratchetFile = 'tool/structure_ratchet.json';
const _vendoredFile = 'tool/harness/vendored.txt';
const _appLib = 'app/lib/';

/// Outside app/lib, the files the browser or the desktop map web view load as
/// code or data: a URL there is a request the app makes just the same.
const _webRoots = ['app/web/', 'app/assets/map/'];
const _webExtensions = ['.js', '.mjs', '.html', '.json', '.css'];

/// The app's own packages: their Dart is held to the same rules as app/lib,
/// and their native code (the platform plugins, the Rust crate) ships in the
/// app, so a host it names is a request the app makes.
const _packagesRoot = 'app/packages/';
const _nativeExtensions = ['.kt', '.kts', '.swift', '.rs'];

/// Build outputs and caches inside a package: never source, sometimes huge.
const _skippedDirs = {'build', '.build', 'target', '.dart_tool', '.gradle', 'Pods'};

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

  /// A JavaScript, CSS, HTML or JSON file: only its block comments (`/* */`,
  /// `<!-- -->`) are blanked, keeping the line numbers. `//` is left alone:
  /// a URL in a template literal, an unquoted CSS `url()` or an HTML
  /// attribute value would look like a line comment to the Dart stripper,
  /// and its host must still be read.
  _Source.web(this.path, String text) : lines = text.split('\n'), code = _blankBlockComments(text).split('\n');

  /// Kotlin, Swift or Rust: block comments, then `//` comments, are blanked.
  /// A Rust lifetime can hide a line comment from the stripper; the host in
  /// it is then read, which errs on the side of the rule.
  _Source.native(this.path, String text)
    : lines = text.split('\n'),
      code = _stripComments(_blankBlockComments(text).split('\n'));

  final String path;
  final List<String> lines;
  final List<String> code;

  bool under(String prefix) => path.startsWith(prefix);
  bool get dart => path.endsWith('.dart');
  bool get generated => path.endsWith('.g.dart') || path.endsWith('.freezed.dart') || path.contains('/frb_generated');
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

/// Replaces `/* ... */` and `<!-- ... -->` with spaces, newlines kept.
String _blankBlockComments(String text) => text.replaceAllMapped(
  RegExp(r'/\*[\s\S]*?\*/|<!--[\s\S]*?-->'),
  (m) => m.group(0)!.replaceAll(RegExp(r'[^\n]'), ' '),
);

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
      where: (x) => x.dart && !x.generated,
    ),
  ),
  _Rule(
    'no-print',
    'print() bypasses the logger and its levels.',
    "Use a Logger from package:logging (`final _log = Logger('feature');`).",
    (s) => _grep(s, RegExp(r'(?<![\w.$])print\('), where: (x) => x.dart && !x.generated),
  ),
  _Rule(
    'allowed-hosts',
    'Every host the app may talk to (app/lib, app/web, app/assets/map, app/packages) is listed in $_hostsFile; a new host is a reviewed decision.',
    'Add the host to $_hostsFile in the same commit, with a one-line reason, or drop the URL.',
    _unknownHosts,
  ),
];

final _hostRe = RegExp(r'''(?:https?|wss?)://(?:[^\s'"@/]+@)?([A-Za-z0-9.-]+\.[A-Za-z]{2,})''');

/// The authority given to `Uri.https(` or `Uri.http(` as a literal, even on
/// the next line; a port is dropped. An interpolated authority cannot be read.
final _uriCtorRe = RegExp(r'''\bUri\.https?\(\s*(['"])([^'"$]*)\1''');
final _domainRe = RegExp(r'^[A-Za-z0-9.-]+\.[A-Za-z]{2,}$');

/// A protocol-relative URL (`//host/path`) in an attribute, a string or a
/// CSS `url()`: the page's own scheme applies, the host is just as remote.
final _schemelessRe = RegExp(r'''(?:^|['"(=\s,])//([A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)*\.[A-Za-z]{2,})''');

/// A literal `host:` argument in Dart (`Uri(scheme: 'https', host: ...)`,
/// `uri.replace(host: ...)`): another way to build a request to a host.
final _hostArgRe = RegExp(r'''\bhost:\s*(['"])([^'"$]*)\1''');

List<_Hit> _unknownHosts(List<_Source> sources) {
  final entries = File(_hostsFile).existsSync()
      ? File(_hostsFile).readAsLinesSync().map((l) => l.split('#').first.trim()).where((l) => l.isNotEmpty).toList()
      : <String>[];
  final allowed = entries.where((e) => !e.startsWith('file:')).toSet();
  final exemptFiles = entries.where((e) => e.startsWith('file:')).map((e) => e.substring(5).trim()).toSet();
  bool ok(String host) =>
      allowed.any((a) => a.startsWith('*.') ? host.endsWith(a.substring(1)) || host == a.substring(2) : host == a);
  final hits = <_Hit>[];
  for (final s in sources) {
    if (exemptFiles.contains(s.path)) continue;
    for (var i = 0; i < s.code.length; i++) {
      for (final m in [..._hostRe.allMatches(s.code[i]), ..._schemelessRe.allMatches(s.code[i])]) {
        final host = m.group(1)!.toLowerCase();
        if (!ok(host)) hits.add(_Hit(s.path, i + 1, '$host  <- ${s.lines[i].trim()}'));
      }
    }
    final code = s.code.join('\n');
    final literalHosts = [..._uriCtorRe.allMatches(code), if (s.path.endsWith('.dart')) ..._hostArgRe.allMatches(code)];
    for (final m in literalHosts) {
      final host = m.group(2)!.split(':').first.toLowerCase();
      if (!_domainRe.hasMatch(host) || ok(host)) continue;
      final line = '\n'.allMatches(code.substring(0, m.start)).length;
      hits.add(_Hit(s.path, line + 1, '$host  <- ${s.lines[line].trim()}'));
    }
  }
  return hits;
}

/// The files under [dir], build outputs and caches left out.
Iterable<File> _walk(Directory dir) sync* {
  for (final e in dir.listSync(followLinks: false)) {
    final name = e.uri.pathSegments.where((p) => p.isNotEmpty).last;
    if (e is Directory && !_skippedDirs.contains(name)) yield* _walk(e);
    if (e is File) yield e;
  }
}

/// Paths of third-party files as their projects publish them; a line ending
/// in / covers a directory.
List<String> _vendored() {
  final f = File(_vendoredFile);
  if (!f.existsSync()) return const [];
  return f.readAsLinesSync().map((l) => l.trim()).where((l) => l.isNotEmpty && !l.startsWith('#')).toList();
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
  final vendored = _vendored();
  if (Directory(_packagesRoot).existsSync()) {
    for (final f in _walk(Directory(_packagesRoot))) {
      final path = f.path.replaceAll(r'\', '/');
      if (path.endsWith('.dart')) {
        sources.add(_Source(path, f.readAsLinesSync()));
      } else if (_nativeExtensions.any(path.endsWith)) {
        sources.add(_Source.native(path, f.readAsStringSync()));
      }
    }
  }
  for (final root in _webRoots) {
    if (!Directory(root).existsSync()) continue;
    for (final f in Directory(root).listSync(recursive: true).whereType<File>()) {
      final path = f.path.replaceAll(r'\', '/');
      final isVendored = vendored.any((v) => v.endsWith('/') ? path.startsWith(v) : path == v);
      if (!_webExtensions.any(path.endsWith) || isVendored) continue;
      sources.add(_Source.web(path, f.readAsStringSync()));
    }
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
