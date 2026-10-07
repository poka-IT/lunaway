import 'package:http/http.dart' as http;
import 'package:lunaway/core/config/app_config.dart';
import 'package:lunaway/core/database/cache_database.dart';
import 'package:lunaway/core/database/user_database.dart';
import 'package:lunaway/shared/images/image_fetcher.dart';
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
CacheDatabase cacheDatabase(Ref ref) {
  final db = CacheDatabase.open(demo: ref.watch(appConfigProvider).demo);
  ref.onDispose(db.close);
  return db;
}

// keepAlive: one database connection for the whole run, as above.
@Riverpod(keepAlive: true)
UserDatabase userDatabase(Ref ref) {
  final db = UserDatabase.open(demo: ref.watch(appConfigProvider).demo);
  ref.onDispose(db.close);
  return db;
}

// keepAlive: one HTTP client reuses its connections across requests. A demo
// build replaces it in main with the in-process demo API, which answers the
// GraphQL operations and the photos.
@Riverpod(keepAlive: true)
http.Client httpClient(Ref ref) {
  final client = http.Client();
  ref.onDispose(client.close);
  return client;
}

// keepAlive: derived from two constants of the run.
@Riverpod(keepAlive: true)
String userAgent(Ref ref) => AppConfig.userAgent(ref.watch(appVersionProvider));

/// Downloads the photos of the API's image proxy.
// keepAlive: it remembers which proxied photos may not be asked for yet,
// across every place opened.
@Riverpod(keepAlive: true)
ImageFetcher imageFetcher(Ref ref) => ImageFetcher(
  client: ref.watch(httpClientProvider),
  config: ref.watch(appConfigProvider),
  userAgent: ref.watch(userAgentProvider),
  clock: ref.watch(clockProvider),
);

/// The clock, injectable so freshness and "open now" are testable.
// keepAlive: a pure function with no state to release.
@Riverpod(keepAlive: true)
DateTime Function() clock(Ref ref) => DateTime.now;

/// The current time, emitted again at the start of every minute: what a
/// screen showing "open now" or "updated 3 days ago" watches, so the text
/// turns over without a rebuild from elsewhere.
@riverpod
Stream<DateTime> minuteClock(Ref ref) async* {
  final now = ref.watch(clockProvider);
  final ticker = ref.watch(minuteTickerProvider);
  yield now();
  await for (final _ in ticker(now)) {
    yield now();
  }
}

/// Ticks at each change of minute of [now]; replaced in tests by a stream
/// the test drives.
typedef MinuteTicker = Stream<void> Function(DateTime Function() now);

// keepAlive: a pure function with no state to release.
@Riverpod(keepAlive: true)
MinuteTicker minuteTicker(Ref ref) => _wallMinutes;

Stream<void> _wallMinutes(DateTime Function() now) async* {
  while (true) {
    final t = now();
    final next = DateTime(t.year, t.month, t.day, t.hour, t.minute + 1);
    await Future<void>.delayed(next.difference(t));
    yield null;
  }
}
