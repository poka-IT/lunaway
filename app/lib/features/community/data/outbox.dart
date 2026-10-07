import 'dart:convert';
import 'dart:math';

import 'package:drift/drift.dart';
import 'package:lunaway/core/database/user_database.dart';
import 'package:lunaway/features/community/data/pending_files.dart';
import 'package:lunaway/features/community/domain/contribution.dart';

/// The contributions waiting to reach the server, kept in the user
/// database so they survive the app's end and a phone without network for
/// days. Every change goes through here: the screens watch it, the sender
/// works it.
final class OutboxStore {
  new(this._db, {required this.files, this.clock = DateTime.now, Random? random})
    : _random = random ?? Random.secure();

  final UserDatabase _db;
  final PendingFiles files;
  final DateTime Function() clock;
  final Random _random;

  /// Every entry, oldest first.
  Stream<List<PendingContribution>> watch() =>
      (_db.select(_db.outbox)..orderBy([(o) => OrderingTerm.asc(o.createdAt)])).watch().map(
        (rows) => [...rows.map(_entry).nonNulls],
      );

  Future<List<PendingContribution>> all() async => [
    ...(await (_db.select(
      _db.outbox,
    )..orderBy([(o) => OrderingTerm.asc(o.createdAt)])).get()).map(_entry).nonNulls,
  ];

  Future<PendingContribution?> byId(String id) async =>
      _entryOrNull(await (_db.select(_db.outbox)..where((o) => o.id.equals(id))).getSingleOrNull());

  /// Queues a contribution. A newer one replaces what it supersedes: a
  /// second rating of a place replaces the first, an unmute cancels a mute
  /// not sent yet. Returns the entry kept, or null when the new one only
  /// cancelled a waiting one.
  Future<PendingContribution?> add(
    ContributionKind kind, {
    required Map<String, Object?> payload,
    String? placeId,
    String? fileId,
    String? accountId,
  }) => _db.transaction(() async {
    // Only this account's own waiting entries (or those made before it
    // existed) are merged with: another account's stay as they are.
    final waiting = (await all())
        .where(
          (e) =>
              e.state == OutboxState.pending &&
              (e.accountId == null || accountId == null || e.accountId == accountId),
        )
        .toList();
    Iterable<PendingContribution> same(
      Set<ContributionKind> kinds,
      bool Function(PendingContribution) match,
    ) => waiting.where((e) => kinds.contains(e.kind) && match(e));
    switch (kind) {
      case ContributionKind.rate:
        // A rating changes the stars of a review still waiting, and keeps
        // its text, as the server does.
        final review = same({ContributionKind.review}, (e) => e.placeId == placeId).firstOrNull;
        if (review != null) {
          await updatePayload(review.id, {...review.payload, 'stars': payload['stars']});
          return await byId(review.id);
        }
        for (final e in same({ContributionKind.rate}, (e) => e.placeId == placeId)) {
          await _remove(e);
        }
      case ContributionKind.review:
        // One rating or review per account and place: the last one counts.
        for (final e in same({
          ContributionKind.rate,
          ContributionKind.review,
        }, (e) => e.placeId == placeId)) {
          await _remove(e);
        }

      case ContributionKind.confirm:
        for (final e in same({ContributionKind.confirm}, (e) => e.placeId == placeId)) {
          await _remove(e);
        }
      case ContributionKind.confirmPoi:
        // Only the latest answer of an account about a point counts.
        for (final e in same({kind}, (e) => e.payload['poiId'] == payload['poiId'])) {
          await _remove(e);
        }
      case ContributionKind.mute || ContributionKind.unmute:
        final opposite = kind == ContributionKind.mute
            ? ContributionKind.unmute
            : ContributionKind.mute;
        final cancelled = same({opposite}, (e) => e.payload['id'] == payload['id']).toList();
        if (cancelled.isNotEmpty) {
          for (final e in cancelled) {
            await _remove(e);
          }
          return null;
        }
        if (same({kind}, (e) => e.payload['id'] == payload['id']).isNotEmpty) return null;
      case ContributionKind.reportContent:
        final duplicate = same({
          kind,
        }, (e) => e.payload['id'] == payload['id'] && e.payload['target'] == payload['target']);
        if (duplicate.isNotEmpty) return duplicate.first;
      case ContributionKind.reportRoadEvent:
        // The same thing reported at the same spot while the first waits:
        // one is enough.
        final input = payload['input'];
        final duplicate = waiting.where(
          (e) =>
              e.kind == kind &&
              e.payload['input'] is Map &&
              input is Map &&
              _sameReport(e.payload['input']! as Map, input),
        );
        if (duplicate.isNotEmpty) return duplicate.first;
      case ContributionKind.clearRoadEvent:
        final duplicate = waiting.where(
          (e) => e.kind == kind && e.payload['eventId'] == payload['eventId'],
        );
        if (duplicate.isNotEmpty) return duplicate.first;
      case ContributionKind.deleteReview ||
          ContributionKind.deleteConfirmation ||
          ContributionKind.reportIssue ||
          ContributionKind.deleteIssueReport ||
          ContributionKind.addPlace ||
          ContributionKind.editPlace ||
          ContributionKind.deletePlaceSubmission ||
          ContributionKind.photo ||
          ContributionKind.deletePhoto ||
          ContributionKind.addVendingMachine ||
          ContributionKind.deletePoiConfirmation:
        break;
    }
    final now = clock().toUtc();
    final id = _uuid();
    await _db
        .into(_db.outbox)
        .insert(
          OutboxCompanion.insert(
            id: id,
            kind: kind.name,
            placeId: Value(placeId),
            payload: jsonEncode(payload),
            fileId: Value(fileId),
            accountId: Value(accountId),
            createdAt: now.microsecondsSinceEpoch,
          ),
        );
    return await byId(id);
  });

