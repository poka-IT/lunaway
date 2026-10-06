import 'dart:async';
import 'dart:typed_data';

import 'package:collection/collection.dart';
import 'package:flutter/widgets.dart';
import 'package:logging/logging.dart';
import 'package:lunaway/core/providers.dart';
import 'package:lunaway/features/account/application/account_providers.dart';
import 'package:lunaway/features/account/domain/account.dart';
import 'package:lunaway/features/community/data/community_api.dart';
import 'package:lunaway/features/community/data/community_operations.dart';
import 'package:lunaway/features/community/data/outbox.dart';
import 'package:lunaway/features/community/data/outbox_sender.dart';
import 'package:lunaway/features/community/data/pending_files.dart';
import 'package:lunaway/features/community/data/pending_files_io.dart'
    if (dart.library.js_interop) 'package:lunaway/features/community/data/pending_files_web.dart';
import 'package:lunaway/features/community/data/photo_prepare.dart';
import 'package:lunaway/features/community/data/photo_prepare_io.dart'
    if (dart.library.js_interop) 'package:lunaway/features/community/data/photo_prepare_web.dart';
import 'package:lunaway/features/community/data/photo_upload.dart';
import 'package:lunaway/features/community/data/picture_picker.dart';
import 'package:lunaway/features/community/data/picture_picker_io.dart'
    if (dart.library.js_interop) 'package:lunaway/features/community/data/picture_picker_web.dart';
import 'package:lunaway/features/community/domain/contribution.dart';
import 'package:lunaway/features/places/application/places_providers.dart';
import 'package:lunaway/features/places/domain/place_content.dart';
import 'package:lunaway/features/poi/application/poi_providers.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'community_providers.g.dart';

final _log = Logger('outbox');

// keepAlive: the store of the photos waiting to be sent, one for the run.
@Riverpod(keepAlive: true)
PendingFiles pendingFiles(Ref ref) => platformPendingFiles(ref.watch(userDatabaseProvider));

// keepAlive: a stateless service; tests replace it.
@Riverpod(keepAlive: true)
PicturePicker picturePicker(Ref ref) => platformPicturePicker();

// keepAlive: a stateless service; tests replace it.
@Riverpod(keepAlive: true)
PhotoPreparer photoPreparer(Ref ref) => platformPhotoPreparer();

/// The bytes of a photo waiting in the outbox, for its tile.
@riverpod
Future<Uint8List?> pendingPhoto(Ref ref, String fileId) =>
    ref.watch(pendingFilesProvider).read(fileId);

// keepAlive: a store over the app-wide database.
@Riverpod(keepAlive: true)
OutboxStore outboxStore(Ref ref) => OutboxStore(
  ref.watch(userDatabaseProvider),
  files: ref.watch(pendingFilesProvider),
  clock: ref.watch(clockProvider),
);

// keepAlive: a stateless client over the shared HTTP client.
@Riverpod(keepAlive: true)
PhotoUploader photoUploader(Ref ref) {
  final base = ref.watch(appConfigProvider).apiBase;
  return PhotoUploader(
    client: ref.watch(httpClientProvider),
    endpoint: base.replace(path: '${base.path}/upload'),
    userAgent: ref.watch(userAgentProvider),
  );
}

// keepAlive: a stateless service over the account's session.
@Riverpod(keepAlive: true)
CommunityApi communityApi(Ref ref) => GraphQLCommunityApi(
  account: ref.watch(accountServiceProvider),
  uploader: ref.watch(photoUploaderProvider),
);

// keepAlive: one sender for the run, whose streams the screens follow.
@Riverpod(keepAlive: true)
OutboxSender outboxSender(Ref ref) {
  final account = ref.watch(accountServiceProvider);
  final sender = OutboxSender(
    outbox: ref.watch(outboxStoreProvider),
    api: ref.watch(communityApiProvider),
    accountId: () async => (await account.restore())?.account.id,
    clock: ref.watch(clockProvider),
  );
  ref.onDispose(sender.dispose);
  return sender;
}

/// Every contribution waiting, oldest first.
@riverpod
Stream<List<PendingContribution>> outboxEntries(Ref ref) => ref.watch(outboxStoreProvider).watch();

/// The entries of the account this device holds, and those made before it
/// had one: another account's (a restored backup, a lost account) count
/// nowhere, and "My contributions" lists them for discarding.
@riverpod
List<PendingContribution> ownOutboxEntries(Ref ref) {
  final account = ref.watch(accountControllerProvider);
  final id = account is SignedIn ? account.account.id : null;
  return [
    for (final e in ref.watch(outboxEntriesProvider).value ?? const <PendingContribution>[])
      if (e.accountId == null || e.accountId == id) e,
  ];
}

