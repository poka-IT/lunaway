import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunaway/core/http/app_http_client_io.dart';
import 'package:lunaway/core/providers.dart';

/// Records each dart:io client made while it is in force.
final class _Recording extends HttpOverrides {
  final made = <HttpClient>[];

  @override
  HttpClient createHttpClient(SecurityContext? context) {
    final client = super.createHttpClient(context);
    made.add(client);
    return client;
  }
}

void main() {
  // The preview's first request after a while on a place's card reused the
  // open connection instead of paying a new one
  // (`plan/research/125-calcul-itineraire.md`).
  test("an idle connection outlives dart:io's 15 s and dies before the API's Caddy drops it", () {
    expect(deviceHttpClient().idleTimeout, connectionIdle);
    expect(connectionIdle, greaterThan(HttpClient().idleTimeout));
    final caddy = File('../infra/caddy/Caddyfile').readAsStringSync();
    final idle = RegExp(r'^\s*idle (\d+)m$', multiLine: true).firstMatch(caddy);
    expect(idle, isNotNull, reason: 'the server-wide idle timeout of the Caddyfile');
    expect(connectionIdle, lessThan(Duration(minutes: int.parse(idle!.group(1)!))));
  });

  test("the app's requests go through the client that keeps its connections", () {
    final recording = _Recording();
    HttpOverrides.runWithHttpOverrides(() {
      ProviderContainer.test().read(httpClientProvider);
    }, recording);
    expect(recording.made.single.idleTimeout, connectionIdle);
  });
}
