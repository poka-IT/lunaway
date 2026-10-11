import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lunaway/core/http/app_http_client_io.dart';

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
}