/// The contributions waiting about [placeId], for the place's sheet.
@riverpod
List<PendingContribution> pendingForPlace(Ref ref, String placeId) => [
  for (final e in ref.watch(ownOutboxEntriesProvider))
    if (e.placeId == placeId) e,
];

/// The progress of each photo being sent, by outbox entry, 0 to 1.
@riverpod
Stream<Map<String, double>> uploadProgress(Ref ref) async* {
  final progress = <String, double>{};
  final updates = ref.watch(outboxSenderProvider).progress;
  yield const {};
  await for (final p in updates) {
    progress[p.id] = p.sent;
    yield Map.of(progress);
  }
}

/// The authors hidden from this device: the account's mutes, with the ones
/// waiting to be sent applied at once.
@riverpod
Set<String> mutedAuthorIds(Ref ref) {
  final account = ref.watch(accountControllerProvider);
  final muted = {if (account is SignedIn) ...account.muted.map((a) => a.id)};
  for (final e in ref.watch(ownOutboxEntriesProvider)) {
    // A refused mute hides nobody.
    if (e.failed) continue;
    final id = e.payload['id'];
    if (id is! String) continue;
    if (e.kind == ContributionKind.mute) muted.add(id);
    if (e.kind == ContributionKind.unmute) muted.remove(id);
  }
  return muted;
}

/// Runs the outbox: sends at launch, when a contribution is queued, when
/// the app comes back to the foreground, when a sync shows the network is
/// back, and when an entry's wait is over. One pass at a time.
// keepAlive: the queue outlives every screen.
@Riverpod(keepAlive: true)
class OutboxRunner extends _$OutboxRunner {
  AppLifecycleListener? _lifecycle;
  Timer? _timer;
  Future<void>? _running;

  /// The callers that asked while a pass ran: they wait for the next one,
  /// which sees what they queued.
  Completer<void>? _waiting;
  bool _now = false;
  StreamSubscription<SentContribution>? _sent;

  /// Whether a pass is under way.
  @override
  bool build() {
    ref.onDispose(() {
      _timer?.cancel();
      _lifecycle?.dispose();
      unawaited(_sent?.cancel());
    });
    // A sync that succeeds says the network is back.
    ref.listen(syncControllerProvider, (previous, next) {
      if (next is SyncDone && previous is! SyncDone) unawaited(kick());
    });
    return false;
  }

  /// Starts the automatic passes; later calls do nothing.
  void start() {
    if (_lifecycle != null) return;
    _lifecycle = AppLifecycleListener(onResume: () => unawaited(kick()));
    _sent = ref.read(outboxSenderProvider).sent.listen(_onSent);
    unawaited(kick());
  }

  /// Queues a contribution and tries to send it now. [deleting], for a
  /// deletion, is the contribution it deletes: the entry that may have made
  /// it goes first (see [mayHaveMade]), unless an entry is already known to
  /// have made it.
  Future<PendingContribution?> enqueue(
    ContributionKind kind, {
    required Map<String, Object?> payload,
    String? placeId,
    String? fileId,
    Object? deleting,
  }) async {
    final account = ref.read(accountControllerProvider);
    final store = ref.read(outboxStoreProvider);
    // A contribution accepted lately for a known entry, or awaited by a
    // photo, was not made by a waiting one: none goes for it.
    final taken = {
      ...await store.claimed(),
      for (final e in await store.all())
        if (e.payload['submissionId'] case final String id) id,
    };
    if (deleting != null && !taken.contains(payload['id'])) {
      if (await store.forgetMakerOf((e) => mayHaveMade(e, deleting))) {
        _log.info('outbox: the entry that made what is deleted dropped');
      }
    }
    final entry = await store.add(
      kind,
      payload: payload,
      placeId: placeId,
      fileId: fileId,
      accountId: account is SignedIn ? account.account.id : null,
    );
    unawaited(kick());
    return entry;
  }

  /// Sends what is due; with [now], what waits too (the user asked). The
  /// future completes after a pass that began after this call, so an entry
  /// queued just before is settled by then.
  Future<void> kick({bool now = false}) {
    _now = _now || now;
    if (_running != null) return (_waiting ??= Completer<void>()).future;
    return _running = _loop();
  }

