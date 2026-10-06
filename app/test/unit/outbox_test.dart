import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunaway/core/database/user_database.dart';
import 'package:lunaway/features/community/data/community_api.dart';
import 'package:lunaway/features/community/data/community_operations.dart';
import 'package:lunaway/features/community/data/outbox.dart';
import 'package:lunaway/features/community/data/outbox_sender.dart';
import 'package:lunaway/features/community/data/pending_files.dart';
import 'package:lunaway/features/community/data/photo_upload.dart';
import 'package:lunaway/features/community/domain/community.dart';
import 'package:lunaway/features/community/domain/contribution.dart';
import 'package:lunaway/features/places/data/graphql/graphql_client.dart';
import 'package:lunaway/features/places/domain/place_content.dart';

/// How the fake server answers the next request.
enum _Net {
  /// Accepts and answers.
  up,

  /// The request never leaves the device.
  down,

  /// The server accepts the request, and the answer is lost on the way.
  answerLost,

  /// The connection breaks after the request left, before the server read
  /// it: the device cannot tell this from [answerLost].
  cutBeforeArrival,
}

/// A server in memory: it keeps what it accepted, so a test sees a
/// duplicate as the real one would store it.
final class _Server implements CommunityApi {
  new(this.clock);

  final DateTime Function() clock;
  _Net net = _Net.up;
  GraphQLError? refuse;
  final confirmations = <Confirmation>[];
  final issues = <IssueReport>[];
  final submissions = <PlaceSubmission>[];
  final photos = <({String placeId, Uint8List bytes})>[];
  final calls = <ContributionKind>[];
  final ratings = <String, int>{};
  final muted = <String>{};
  var _next = 0;

  String _id() => 'srv-${_next++}';

  T _answer<T>(T Function() accept) {
    if (net == _Net.down) throw GraphQLNetworkException('no route to host', null);
    if (net == _Net.cutBeforeArrival) throw GraphQLNetworkException('connection reset', null);
    final refused = refuse;
    if (refused != null) throw GraphQLResponseException([refused]);
    final result = accept();
    if (net == _Net.answerLost) throw GraphQLNetworkException('connection reset', null);
    return result;
  }

  /// What each idempotency key's first request stored, as the server keeps
  /// it for 30 days.
  final keyed = <String, Object?>{};

  /// As the API before the keys: each request makes a new row.
  bool ignoresKeys = false;

  @override
  Future<Object?> send(ContributionKind kind, Map<String, Object?> v, {bool create = true}) async {
    calls.add(kind);
    final key = v['idempotencyKey'];
    return _answer<Object?>(() {
      if (!ignoresKeys && key is String && keyed.containsKey(key)) return keyed[key];
      final result = _store(kind, v);
      if (key is String) keyed[key] = result;
      return result;
    });
  }

  Object? _store(ContributionKind kind, Map<String, Object?> v) {
    {
      switch (kind) {
        case ContributionKind.confirm:
          final c = Confirmation(
            id: _id(),
            placeId: v['placeId']! as String,
            status: ConfirmationStatus.fromWire(v['status'])!,
            createdAt: clock(),
          );
          confirmations.add(c);
          return c;
        case ContributionKind.reportIssue:
          final i = IssueReport(
            id: _id(),
            placeId: v['placeId']! as String,
            kind: IssueKind.fromWire(v['kind'])!,
            createdAt: clock(),
          );
          issues.add(i);
          return i;
        case ContributionKind.addVendingMachine:
          final s = PlaceSubmission(
            id: _id(),
            kind: SubmissionKind.poi,
            status: SubmissionStatus.accepted,
            createdAt: clock(),
          );
          submissions.add(s);
          return s;
        case ContributionKind.addPlace:
          final s = PlaceSubmission(
            id: _id(),
            kind: SubmissionKind.create,
            status: SubmissionStatus.accepted,
            createdAt: clock(),
          );
          submissions.add(s);
          return s;
        case ContributionKind.rate:
          ratings[v['placeId']! as String] = v['stars']! as int;
          return true;
        case ContributionKind.mute:
          muted.add(v['id']! as String);
          return true;
        case ContributionKind.unmute:
          muted.remove(v['id']! as String);
          return true;
        case ContributionKind.deleteReview:
          throw GraphQLResponseException([
            const GraphQLError('no such review', code: GraphQLError.notFound),
          ]);
        case _:
          return true;
      }
    }
  }

