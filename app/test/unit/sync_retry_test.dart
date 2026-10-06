import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunaway/core/geo/geo.dart';
import 'package:lunaway/core/providers.dart';
import 'package:lunaway/features/places/application/places_providers.dart';
import 'package:lunaway/features/places/data/graphql/graphql_client.dart';
import 'package:lunaway/features/places/data/graphql/operations.dart';
import 'package:lunaway/features/places/data/sync/sync_service.dart';

import '../helpers/pump.dart' show MemorySyncStore;

/// What the server does for one request.
sealed class _Answer {
  const new();
}

/// The last page.
final class _Done extends _Answer {
  const new();
}

/// A page announcing more, with the cursor it was asked from (the first
/// one when asked without): a server whose cursor is stuck.
final class _Stuck extends _Answer {
  const new();
}

final class _Fails extends _Answer {
  const new(this.error);

  final Exception error;
}

/// Answers each request with the next of [script], the last one repeating.
final class _ScriptedServer implements ChangesSource {
  new(this.script);

  final List<_Answer> script;
  int requests = 0;

  @override
  Future<ChangeSet> changes({required GeoBounds bbox, required int first, String? since}) async {
    final next = script[requests.clamp(0, script.length - 1)];
    requests++;
    return switch (next) {
      _Done() => const ChangeSet(places: [], deleted: [], cursor: 'end', hasMore: false),
      _Stuck() => ChangeSet(
        places: const [],
        deleted: const [],
        cursor: since ?? 'c1',
        hasMore: true,
      ),
      _Fails(:final error) => throw error,
    };
  }
}

_Fails _answer(String code) =>
    _Fails(GraphQLResponseException([GraphQLError('failed', code: code)]));

final _offline = _Fails(GraphQLNetworkException('connection lost', null));

/// The automatic retries of a failed sync, through the controller the app
/// runs, on a clock the test moves.
void main() {
  const waits = [Duration(seconds: 30), Duration(minutes: 2)];

  /// Runs [body] on a fake clock with a controller syncing from [server];
  /// [seen] gathers every status the controller goes through.
  void run(
    _ScriptedServer server,
    void Function(FakeAsync time, ProviderContainer container, List<SyncStatus> seen) body,
  ) => fakeAsync((time) {
    final container = ProviderContainer.test(
      overrides: [
        clockProvider.overrideWithValue(() => DateTime.utc(2026, 10, 6)),
        syncRetryDelaysProvider.overrideWithValue(waits),
        syncServiceProvider.overrideWithValue(
          SyncService(source: server, store: MemorySyncStore()),
        ),
      ],
    );
    final seen = <SyncStatus>[];
    container.listen(syncControllerProvider, (_, next) => seen.add(next));
    body(time, container, seen);
    container.dispose();
    time.flushMicrotasks();
  });

  List<Duration?> retries(List<SyncStatus> seen) => [
    for (final s in seen.whereType<SyncFailed>()) s.retryIn,
  ];

  test('a server failure is tried again by itself, and the retry completes', () {
    final server = _ScriptedServer([_answer(GraphQLError.internal), const _Done()]);
    run(server, (time, container, seen) {
      unawaited(container.read(syncControllerProvider.notifier).sync());
      time.flushMicrotasks();
      final failed = container.read(syncControllerProvider) as SyncFailed;
      expect(failed.failure, SyncFailure.server);
      expect(failed.retryIn, waits.first);

      time.elapse(waits.first);
      expect(server.requests, 2);
      expect(container.read(syncControllerProvider), isA<SyncDone>());
    });
  });

  test('a service down behind the API is a server failure too', () {
    expect(
      SyncFailure.of(GraphQLResponseException(const [GraphQLError('a', code: 'UNAVAILABLE')])),
      SyncFailure.server,
    );
    expect(
      SyncFailure.of(
        GraphQLResponseException(const [
          GraphQLError('a', code: GraphQLError.internal),
          GraphQLError('b', code: GraphQLError.invalidInput),
        ]),
      ),
      SyncFailure.refused,
      reason: 'one refusal among the errors: the same request fails again',
    );
  });

  test('a refused request is not sent again by itself', () {
    final server = _ScriptedServer([_answer(GraphQLError.invalidInput)]);
    run(server, (time, container, seen) {
      unawaited(container.read(syncControllerProvider.notifier).sync());
      time.flushMicrotasks();
      final failed = container.read(syncControllerProvider) as SyncFailed;
      expect(failed.failure, SyncFailure.refused);
      expect(failed.retryIn, isNull);

      time.elapse(const Duration(hours: 1));
      expect(server.requests, 1);
    });
  });

  test('each failure waits longer, the last wait repeating', () {
    final server = _ScriptedServer([_offline]);
    run(server, (time, container, seen) {
      unawaited(container.read(syncControllerProvider.notifier).sync());
      time.elapse(waits[0] + waits[1] * 2);
      expect(retries(seen), [waits[0], waits[1], waits[1], waits[1]]);
      expect(server.requests, 4);
    });
  });

  test('a success starts the waits over', () {
    final server = _ScriptedServer([_offline, const _Done(), _offline]);
    run(server, (time, container, seen) {
      unawaited(container.read(syncControllerProvider.notifier).sync());
      time.elapse(waits[0]);
      expect(container.read(syncControllerProvider), isA<SyncDone>());

      unawaited(container.read(syncControllerProvider.notifier).sync());
      time.flushMicrotasks();
      expect(retries(seen), [waits[0], waits[0]]);
    });
  });

  test('a rate limit is waited out as long as the server asks', () {
    final server = _ScriptedServer([
      _Fails(GraphQLRateLimitedException(const Duration(minutes: 5))),
      const _Done(),
    ]);
    run(server, (time, container, seen) {
      unawaited(container.read(syncControllerProvider.notifier).sync());
      time.flushMicrotasks();
      final failed = container.read(syncControllerProvider) as SyncFailed;
      expect(failed.failure, SyncFailure.busy);
      expect(failed.retryIn, const Duration(minutes: 5));

      time.elapse(waits.first);
      expect(server.requests, 1, reason: 'not before the server said');
      time.elapse(const Duration(minutes: 5));
      expect(container.read(syncControllerProvider), isA<SyncDone>());
    });
  });

  test('an error with no known cause is told neutrally, and tried again', () {
    final server = _ScriptedServer([const _Fails(FormatException('not a place')), const _Done()]);
    run(server, (time, container, seen) {
      unawaited(container.read(syncControllerProvider.notifier).sync());
      time.flushMicrotasks();
      final failed = container.read(syncControllerProvider) as SyncFailed;
      expect(failed.failure, SyncFailure.other, reason: 'never "no connection"');
      expect(failed.retryIn, waits.first);
    });
  });

  test('a run stopped by a stuck cursor is not reported done', () {
    final server = _ScriptedServer([const _Stuck(), const _Stuck(), const _Done()]);
    run(server, (time, container, seen) {
      unawaited(container.read(syncControllerProvider.notifier).sync());
      time.flushMicrotasks();
      final failed = container.read(syncControllerProvider) as SyncFailed;
      expect(failed.failure, SyncFailure.server);

      time.elapse(waits.first);
      expect(container.read(syncControllerProvider), isA<SyncDone>());
    });
  });
}