  Future<void> _loop() async {
    try {
      while (ref.mounted) {
        final waiting = _waiting;
        _waiting = null;
        final now = _now;
        _now = false;
        await _pass(now: now);
        waiting?.complete();
        if (_waiting == null) break;
      }
    } finally {
      _running = null;
      final left = _waiting;
      _waiting = null;
      left?.complete();
    }
  }

  Future<void> _pass({required bool now}) async {
    _timer?.cancel();
    if (ref.mounted) state = true;
    SendReport? report;
    try {
      report = await ref.read(outboxSenderProvider).sendDue(now: now);
    } on Object catch (e, st) {
      _log.warning('outbox pass failed', e, st);
    }
    if (!ref.mounted) return;
    state = false;
    final next = report?.nextAttemptAt;
    if (next != null) {
      final wait = next.difference(ref.read(clockProvider)());
      _timer = Timer(wait.isNegative ? const Duration(seconds: 1) : wait, () => unawaited(kick()));
    }
  }

  void _onSent(SentContribution sent) {
    if (!ref.mounted) return;
    final e = sent.entry;
    final placeId = e.placeId;
    final extras = ref.read(placeExtrasRepositoryProvider);
    switch (e.kind) {
      case ContributionKind.rate || ContributionKind.review || ContributionKind.deleteReview:
        // The server's answer is the account's review as it now stands: the
        // place shows it at once; the next read brings the rest.
        if (placeId != null) {
          final review = sent.result is Review ? sent.result! as Review : null;
          unawaited(
            extras.putMyReview(placeId, review).then((_) {
              if (ref.mounted) ref.invalidate(placeExtrasProvider(placeId));
            }),
          );
        }
      case ContributionKind.photo || ContributionKind.deletePhoto:
        if (placeId != null) {
          unawaited(
            extras.forget(placeId).then((_) {
              if (ref.mounted) ref.invalidate(placeExtrasProvider(placeId));
            }),
          );
        }
      case ContributionKind.mute || ContributionKind.unmute:
        // Every place read with the old mutes: read again with the new.
        unawaited(extras.forgetAll());
      case ContributionKind.confirm ||
          ContributionKind.reportIssue ||
          ContributionKind.addPlace ||
          ContributionKind.editPlace:
        // The worker writes what the community said in a second or so; the
        // next sync brings it to the map.
        Timer(const Duration(seconds: 3), () {
          if (ref.mounted) unawaited(ref.read(syncControllerProvider.notifier).sync());
        });
      case ContributionKind.deleteConfirmation ||
          ContributionKind.deleteIssueReport ||
          ContributionKind.reportContent ||
          ContributionKind.deletePlaceSubmission ||
          ContributionKind.addVendingMachine:
        break;
      case ContributionKind.confirmPoi:
        // The page shows when the point was last said to be there: read it
        // again.
        if (e.payload['poiId'] case final String poiId) {
          unawaited(
            ref.read(poiRepositoryProvider).forgetPage(poiId).then((_) {
              if (ref.mounted) ref.invalidate(poiPageProvider(poiId));
            }),
          );
        }
    }
    ref.invalidate(myContributionsProvider);
    // Contributions move the level: read it again.
    unawaited(ref.read(accountControllerProvider.notifier).refresh());
  }
}

/// The account's own contributions, read online.
@Riverpod(retry: noRetry)
Future<MyContributions> myContributions(Ref ref) =>
    // The latest twenty of each kind: the page says when there are more.
    ref.watch(accountServiceProvider).run(myContributionsOperation, variables: {'first': 20});

/// What the device holds of the account's level for an action: whether it
/// may do it now, and the level it needs.
@immutable
final class Gate {
  const new({required this.allowed, required this.required, required this.level, this.next});

  final bool allowed;
  final int required;
  final int level;

  /// What the account's next level needs, when known.
  final NextLevel? next;
}

/// Whether the device's account may do an action of level [required]; a
/// device without an account counts as level 0, the level a new account
/// starts at.
@riverpod
Gate gate(Ref ref, int required) {
  final account = ref.watch(accountControllerProvider);
  final level = account is SignedIn ? account.account.trustLevel : 0;
  return Gate(
    allowed: level >= required,
    required: required,
    level: level,
    next: account is SignedIn ? account.account.nextLevel : null,
  );
}

/// The failed entries first, for the profile's list.
List<PendingContribution> byAttention(List<PendingContribution> entries) =>
    entries.sorted((a, b) => (b.failed ? 1 : 0).compareTo(a.failed ? 1 : 0));