  /// The worker places a new place: its submission gains the place's id.
  void place(String placeId) {
    for (var i = 0; i < submissions.length; i++) {
      final s = submissions[i];
      submissions[i] = PlaceSubmission(
        id: s.id,
        kind: s.kind,
        status: SubmissionStatus.applied,
        createdAt: s.createdAt,
        placeId: placeId,
      );
    }
  }

  bool duplicatePhoto = false;

  @override
  Future<Photo> upload(
    String placeId,
    Uint8List jpeg, {
    bool create = true,
    void Function(double sent)? onProgress,
  }) async {
    if (net == _Net.down) throw const UploadException(0, 'offline');
    if (photos.any((p) => p.bytes.length == jpeg.length && p.placeId == placeId)) {
      throw const UploadException(422, 'file: this account already sent this photo');
    }
    onProgress?.call(0.5);
    onProgress?.call(1);
    photos.add((placeId: placeId, bytes: jpeg));
    if (net == _Net.answerLost) throw const UploadException(0, 'connection reset');
    return Photo(id: _id(), sourceId: 'community', thumbUrl: 't', largeUrl: 'l');
  }

  @override
  Future<MyContributions> recent({int first = 20}) async {
    if (net == _Net.down) throw GraphQLNetworkException('no route to host', null);
    return (
      reviews: const <Review>[],
      reviewTotal: 0,
      photos: const <Photo>[],
      photoTotal: 0,
      confirmations: confirmations.reversed.toList(),
      confirmationTotal: confirmations.length,
      issues: issues.reversed.toList(),
      issueTotal: issues.length,
      submissions: submissions.reversed.toList(),
      submissionTotal: submissions.length,
    );
  }
}

