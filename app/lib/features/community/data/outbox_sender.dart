import 'dart:async';
import 'dart:math';

import 'package:logging/logging.dart';
import 'package:lunaway/features/account/data/account_service.dart';
import 'package:lunaway/features/community/data/community_api.dart';
import 'package:lunaway/features/community/data/community_operations.dart';
import 'package:lunaway/features/community/data/outbox.dart';
import 'package:lunaway/features/community/data/photo_upload.dart';
import 'package:lunaway/features/community/domain/community.dart';
import 'package:lunaway/features/community/domain/contribution.dart';
import 'package:lunaway/features/places/data/graphql/graphql_client.dart';
import 'package:lunaway/features/places/domain/place_content.dart';
import 'package:meta/meta.dart';

final _log = Logger('outbox');

/// A contribution the server accepted, with its answer.
@immutable
final class SentContribution {
  const new(this.entry, this.result);

  final PendingContribution entry;
  final Object? result;
}

/// What a pass over the outbox did.
@immutable
final class SendReport {
  const new({
    this.sent = 0,
    this.failed = 0,
    this.offline = false,
    this.nextAttemptAt,
  });

  final int sent;
  final int failed;

  /// The pass stopped because the network or the server did not answer.
  final bool offline;

  /// When an entry waits to be tried again; null when nothing waits.
  final DateTime? nextAttemptAt;
}

/// Sends the outbox, oldest first, and keeps a replay from ever
/// duplicating a contribution:
///
/// - each entry is the same row from its first attempt to its last, and is
///   removed only once the server accepted it;
/// - a contribution sent twice changes nothing more than once (a rating, a
///   deletion, a mute) is simply sent again;
/// - for the others (a confirmation, an issue, a new place, an edit, a
///   photo), an attempt that may have reached the server (the app ended
///   during it, or the network failed after the request left) marks the
///   entry uncertain, and the next attempt first looks for it among the
///   account's latest contributions; a photo the server already has is
///   refused by the server itself, which settles it.
///
/// No network stops the pass at once (every entry would fail the same
/// way); a server error delays that entry only; a refusal fails it, for the
/// user to see.
final class OutboxSender {
  new({
    required this.outbox,
    required this.api,
    required this.accountId,
    this.clock = DateTime.now,
    this.delays = const [
      Duration(seconds: 15),
      Duration(minutes: 1),
      Duration(minutes: 5),
      Duration(minutes: 15),
      Duration(hours: 1),
    ],
    this.placeWait = const Duration(seconds: 20),
    this.moderationWait = const Duration(minutes: 30),
  });

  final OutboxStore outbox;
  final CommunityApi api;

  /// The account of this device, null before the first contribution makes
  /// it.
  final Future<String?> Function() accountId;
  final DateTime Function() clock;

  /// The waits after a failed attempt, the last one repeated.
  final List<Duration> delays;

  /// A photo of a new place waits this long for the server to place it
  /// (about a second when the place goes straight in).
  final Duration placeWait;

  /// ... and this long between two looks when a moderator holds the place.
  final Duration moderationWait;

  /// How far around an uncertain attempt a contribution found on the server
  /// counts as its own: the clocks of the device and the server differ.
  static const uncertaintyWindow = Duration(minutes: 10);

  final _sent = StreamController<SentContribution>.broadcast();
  final _progress = StreamController<({String id, double sent})>.broadcast();

  /// Every contribution the server accepted.
  Stream<SentContribution> get sent => _sent.stream;

  /// The progress of a photo being sent, by entry.
  Stream<({String id, double sent})> get progress => _progress.stream;

  Future<void> dispose() async {
    await _sent.close();
    await _progress.close();
  }