  /// An attempt starts: if the app ends before its answer, the entry stays
  /// in this state and the next start treats it as uncertain.
  Future<void> markSending(String id) => _write(
    id,
    OutboxCompanion(
      state: Value(OutboxState.sending.name),
      attemptStartedAt: Value(clock().toUtc().microsecondsSinceEpoch),
    ),
  );

  /// The server accepted it: the entry and its file go, unless [keepFile]
  /// (another entry takes the file over).
  Future<void> done(String id, {bool keepFile = false}) => _db.transaction(() async {
    final entry = await byId(id);
    if (entry == null) return;
    await _remove(entry, keepFile: keepFile);
  });

  /// Not sent this time; tried again at [at]. [uncertain] when the request
  /// may have reached the server.
  Future<void> retryAt(String id, DateTime at, {required bool uncertain, String? detail}) async {
    final entry = await byId(id);
    if (entry == null) return;
    await _write(
      id,
      OutboxCompanion(
        state: Value(OutboxState.pending.name),
        attempts: Value(entry.attempts + 1),
        nextAttemptAt: Value(at.toUtc().microsecondsSinceEpoch),
        uncertain: Value(entry.uncertain || uncertain),
        errorDetail: Value(detail),
      ),
    );
  }

  /// Refused for good: kept, with why, until the user retries or discards
  /// it.
  Future<void> fail(String id, {required String code, String? detail}) async {
    final entry = await byId(id);
    if (entry == null) return;
    await _write(
      id,
      OutboxCompanion(
        state: Value(OutboxState.failed.name),
        attempts: Value(entry.attempts + 1),
        errorCode: Value(code),
        errorDetail: Value(detail),
      ),
    );
  }

  /// The user asks to try a failed entry again, now.
  Future<void> retryNow(String id) => _write(
    id,
    OutboxCompanion(
      state: Value(OutboxState.pending.name),
      nextAttemptAt: const Value(0),
      errorCode: const Value(null),
      errorDetail: const Value(null),
    ),
  );

  /// Changes the request of an entry (a photo learns the place its new
  /// place became).
  Future<void> updatePayload(String id, Map<String, Object?> payload) =>
      _write(id, OutboxCompanion(payload: Value(jsonEncode(payload))));

  /// The entry was found on the server: it is no longer uncertain.
  Future<void> settle(String id) => _write(id, const OutboxCompanion(uncertain: Value(false)));

  /// The user gives an entry up, with its file.
  Future<void> discard(String id) => done(id);

  /// Gives the entries made before the account existed to [accountId].
  Future<void> claimFor(String accountId) => (_db.update(
    _db.outbox,
  )..where((o) => o.accountId.isNull())).write(OutboxCompanion(accountId: Value(accountId)));

  /// The mark of a rating or review the user deleted while it was being
  /// sent: once the server has it, the sender deletes it there. Kept in the
  /// payload, never sent (keys starting with `_` stay on the device).
  static const deleteOnceSent = '_deleteOnceSent';

  /// Server ids of contributions accepted lately, kept across runs: an
  /// uncertain entry never takes one of them for its own. Three days cover
  /// an entry left waiting for the network over a long weekend; a few
  /// dozen ids at most.
  static const _claimedSetting = 'outbox_claimed';
  static const _claimedFor = Duration(days: 3);

  Future<Set<String>> claimed() async => (await _claimedTimes()).keys.toSet();

