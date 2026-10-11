import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

/// How long an idle connection to a host stays open. dart:io closes one
/// after 15 s: 20 s spent on a place's card, the preview's first request
/// then paid a new connection (name lookup, TCP and TLS), 0.8 to 2.4 s on
/// the emulator against 0.09 s on the open one
/// (`plan/research/125-calcul-itineraire.md`). Under the 2 minutes the
/// API's Caddy keeps one (`infra/caddy/Caddyfile`), so the app does not
/// send on a connection the server has just closed.
const connectionIdle = Duration(seconds: 100);

/// The dart:io client under [appHttpClient].
HttpClient deviceHttpClient() => HttpClient()..idleTimeout = connectionIdle;

http.Client appHttpClient() => IOClient(deviceHttpClient());