  /// One pass: every entry that is due, oldest first. [now] lets the user's
  /// "try again" send what waits.
  Future<SendReport> sendDue({bool now = false}) async {
    var account = await accountId();
    if (account != null) await outbox.claimFor(account);
    var sent = 0;
    var failed = 0;
    MyContributions? recent;
    Future<MyContributions> recentOnce() async => recent ??= await api.recent();
    for (var e in await outbox.all()) {
      if (e.state == OutboxState.failed) continue;
      final at = clock();
      if (!now && e.nextAttemptAt != null && e.nextAttemptAt!.isAfter(at))
        continue;
      // Read again for each entry: the account may have gone during the
      // pass (signed out, deleted), and the entry with it, or come with the
      // first contribution, which gave it the waiting entries.
      final current = await outbox.byId(e.id);
      if (current == null) continue;
      e = current;
      account = await accountId();
      // Made under an account the device no longer holds: never sent under
      // another one, nor under a new one made for it.
      if (e.accountId != null && e.accountId != account) {
        await outbox.fail(e.id, code: OutboxError.otherAccount);
        failed++;
        continue;
      }
      // An entry still marked as being sent was cut by the end of the app:
      // its request may have reached the server.
      final unsure = e.uncertain || e.state == OutboxState.sending;
      try {
        // Without an account kept, nothing was sent: a contribution leaves
        // only once the session and its account are stored.
        if (unsure &&
            account != null &&
            !e.kind.idempotent &&
            e.kind != ContributionKind.photo) {
          final found = _alreadySent(e, await recentOnce(), await _taken());
          if (found != null) {
            _log.info(
              '${e.kind.name} ${e.id}: found on the server, not sent again',
            );
            await _accepted(e, found);
            sent++;
            continue;
          }
          // Not there: the lost attempt never landed, and this one starts
          // from a clean slate.
          await outbox.settle(e.id);
        }
        await outbox.markSending(e.id);
        final result = await _send(e, recentOnce);
        if (result is _Held) {
          await outbox.retryAt(
            e.id,
            at.add(result.wait),
            uncertain: false,
            detail: result.why,
          );
          continue;
        }
        await _accepted(e, result);
        sent++;
        // The first contribution made the account: the next entries are
        // its own.
        account ??= await accountId();
        if (account != null) await outbox.claimFor(account);
      } on Object catch (error, stack) {
        final outcome = _classify(e, error, unsure: unsure);
        if (outcome.isDone) {
          await _accepted(e, null);
          sent++;
          continue;
        }
        final code = outcome.code;
        if (code != null) {
          _log.info('${e.kind.name} ${e.id} refused: $error');
          await outbox.fail(e.id, code: code, detail: '$error');
          failed++;
          continue;
        }
        await outbox.retryAt(
          e.id,
          at.add(outcome.wait ?? delays[min(e.attempts, delays.length - 1)]),
          // The request may have reached the server before the connection
          // broke.
          uncertain: !e.kind.idempotent && _mayHaveArrived(error),
          detail: '$error',
        );
        if (outcome.offline) {
          _log.info('outbox: offline ($error); ${e.kind.name} ${e.id} waits');
          // The next pass comes when this entry is due again: the others,
          // still due now, would only meet the same missing network.
          final next = await outbox.byId(e.id);
          return SendReport(
            sent: sent,
            failed: failed,
            offline: true,
            nextAttemptAt: next?.nextAttemptAt ?? await _next(),
          );
        }
        _log.warning(
          '${e.kind.name} ${e.id} not sent, tried again later',
          error,
          stack,
        );
      }
    }
    return SendReport(sent: sent, failed: failed, nextAttemptAt: await _next());
  }

  Future<DateTime?> _next() async {
    DateTime? next;
    for (final e in await outbox.all()) {
      if (e.state == OutboxState.failed) continue;
      final at = e.nextAttemptAt ?? clock();
      if (next == null || at.isBefore(next)) next = at;
    }
    return next;
  }

