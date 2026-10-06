import 'package:http/http.dart' as http;
import 'package:lunaway/core/config/app_config.dart';
import 'package:lunaway/core/database/app_database.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'providers.g.dart';

// keepAlive: build-time configuration, read by services for the whole run.
@Riverpod(keepAlive: true)
AppConfig appConfig(Ref ref) => AppConfig.fromEnvironment();

/// The version string of the running app, overridden in `main` from the
/// platform; the default serves tests.
// keepAlive: a constant of the run, read by every outbound request.
@Riverpod(keepAlive: true)
String appVersion(Ref ref) => '0.1.0';

// keepAlive: one database connection for the whole run; closing it under a
// listener would break every stream query.
@Riverpod(keepAlive: true)
AppDatabase appDatabase(Ref ref) {
  final db = AppDatabase.open(demo: ref.watch(appConfigProvider).demo);
  ref.onDispose(db.close);
  return db;
}

// keepAlive: one HTTP client reuses its connections across requests.
@Riverpod(keepAlive: true)
http.Client httpClient(Ref ref) {
  final client = http.Client();
  ref.onDispose(client.close);
  return client;
}

// keepAlive: derived from two constants of the run.
@Riverpod(keepAlive: true)
String userAgent(Ref ref) => AppConfig.userAgent(ref.watch(appVersionProvider));

/// The clock, injectable so freshness and "open now" are testable.
// keepAlive: a pure function with no state to release.
@Riverpod(keepAlive: true)
DateTime Function() clock(Ref ref) => DateTime.now;
