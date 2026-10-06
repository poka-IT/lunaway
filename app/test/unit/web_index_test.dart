import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The web build runs under the Content-Security-Policy of /app/
/// (infra/caddy/lunaway.net.caddy): `script-src 'self' 'wasm-unsafe-eval'`
/// refuses inline scripts and inline event handlers, and the app may load
/// scripts and fonts from its own origin only. tool/web/csp_check.py proves
/// the whole build in a browser; these checks hold the files in between.
void main() {
  final html = File('web/index.html').readAsStringSync();
  // Comments may quote markup; only live markup counts.
  final markup = html.replaceAll(RegExp(r'<!--[\s\S]*?-->'), '');
  final scripts = RegExp(
    r'<script\b([^>]*)>([\s\S]*?)</script\s*>',
    caseSensitive: false,
  ).allMatches(markup).toList();
  String? srcOf(RegExpMatch script) =>
      RegExp(r'''\bsrc\s*=\s*["']([^"']*)["']''').firstMatch(script.group(1)!)?.group(1);

  group('web/index.html under the production CSP', () {
    test('has no inline script', () {
      expect(scripts, isNotEmpty);
      for (final s in scripts) {
        expect(srcOf(s), isNotNull, reason: 'inline <script${s.group(1)}> is refused by the CSP');
        expect(s.group(2)!.trim(), isEmpty, reason: 'a script with src carries no inline body');
      }
    });

    test('has no inline event handler attribute nor javascript: URL', () {
      final tags = RegExp('<[a-zA-Z][^>]*>').allMatches(markup).map((m) => m.group(0)!);
      for (final tag in tags) {
        expect(
          RegExp(r'\son[a-z]+\s*=', caseSensitive: false).hasMatch(tag),
          isFalse,
          reason: 'event handler attribute in $tag',
        );
        expect(tag.toLowerCase(), isNot(contains('javascript:')), reason: tag);
      }
    });

    test('loads every script from its own origin, from a file in web/', () {
      for (final s in scripts) {
        final src = srcOf(s)!;
        final uri = Uri.parse(src);
        expect(uri.hasScheme || src.startsWith('//'), isFalse, reason: '$src leaves the origin');
        expect(File('web/${uri.path}').existsSync(), isTrue, reason: 'web/${uri.path} is missing');
      }
    });

    test('removes the loading screen from a script it loads', () {
      expect(markup, contains('id="splash"'));
      final loaded = scripts.map(
        (s) => File('web/${Uri.parse(srcOf(s)!).path}').readAsStringSync(),
      );
      expect(
        loaded.any(
          (js) => js.contains('flutter-first-frame') && js.contains("getElementById('splash')"),
        ),
        isTrue,
        reason: 'the fixed splash covers the app and eats clicks unless a script removes it',
      );
    });
  });

  group('web fallback fonts', () {
    final bootstrap = File('web/flutter_bootstrap.js').readAsStringSync();
    final hosted = Directory('web/fonts')
        .listSync(recursive: true)
        .whereType<File>()
        .map((f) => f.path.replaceAll(r'\', '/').substring('web/fonts/'.length))
        .toList();

    test('the engine is told to fetch them from our origin', () {
      expect(bootstrap, contains('{{flutter_js}}'));
      expect(bootstrap, contains('{{flutter_build_config}}'));
      expect(bootstrap, contains("fontFallbackBaseUrl: new URL('fonts/', document.baseURI).href"));
    });

    test('cover Latin, Greek and Cyrillic (Noto Sans) and symbols, each with its licence', () {
      for (final family in ['notosans', 'notosanssymbols', 'notosanssymbols2']) {
        expect(hosted.where((p) => p.startsWith('$family/v')), isNotEmpty, reason: family);
        expect(hosted, contains('$family/OFL.txt'));
      }
    });

    test('sit at the paths the pinned web engine requests', () {
      final data = _engineFontData();
      if (data == null) {
        markTestSkipped('Flutter SDK sources not found next to the test runner');
        return;
      }
      final requested = RegExp(r"'([a-z0-9]+/v\d+/[A-Za-z0-9_.-]+\.woff2)'")
          .allMatches(data)
          .map((m) => m.group(1))
          .toSet();
      final fonts = hosted.where((p) => p.endsWith('.woff2')).toList();
      expect(fonts, isNotEmpty);
      for (final font in fonts) {
        // A Flutter upgrade that moves a font to a new version leaves this
        // file unused: the engine would ask for a path we do not serve.
        expect(
          requested,
          contains(font),
          reason: 'web/fonts/$font is not requested by this engine',
        );
      }
    });
  });
}

/// font_fallback_data.dart of the Flutter SDK running the test, which lists
/// the Noto files the web engine fetches by relative path.
String? _engineFontData() {
  final roots = <String>[
    ?Platform.environment['FLUTTER_ROOT'],
    // flutter_tester lives in <root>/bin/cache/artifacts/engine/<platform>/.
    for (
      var dir = File(Platform.resolvedExecutable).parent;
      dir.parent.path != dir.path;
      dir = dir.parent
    )
      dir.path,
  ];
  for (final root in roots) {
    final file = File('$root/engine/src/flutter/lib/web_ui/lib/src/engine/font_fallback_data.dart');
    if (file.existsSync()) return file.readAsStringSync();
  }
  return null;
}