  Future<Object?> _send(
    PendingContribution e,
    Future<MyContributions> Function() recent,
  ) async {
    // Only a contribution made before the device had an account may make
    // one; the others go as their account or not at all.
    final create = e.accountId == null;
    if (e.kind != ContributionKind.photo) {
      // The device's own marks (`_`) are not variables of the request.
      final variables = {
        for (final MapEntry(:key, :value) in e.payload.entries)
          if (!key.startsWith('_')) key: value,
      };
      return await api.send(e.kind, variables, create: create);
    }
    var placeId = e.payload['placeId'] as String?;
    if (placeId == null) {
      // A photo of a place added with it: it waits for the server to place
      // the new place.
      final submissionId = e.payload['submissionId'] as String?;
      if (submissionId == null) throw const _Refused(OutboxError.placeRefused);
      final submission = (await recent()).submissions
          .where((s) => s.id == submissionId)
          .firstOrNull;
      if (submission == null)
        return _Held(placeWait, 'the new place is not listed yet');
      switch (submission.status) {
        case SubmissionStatus.rejected || SubmissionStatus.withdrawn:
          throw const _Refused(OutboxError.placeRefused);
        case _ when submission.placeId != null:
          placeId = submission.placeId;
          await outbox.updatePayload(e.id, {...e.payload, 'placeId': placeId});
        case SubmissionStatus.proposed:
          return _Held(moderationWait, 'the new place waits for a moderator');
        case _:
          return _Held(placeWait, 'the new place is being placed');
      }
    }
    final fileId = e.fileId;
    final bytes = fileId == null ? null : await outbox.files.read(fileId);
    if (bytes == null) throw const _Refused(OutboxError.fileLost);
    return await api.upload(
      placeId!,
      bytes,
      create: create,
      onProgress: (sent) {
        if (!_progress.isClosed) _progress.add((id: e.id, sent: sent));
      },
    );
  }

  Future<void> _accepted(PendingContribution e, Object? result) async {
    final serverId = switch (result) {
      Confirmation(:final id) ||
      IssueReport(:final id) ||
      PlaceSubmission(:final id) => id,
      _ => null,
    };
    if (serverId != null) await outbox.claim(serverId);
    // The mark may have been set while the request was out: read it again.
    final marked =
        (await outbox.byId(e.id))?.payload[OutboxStore.deleteOnceSent] == true;
    if (marked && result is Review) {
      // Deleted by the user while it was on its way: it goes now that the
      // server has it.
      final review = result;
      await outbox.add(
        ContributionKind.deleteReview,
        payload: {'id': review.id},
        placeId: e.placeId,
        accountId: e.accountId,
      );
    }
    final file = e.fileId;
    if (e.kind == ContributionKind.addPlace &&
        file != null &&
        result is PlaceSubmission) {
      // The photo taken with the new place becomes its own entry, which
      // waits for the server to place the new place.
      await outbox.add(
        ContributionKind.photo,
        payload: {'submissionId': result.id, 'placeId': ?result.placeId},
        placeId: result.placeId,
        fileId: file,
        accountId: e.accountId,
      );
      await outbox.done(e.id, keepFile: true);
    } else {
      await outbox.done(e.id);
    }
    if (!_sent.isClosed) _sent.add(SentContribution(e, result));
  }

  /// The contribution the account already made for [e], if the latest ones
  /// hold it.
  /// A contribution already taken by another entry (accepted lately, or a
  /// new place whose photo waits for it) is never this one's;
  /// among the others, the oldest in the window is.
  Object? _alreadySent(
    PendingContribution e,
    MyContributions recent,
    Set<String> taken,
  ) {
    final attempt = e.attemptStartedAt ?? e.createdAt;
    final since = attempt.subtract(uncertaintyWindow);
    final until = attempt.add(uncertaintyWindow);
    // Within the window around the attempt, on both sides: a later one may
    // come from another device of the account.
    bool free(String id, DateTime at) =>
        !at.isBefore(since) && !at.isAfter(until) && !taken.contains(id);
    T? oldest<T>(Iterable<T> found, DateTime Function(T) at) =>
        (found.toList()..sort((a, b) => at(a).compareTo(at(b)))).firstOrNull;
    return switch (e.kind) {
      ContributionKind.confirm => oldest<Confirmation>(
        recent.confirmations.where(
          (c) =>
              c.placeId == e.placeId &&
              c.status.wire == e.payload['status'] &&
              free(c.id, c.createdAt),
        ),
        (c) => c.createdAt,
      ),
      ContributionKind.reportIssue => oldest<IssueReport>(
        recent.issues.where(
          (i) =>
              i.placeId == e.placeId &&
              i.kind.wire == e.payload['kind'] &&
              free(i.id, i.createdAt),
        ),
        (i) => i.createdAt,
      ),
      ContributionKind.addPlace => oldest<PlaceSubmission>(
        recent.submissions.where(
          (s) => s.kind == SubmissionKind.create && free(s.id, s.createdAt),
        ),
        (s) => s.createdAt,
      ),
      ContributionKind.editPlace => oldest<PlaceSubmission>(
        recent.submissions.where(
          (s) =>
              s.kind == SubmissionKind.edit &&
              s.placeId == e.placeId &&
              free(s.id, s.createdAt),
        ),
        (s) => s.createdAt,
      ),
      _ => null,
    };
  }