void main() {
  late UserDatabase db;
  late DateTime now;
  late _Server server;
  late MemoryPendingFiles files;
  late OutboxStore outbox;
  String? account;

  OutboxSender sender() =>
      OutboxSender(outbox: outbox, api: server, accountId: () async => account, clock: () => now);

  setUp(() {
    db = UserDatabase(NativeDatabase.memory());
    now = DateTime.utc(2026, 10, 6, 8);
    server = _Server(() => now);
    files = MemoryPendingFiles();
    outbox = OutboxStore(db, files: files, clock: () => now);
    account = null;
  });
  tearDown(() => db.close());

  test('a contribution made offline waits, then goes once the network is back', () async {
    await outbox.add(
      ContributionKind.confirm,
      placeId: 'p1',
      payload: {'placeId': 'p1', 'status': 'STILL_OK'},
    );
    server.net = _Net.down;
    final first = await sender().sendDue();
    expect(first.offline, isTrue);
    expect(server.confirmations, isEmpty);
    final waiting = (await outbox.all()).single;
    expect(waiting.state, OutboxState.pending);
    expect(waiting.nextAttemptAt, now.add(const Duration(seconds: 15)));

    // Not due yet: nothing is sent before the wait is over.
    server.net = _Net.up;
    now = now.add(const Duration(seconds: 5));
    await sender().sendDue();
    expect(server.confirmations, isEmpty);

    now = now.add(const Duration(seconds: 10));
    final second = await sender().sendDue();
    expect(second.sent, 1);
    expect(server.confirmations, hasLength(1));
    expect(await outbox.all(), isEmpty);
  });

  test('a replay after a lost answer looks for it first, and never adds it twice', () async {
    // A device with an account: a contribution only leaves with one.
    account = 'acc-1';
    await outbox.add(
      ContributionKind.confirm,
      placeId: 'p1',
      payload: {'placeId': 'p1', 'status': 'CLOSED'},
    );
    await outbox.add(
      ContributionKind.reportIssue,
      placeId: 'p2',
      payload: {'placeId': 'p2', 'kind': 'NIGHT_BAN'},
    );
    // The server stores the confirmation, the answer never arrives.
    server.net = _Net.answerLost;
    await sender().sendDue();
    expect(server.confirmations, hasLength(1));

    server.net = _Net.up;
    now = now.add(const Duration(minutes: 1));
    final replay = await sender().sendDue();
    expect(replay.sent, 2);
    expect(
      server.calls.where((k) => k == ContributionKind.confirm),
      hasLength(1),
      reason: "found among the account's latest, not sent again",
    );
    expect(server.confirmations, hasLength(1));
    expect(server.issues, hasLength(1));
    expect(await outbox.all(), isEmpty);
  });

  test(
    'an entry an older version left uncertain, sent without a key, is looked for first',
    () async {
      account = 'acc-1';
      final entry = await outbox.add(
        ContributionKind.confirm,
        placeId: 'p1',
        payload: {'placeId': 'p1', 'status': 'CLOSED'},
      );
      // The version before the keys sent it, the answer was lost, and it
      // marked the entry uncertain; the server stored it under no key.
      await outbox.markSending(entry!.id);
      await outbox.retryAt(entry.id, now, uncertain: true);
      server.confirmations.add(
        Confirmation(
          id: 'srv-old',
          placeId: 'p1',
          status: ConfirmationStatus.closed,
          createdAt: now,
        ),
      );
      now = now.add(const Duration(minutes: 1));
      await sender().sendDue();
      expect(server.confirmations, hasLength(1));
      expect(server.calls, isNot(contains(ContributionKind.confirm)));
      expect(await outbox.all(), isEmpty);
    },
  );

  test(
    'deleting what a lost answer made drops its entry: sent again, it would be made anew',
    () async {
      account = 'acc-1';
      await outbox.add(
        ContributionKind.confirm,
        placeId: 'p1',
        payload: {'placeId': 'p1', 'status': 'CLOSED'},
      );
      // The server stores it, the answer never arrives: the entry waits.
      server.net = _Net.answerLost;
      await sender().sendDue();
      final made = server.confirmations.single;
      expect(await outbox.all(), hasLength(1));
      // Queued later and never sent: it made nothing, it stays.
      await outbox.add(
        ContributionKind.confirm,
        placeId: 'p2',
        payload: {'placeId': 'p2', 'status': 'STILL_OK'},
      );

      // The user deletes it from the list of their contributions; the server
      // forgets it, and its key with it.
      expect(await outbox.forgetMakerOf((e) => mayHaveMade(e, made)), isTrue);
      server.confirmations.remove(made);
      server.keyed.removeWhere((_, v) => v == made);

      server.net = _Net.up;
      now = now.add(const Duration(minutes: 1));
      await sender().sendDue();
      expect(server.confirmations.map((c) => c.placeId), ['p2'], reason: 'p1 was not made again');
      expect(await outbox.all(), isEmpty);
    },
  );

  test('a deletion drops only the oldest entry that may have reached the server', () async {
    account = 'acc-1';
    Future<String> issue() async => (await outbox.add(
      ContributionKind.reportIssue,
      placeId: 'p1',
      payload: {'placeId': 'p1', 'kind': 'DANGER'},
    ))!.id;
    // Refused for good: it made nothing, and waits for the user.
    final refused = await issue();
    await outbox.markSending(refused);
    await outbox.fail(refused, code: OutboxError.invalid);
    // Two whose answers were lost, the same request.
    final first = await issue();
    await outbox.markSending(first);
    await outbox.retryAt(first, now, uncertain: true);
    final second = await issue();
    await outbox.markSending(second);
    await outbox.retryAt(second, now, uncertain: true);
    // Never sent: it made nothing.
    final waiting = await issue();

    final made = IssueReport(id: 'srv-1', placeId: 'p1', kind: IssueKind.danger, createdAt: now);
    expect(await outbox.forgetMakerOf((e) => mayHaveMade(e, made)), isTrue);
    expect((await outbox.all()).map((e) => e.id), [refused, second, waiting]);
  });

  test('what an entry may have made: same request, made after it was queued', () {
    final entry = PendingContribution(
      id: 'e1',
      kind: ContributionKind.reportIssue,
      placeId: 'p1',
      payload: const {'placeId': 'p1', 'kind': 'DANGER'},
      createdAt: now,
      attemptStartedAt: now,
    );
    IssueReport issue({
      String place = 'p1',
      IssueKind kind = IssueKind.danger,
      Duration after = Duration.zero,
    }) => IssueReport(id: 'i', placeId: place, kind: kind, createdAt: now.add(after));
    expect(mayHaveMade(entry, issue()), isTrue);
    expect(
      mayHaveMade(entry, issue(after: const Duration(days: 2))),
      isTrue,
      reason: 'a late retry',
    );
    expect(
      mayHaveMade(entry, issue(after: const Duration(hours: -1))),
      isFalse,
      reason: 'made before it',
    );
    expect(mayHaveMade(entry, issue(place: 'p2')), isFalse);
    expect(mayHaveMade(entry, issue(kind: IssueKind.nightBan)), isFalse);
    expect(
      mayHaveMade(
        entry,
        Confirmation(id: 'c', placeId: 'p1', status: ConfirmationStatus.closed, createdAt: now),
      ),
      isFalse,
    );
  });

  test('an API without the keys still gets each contribution once after a lost answer', () async {
    account = 'acc-1';
    server.ignoresKeys = true;
    await outbox.add(
      ContributionKind.confirm,
      placeId: 'p1',
      payload: {'placeId': 'p1', 'status': 'CLOSED'},
    );
    server.net = _Net.answerLost;
    await sender().sendDue();
    final cut = await outbox.add(
      ContributionKind.reportIssue,
      placeId: 'p2',
      payload: {'placeId': 'p2', 'kind': 'DANGER'},
    );
    // The app ended during this one's request, which the server stored.
    await outbox.markSending(cut!.id);
    server.issues.add(
      IssueReport(id: 'srv-cut', placeId: 'p2', kind: IssueKind.danger, createdAt: now),
    );

    server.net = _Net.up;
    now = now.add(const Duration(minutes: 1));
    await sender().sendDue();
    expect(server.confirmations, hasLength(1));
    expect(server.issues, hasLength(1));
    expect(await outbox.all(), isEmpty);
  });

  test('an edit that empties a field waits for an API that knows how', () async {
    account = 'acc-1';
    await outbox.add(
      ContributionKind.editPlace,
      placeId: 'p1',
      payload: {
        'placeId': 'p1',
        'patch': {
          'clear': ['WEBSITE'],
        },
      },
    );
    server.refuse = const GraphQLError(
      'Invalid value for argument "patch", unknown field "clear" of type "PlaceDetailsInput"',
      code: 'INVALID_INPUT',
    );
    await sender().sendDue();
    final waiting = (await outbox.all()).single;
    expect(waiting.state, OutboxState.pending, reason: 'not refused for good');
    expect(waiting.nextAttemptAt, isNotNull);
  });

  test('a failure before any connection is not taken for a request that may have landed', () async {
    await outbox.add(
      ContributionKind.confirm,
      placeId: 'p1',
      payload: {'placeId': 'p1', 'status': 'STILL_OK'},
    );
    server.net = _Net.down;
    await sender().sendDue();
    expect((await outbox.all()).single.uncertain, isFalse);
  });

  test('an entry made under an account the device no longer holds is never sent', () async {
    // Queued while signed in as acc-1, then signed out (or the account
    // was lost): neither sent without an account, which would make a new
    // one, nor under another account.
    await outbox.add(
      ContributionKind.confirm,
      placeId: 'p1',
      payload: {'placeId': 'p1', 'status': 'STILL_OK'},
      accountId: 'acc-1',
    );
    account = null;
    final report = await sender().sendDue();
    expect(report.failed, 1);
    expect(server.calls, isEmpty);
    expect((await outbox.all()).single.errorCode, OutboxError.otherAccount);
  });

  test('a replayed new place never takes the submission of another new place', () async {
    final first = await outbox.add(
      ContributionKind.addPlace,
      payload: {
        'input': {'kind': 'PARKING', 'lat': 45.0, 'lon': 6.0},
      },
    );
    await sender().sendDue();
    expect(server.submissions, hasLength(1));
    expect(await outbox.byId(first!.id), isNull);

    // A second place: its connection breaks in a way the device cannot
    // tell from a lost answer, and the server never had it.
    now = now.add(const Duration(minutes: 1));
    await outbox.add(
      ContributionKind.addPlace,
      payload: {
        'input': {'kind': 'CAMPSITE', 'lat': 45.1, 'lon': 6.1},
      },
    );
    server.net = _Net.cutBeforeArrival;
    await sender().sendDue();

    // The next pass, in a new run: its own key, which the server has not
    // seen, never the first place's.
    server.net = _Net.up;
    now = now.add(const Duration(minutes: 2));
    await sender().sendDue();
    expect(server.submissions, hasLength(2), reason: 'the second place was sent');
    expect(await outbox.all(), isEmpty);
  });

  test('an attempt cut by the end of the app is found on the server, never sent twice', () async {
    // A device with an account: a contribution only leaves with one.
    account = 'acc-1';
    final entry = await outbox.add(
      ContributionKind.reportIssue,
      placeId: 'p1',
      payload: {'placeId': 'p1', 'kind': 'DANGER'},
    );
    // The app ended during the request, which the server had stored under
    // the entry's key.
    await outbox.markSending(entry!.id);
    final stored = IssueReport(id: 'srv-x', placeId: 'p1', kind: IssueKind.danger, createdAt: now);
    server.issues.add(stored);
    server.keyed[entry.id] = stored;
    now = now.add(const Duration(hours: 2));
    await sender().sendDue();
    expect(server.issues, hasLength(1));
    expect(await outbox.all(), isEmpty);
  });

  test('a vending machine whose answer was lost is looked for before it is sent again', () async {
    account = 'acc-1';
    await outbox.add(
      ContributionKind.addVendingMachine,
      payload: {
        'input': {'kind': 'VENDING_PIZZA', 'lat': 45.0, 'lon': 6.0},
      },
    );
    server.net = _Net.answerLost;
    await sender().sendDue();
    expect(server.submissions, hasLength(1));
    expect((await outbox.all()).single.uncertain, isTrue);

    server.net = _Net.up;
    now = now.add(const Duration(minutes: 1));
    await sender().sendDue();
    expect(server.submissions, hasLength(1), reason: "found among the account's submissions");
    expect(server.calls.where((k) => k == ContributionKind.addVendingMachine), hasLength(1));
    expect(await outbox.all(), isEmpty);
  });

  test('an attempt cut before it reached the server is sent after the check', () async {
    final entry = await outbox.add(
      ContributionKind.confirm,
      placeId: 'p1',
      payload: {'placeId': 'p1', 'status': 'STILL_OK'},
    );
    await outbox.markSending(entry!.id);
    await sender().sendDue();
    expect(server.confirmations, hasLength(1));
    expect(await outbox.all(), isEmpty);
  });

  test(
    'a newer rating of a place replaces the one waiting; a mute and its unmute cancel',
    () async {
      await outbox.add(
        ContributionKind.rate,
        placeId: 'p1',
        payload: {'placeId': 'p1', 'stars': 2},
      );
      await outbox.add(
        ContributionKind.rate,
        placeId: 'p1',
        payload: {'placeId': 'p1', 'stars': 5},
      );
      await outbox.add(ContributionKind.mute, payload: {'id': 'a1'});
      expect(await outbox.add(ContributionKind.unmute, payload: {'id': 'a1'}), isNull);
      final waiting = await outbox.all();
      expect(waiting.map((e) => e.kind), [ContributionKind.rate]);
      await sender().sendDue();
      expect(server.ratings, {'p1': 5});
      expect(server.calls, [ContributionKind.rate]);
    },
  );

  test(
    'a deletion of what the server no longer has is done; a refusal waits for the user',
    () async {
      await outbox.add(ContributionKind.deleteReview, payload: {'id': 'r1'});
      await sender().sendDue();
      expect(await outbox.all(), isEmpty);

      await outbox.add(
        ContributionKind.rate,
        placeId: 'p1',
        payload: {'placeId': 'p1', 'stars': 4},
      );
      server.refuse = const GraphQLError(
        'this needs trust level 1',
        code: GraphQLError.forbidden,
        requiredLevel: 1,
        level: 0,
      );
      final report = await sender().sendDue();
      expect(report.failed, 1);
      final failed = (await outbox.all()).single;
      expect(failed.state, OutboxState.failed);
      expect(failed.errorCode, OutboxError.forbidden);

      // Never resent alone, even much later.
      server.refuse = null;
      now = now.add(const Duration(days: 1));
      await sender().sendDue();
      expect(server.ratings, isEmpty);

      await outbox.retryNow(failed.id);
      await sender().sendDue();
      expect(server.ratings, {'p1': 4});
      expect(await outbox.all(), isEmpty);
    },
  );

  test('a photo taken with a new place waits for the place, then goes once', () async {
    final file = await files.put(Uint8List.fromList(List.filled(2000, 7)));
    await outbox.add(
      ContributionKind.addPlace,
      fileId: file,
      payload: {
        'input': {
          'kind': 'PARKING',
          'lat': 45.9,
          'lon': 6.1,
          'details': {'name': 'Parking du lac'},
        },
      },
    );

    final first = await sender().sendDue();
    expect(server.submissions, hasLength(1));
    expect(server.photos, isEmpty, reason: 'the place is not placed yet');
    final waiting = (await outbox.all()).single;
    expect(waiting.kind, ContributionKind.photo);
    expect(waiting.fileId, file, reason: 'the photo keeps its bytes');
    expect(first.nextAttemptAt, now, reason: 'the photo is due at once');
    final second = await sender().sendDue();
    expect(server.photos, isEmpty);
    expect(second.nextAttemptAt, now.add(const Duration(seconds: 20)));

    server.place('place-new');
    now = now.add(const Duration(seconds: 20));
    await sender().sendDue();
    expect(server.photos.single.placeId, 'place-new');
    expect(await outbox.all(), isEmpty);
    expect(files.files, isEmpty, reason: 'the bytes leave the device with the entry');
  });

  test('a photo whose answer was lost is settled by the server refusing it twice', () async {
    final file = await files.put(Uint8List.fromList(List.filled(1000, 1)));
    await outbox.add(
      ContributionKind.photo,
      placeId: 'p1',
      fileId: file,
      payload: {'placeId': 'p1'},
    );
    server.net = _Net.answerLost;
    await sender().sendDue();
    expect(server.photos, hasLength(1));
    expect((await outbox.all()).single.uncertain, isTrue);

    server.net = _Net.up;
    now = now.add(const Duration(minutes: 1));
    await sender().sendDue();
    expect(server.photos, hasLength(1));
    expect(await outbox.all(), isEmpty);
  });

  test("entries made before the account belong to it; another account's are held back", () async {
    await outbox.add(ContributionKind.rate, placeId: 'p1', payload: {'placeId': 'p1', 'stars': 3});
    account = 'acc-1';
    await sender().sendDue();
    expect(server.ratings, {'p1': 3});

    // A contribution of acc-1 left on a device now signed in as acc-2.
    await outbox.add(
      ContributionKind.rate,
      placeId: 'p2',
      payload: {'placeId': 'p2', 'stars': 1},
      accountId: 'acc-1',
    );
    account = 'acc-2';
    await sender().sendDue();
    expect(server.ratings.containsKey('p2'), isFalse);
    expect((await outbox.all()).single.errorCode, OutboxError.otherAccount);
  });

  test('the outbox survives the end of the app: a new store reads the same entries', () async {
    await outbox.add(
      ContributionKind.confirm,
      placeId: 'p1',
      payload: {'placeId': 'p1', 'status': 'CHANGED', 'note': 'Barrière posée'},
    );
    final again = OutboxStore(db, files: files, clock: () => now);
    final entry = (await again.all()).single;
    expect(entry.kind, ContributionKind.confirm);
    expect(entry.payload, {'placeId': 'p1', 'status': 'CHANGED', 'note': 'Barrière posée'});
    expect(entry.createdAt, now);
  });
}