  Future<void> claim(String serverId) => _db.transaction(() async {
    final since = clock().subtract(_claimedFor).millisecondsSinceEpoch;
    final times = await _claimedTimes()
      ..removeWhere((_, at) => at < since)
      ..[serverId] = clock().millisecondsSinceEpoch;
    await _db
        .into(_db.settings)
        .insertOnConflictUpdate(
          SettingsCompanion.insert(id: _claimedSetting, value: jsonEncode(times)),
        );
  });

  Future<Map<String, int>> _claimedTimes() async {
    final row = await (_db.select(
      _db.settings,
    )..where((r) => r.id.equals(_claimedSetting))).getSingleOrNull();
    if (row == null) return {};
    try {
      return (jsonDecode(row.value) as Map<String, dynamic>).map(
        (id, at) => MapEntry(id, (at as num).toInt()),
      );
    } on Object {
      return {};
    }
  }

  /// Drops the oldest entry whose request may have reached the server
  /// (being sent, or uncertain after a broken answer) and that [made] says
  /// may have made what the user now deletes: the outbox sends oldest
  /// first, so that is the one whose attempt landed. Another one that
  /// matches (a second new place) stays. An entry that never reached the
  /// server made nothing, and one refused for good waits for the user.
  /// Whether one went.
  Future<bool> forgetMakerOf(bool Function(PendingContribution) made) => _db.transaction(() async {
    for (final e in await all()) {
      final reached = e.uncertain || e.state == OutboxState.sending;
      if (e.failed || !reached || !made(e)) continue;
      await _remove(e);
      return true;
    }
    return false;
  });

  /// Forgets every entry and its files (signed out, account deleted).
  Future<void> clear() => _db.transaction(() async {
    for (final e in await all()) {
      await _remove(e);
    }
  });

  Future<void> _remove(PendingContribution e, {bool keepFile = false}) async {
    await (_db.delete(_db.outbox)..where((o) => o.id.equals(e.id))).go();
    final file = e.fileId;
    if (file != null && !keepFile) await files.delete(file);
  }

  Future<void> _write(String id, OutboxCompanion values) =>
      (_db.update(_db.outbox)..where((o) => o.id.equals(id))).write(values);

  /// A random UUID (version 4): the entry's id, never reused.
  String _uuid() {
    final b = List<int>.generate(16, (_) => _random.nextInt(256));
    b[6] = (b[6] & 0x0f) | 0x40;
    b[8] = (b[8] & 0x3f) | 0x80;
    final h = b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
    return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-'
        '${h.substring(16, 20)}-${h.substring(20)}';
  }

  static PendingContribution? _entryOrNull(OutboxRow? row) => row == null ? null : _entry(row);

  /// Null for a row this version cannot read (written by a newer one).
  static PendingContribution? _entry(OutboxRow r) {
    final kind = ContributionKind.fromName(r.kind);
    final state = OutboxState.values.where((s) => s.name == r.state).firstOrNull;
    if (kind == null || state == null) return null;
    DateTime? at(int? micros) => micros == null || micros == 0
        ? null
        : DateTime.fromMicrosecondsSinceEpoch(micros, isUtc: true);
    return PendingContribution(
      id: r.id,
      kind: kind,
      placeId: r.placeId,
      payload: (jsonDecode(r.payload) as Map<String, dynamic>).cast<String, Object?>(),
      fileId: r.fileId,
      accountId: r.accountId,
      createdAt: DateTime.fromMicrosecondsSinceEpoch(r.createdAt, isUtc: true),
      state: state,
      uncertain: r.uncertain,
      attempts: r.attempts,
      nextAttemptAt: at(r.nextAttemptAt),
      attemptStartedAt: at(r.attemptStartedAt),
      errorCode: r.errorCode,
      errorDetail: r.errorDetail,
    );
  }
}

/// Two road reports of one thing at one spot: the same kind and figure,
/// within about 50 m, made the same way (within 45 degrees).
bool _sameReport(Map<Object?, Object?> a, Map<Object?, Object?> b) {
  double? n(Object? v) => (v as num?)?.toDouble();
  final (la, lo, lb, lob) = (n(a['lat']), n(a['lon']), n(b['lat']), n(b['lon']));
  if (la == null || lo == null || lb == null || lob == null) return false;
  // The way it was made counts, as on the server: the same works seen
  // from both directions are two reports.
  final (ha, hb) = (n(a['headingDeg']), n(b['headingDeg']));
  final sameWay = ha == null || hb == null || (((ha - hb) % 360 + 360) % 360 - 180).abs() >= 135;
  return a['kind'] == b['kind'] &&
      n(a['valueM']) == n(b['valueM']) &&
      sameWay &&
      (la - lb).abs() < 0.0005 &&
      (lo - lob).abs() < 0.0007;
}