  /// The server ids no uncertain entry may take: accepted lately, or
  /// awaited by a photo of a new place.
  Future<Set<String>> _taken() async => {
    ...await outbox.claimed(),
    for (final other in await outbox.all())
      if (other.payload['submissionId'] case final String id) id,
  };

  /// Whether the request may have reached the server before the failure:
  /// not when the connection was never made (no network, no route, a name
  /// that did not resolve), only when it broke or went silent after.
  static bool _mayHaveArrived(Object error) => switch (error) {
    GraphQLRateLimitedException() => false,
    GraphQLNetworkException(:final message) => !_neverConnected(message),
    UploadException(status: 0, :final message) => !_neverConnected(message),
    GraphQLResponseException(transient: true) => true,
    UploadException(:final status) when status >= 500 => true,
    _ => false,
  };

  static bool _neverConnected(String message) {
    final m = message.toLowerCase();
    return const [
      'failed host lookup',
      'connection refused',
      'network is unreachable',
      'no route to host',
      'offline',
    ].any(m.contains);
  }

  _Outcome _classify(
    PendingContribution e,
    Object error, {
    required bool unsure,
  }) {
    switch (error) {
      case _Refused(:final code):
        return _Outcome(code: code);
      case GraphQLRateLimitedException(:final wait):
        return _Outcome(offline: true, wait: wait);
      case AccountLostException():
        // The account this entry was made for is gone from the device.
        return const _Outcome(code: OutboxError.otherAccount);
      case NoAccountException():
        // Its account went during the pass (signed out, deleted): never sent
        // under another. An entry made before any account waits instead.
        return e.accountId != null
            ? const _Outcome(code: OutboxError.otherAccount)
            : const _Outcome();
      case GraphQLNetworkException() || BadChallengeException():
        return const _Outcome(offline: true);
      case GraphQLResponseException(transient: true):
        return const _Outcome();
      case final GraphQLResponseException r:
        if (r.hasCode(GraphQLError.notFound)) {
          return e.kind.deletes
              ? _Outcome.done
              : const _Outcome(code: OutboxError.notFound);
        }
        if (r.hasCode(GraphQLError.forbidden))
          return const _Outcome(code: OutboxError.forbidden);
        if (r.hasCode(GraphQLError.invalidInput))
          return const _Outcome(code: OutboxError.invalid);
        if (r.hasCode(GraphQLError.unauthenticated)) return const _Outcome();
        return const _Outcome(code: OutboxError.other);
      case UploadException(:final transient, :final retryAfter) when transient:
        return _Outcome(offline: true, wait: retryAfter);
      case UploadException(status: 403):
        return const _Outcome(code: OutboxError.forbidden);
      case UploadException(status: 404):
        return const _Outcome(code: OutboxError.notFound);
      case UploadException(status: 413):
        return const _Outcome(code: OutboxError.photoTooLarge);
      case UploadException(status: 422):
        // After an attempt whose answer was lost, "already sent" is this
        // very photo arriving twice.
        return unsure
            ? _Outcome.done
            : const _Outcome(code: OutboxError.unreadablePhoto);
      case UploadException(status: 415):
        return const _Outcome(code: OutboxError.unreadablePhoto);
      case UploadException():
        return const _Outcome(code: OutboxError.other);
      default:
        return const _Outcome(code: OutboxError.other);
    }
  }
}

/// A photo whose place does not exist yet: tried again after [wait].
final class _Held {
  const new(this.wait, this.why);

  final Duration wait;
  final String why;
}

final class _Refused implements Exception {
  const new(this.code);

  final String code;

  @override
  String toString() => code;
}

/// What a failed attempt means: accepted after all ([done]), refused for
/// good ([code]), or to try again (after [wait]; [offline] stops the pass).
final class _Outcome {
  const new({this.code, this.offline = false, this.wait, this.isDone = false});

  static const done = _Outcome(isDone: true);

  final String? code;
  final bool offline;
  final Duration? wait;
  final bool isDone;
}
