import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:lunaway/core/providers.dart';
import 'package:lunaway/features/community/application/community_providers.dart';
import 'package:lunaway/features/community/data/community_operations.dart';
import 'package:lunaway/features/community/domain/community.dart';
import 'package:lunaway/features/community/domain/contribution.dart';
import 'package:lunaway/features/community/presentation/community_labels.dart';
import 'package:lunaway/features/community/presentation/contribute.dart';
import 'package:lunaway/features/places/application/places_providers.dart';
import 'package:lunaway/features/places/domain/place_content.dart';
import 'package:lunaway/i18n/strings.g.dart';
import 'package:lunaway/shared/images/cached_image.dart';
import 'package:lunaway/shared/images/thumbhash.dart';
import 'package:lunaway/shared/labels.dart';
import 'package:lunaway/shared/theme/app_icons.dart';
import 'package:lunaway/shared/theme/tokens.dart';
import 'package:lunaway/shared/widgets/night_scene.dart';
import 'package:lunaway/shared/widgets/status_views.dart';
import 'package:lunaway/shared/widgets/sub_page.dart';

/// Everything the account contributed, each deletable on its own, with
/// what still waits on this device first.
class ContributionsScreen extends ConsumerWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.t;
    final pending = byAttention(ref.watch(outboxEntriesProvider).value ?? const []);
    final mine = ref.watch(myContributionsProvider);
    return SubPage(
      title: t.mine.title,
      children: [
        if (pending.isNotEmpty) ...[_Pending(entries: pending), const SizedBox(height: Space.xl)],
        switch (mine) {
          AsyncData(:final value) => _Published(mine: value),
          AsyncError() => MessageView(
            mood: SceneMood.offline,
            title: t.mine.error,
            action: t.common.retry,
            onAction: () => ref.invalidate(myContributionsProvider),
            compact: true,
          ),
          AsyncLoading() => const Column(
            children: [SkeletonTile(), SkeletonTile(), SkeletonTile()],
          ),
        },
      ],
    );
  }
}

/// "The latest 20 of 34" when the page shows only part of a kind.
String? _latest(Translations t, int shown, int total) =>
    total > shown ? t.mine.latest(shown: t.number(shown), total: t.number(total)) : null;

Widget _heading(BuildContext context, String text, {String? hint}) {
  final theme = Theme.of(context);
  return Padding(
    padding: const EdgeInsets.only(left: Space.xs, bottom: Space.s, top: Space.l),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(header: true, child: Text(text, style: theme.textTheme.titleLarge)),
        if (hint != null)
          Text(
            hint,
            style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
      ],
    ),
  );
}

/// The contributions still on this device: what waits, what is under way,
/// what the server refused and why, with "try again" and "give up".
class _Pending extends ConsumerWidget {
  const new({required this.entries});

  final List<PendingContribution> entries;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.t;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final store = ref.read(outboxStoreProvider);
    final runner = ref.read(outboxRunnerProvider.notifier);
    final sending = ref.watch(outboxRunnerProvider);
    final progress = ref.watch(uploadProgressProvider).value ?? const <String, double>{};
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _heading(context, t.mine.pending, hint: t.mine.pendingHint),
        SectionCard(
          child: Column(
            children: [
              for (final e in entries)
                Consumer(
                  builder: (context, ref, _) {
                    final placeName = e.placeId == null
                        ? null
                        : switch (ref.watch(placeProvider(e.placeId!)).value) {
                            final p? => t.placeTitle(
                              name: p.name,
                              kind: p.kind,
                              city: p.address?.city,
                            ),
                            null => null,
                          };
                    final share = progress[e.id];
                    final status = e.failed
                        ? t.outboxError(e.errorCode)
                        : e.state == OutboxState.sending && share != null
                        ? t.photoFlow.sending(percent: '${(share * 100).round()}')
                        : e.state == OutboxState.sending
                        ? t.outbox.sending
                        : t.outbox.waiting;
                    return ListTile(
                      leading: Icon(
                        e.failed ? AppIcons.error : AppIcons.waiting,
                        color: e.failed ? scheme.error : scheme.onSurfaceVariant,
                      ),
                      title: Text(t.pendingLabel(e)),
                      subtitle: Text(
                        [?placeName, status].join('\n'),
                        style: e.failed ? TextStyle(color: scheme.error) : null,
                      ),
                      isThreeLine: placeName != null,
                      trailing: PopupMenuButton<String>(
                        tooltip: t.contribute.more,
                        icon: const Icon(AppIcons.moreVertical),
                        onSelected: (action) async {
                          if (action == 'retry') {
                            await store.retryNow(e.id);
                            await runner.kick(now: true);
                          } else if (action == 'discard' && context.mounted) {
                            final ok = await showDialog<bool>(
                              context: context,
                              builder: (context) => AlertDialog(
                                title: Text(t.mine.discardTitle),
                                content: Text(t.mine.discardBody),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.of(context).pop(false),
                                    child: Text(t.common.cancel),
                                  ),
                                  FilledButton(
                                    onPressed: () => Navigator.of(context).pop(true),
                                    child: Text(t.mine.discard),
                                  ),
                                ],
                              ),
                            );
                            if (ok ?? false) await store.discard(e.id);
                          }
                        },
                        itemBuilder: (context) => [
                          PopupMenuItem(
                            value: 'retry',
                            child: ListTile(
                              leading: const Icon(AppIcons.retry),
                              title: Text(e.failed ? t.mine.retry : t.mine.sendNow),
                            ),
                          ),
                          PopupMenuItem(
                            value: 'discard',
                            child: ListTile(
                              leading: const Icon(AppIcons.delete),
                              title: Text(t.mine.discard),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
            ],
          ),
        ),
        const SizedBox(height: Space.s),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: sending ? null : () => runner.kick(now: true),
            icon: const Icon(AppIcons.uploading),
            label: Text(t.mine.sendNow),
          ),
        ),
      ],
    );
  }
}

/// What the server holds: reviews and ratings, photos, confirmations,
/// reported problems, places added and edits; each with its status and a
/// delete.
class _Published extends ConsumerWidget {
  const new({required this.mine});

  final MyContributions mine;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.t;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final locale = t.$meta.locale.languageCode;
    String date(DateTime d) => DateFormat.yMMMd(locale).format(d.toLocal());
    final empty =
        mine.reviews.isEmpty &&
        mine.photos.isEmpty &&
        mine.confirmations.isEmpty &&
        mine.issues.isEmpty &&
        mine.submissions.isEmpty;
    if (empty) {
      return MessageView(
        mood: SceneMood.saved,
        title: t.mine.empty,
        hint: t.mine.emptyHint,
        compact: true,
      );
    }

    Future<void> delete(ContributionKind kind, String id, {String? placeId, String? body}) async {
      final ok = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(t.mine.deleteTitle),
          content: Text(body ?? t.mine.deleteBody),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(t.common.cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(t.common.delete),
            ),
          ],
        ),
      );
      if (!(ok ?? false) || !context.mounted) return;
      await submitContribution(
        context,
        kind,
        placeId: placeId,
        payload: {'id': id},
        sentText: t.mine.deleted,
      );
    }

    Widget deleteButton(VoidCallback onPressed) => IconButton(
      tooltip: t.common.delete,
      icon: const Icon(AppIcons.delete),
      onPressed: onPressed,
    );

    Widget placeLine(String? placeId) {
      if (placeId == null) return Text(t.mine.aPlace);
      return Consumer(
        builder: (context, ref, _) => Text(switch (ref.watch(placeProvider(placeId)).value) {
          final p? => t.placeTitle(name: p.name, kind: p.kind, city: p.address?.city),
          null => t.mine.aPlace,
        }),
      );
    }

    Widget status(ContributionStatus? s) => s == null || s == ContributionStatus.published
        ? const SizedBox.shrink()
        : Text(
            t.contributionStatus(s),
            style: theme.textTheme.labelMedium?.copyWith(
              color: s == ContributionStatus.pending ? scheme.onSurfaceVariant : scheme.error,
            ),
          );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (mine.reviews.isNotEmpty) ...[
          _heading(
            context,
            t.mine.reviews,
            hint: _latest(t, mine.reviews.length, mine.reviewTotal),
          ),
          SectionCard(
            child: Column(
              children: [
                for (final r in mine.reviews)
                  ListTile(
                    leading: const Icon(AppIcons.star),
                    title: placeLine(r.placeId),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          [
                            if (r.rating != null) t.place.stars(rating: '${r.rating}'),
                            date(r.createdAt),
                          ].join(' · '),
                        ),
                        Text(
                          r.text ?? t.mine.ratingOnly,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        status(r.status),
                      ],
                    ),
                    trailing: deleteButton(
                      () => delete(ContributionKind.deleteReview, r.id, placeId: r.placeId),
                    ),
                  ),
              ],
            ),
          ),
        ],
        if (mine.photos.isNotEmpty) ...[
          _heading(context, t.mine.photos, hint: _latest(t, mine.photos.length, mine.photoTotal)),
          Wrap(
            spacing: Space.s,
            runSpacing: Space.s,
            children: [
              for (final p in mine.photos)
                _MyPhoto(photo: p, onDelete: () => delete(ContributionKind.deletePhoto, p.id)),
            ],
          ),
        ],
        if (mine.confirmations.isNotEmpty) ...[
          _heading(
            context,
            t.mine.confirmations,
            hint: _latest(t, mine.confirmations.length, mine.confirmationTotal),
          ),
          SectionCard(
            child: Column(
              children: [
                for (final c in mine.confirmations)
                  ListTile(
                    leading: const Icon(AppIcons.confirmed),
                    title: placeLine(c.placeId),
                    subtitle: Text('${t.confirmationStatus(c.status)} · ${date(c.createdAt)}'),
                    trailing: deleteButton(
                      () => delete(ContributionKind.deleteConfirmation, c.id, placeId: c.placeId),
                    ),
                  ),
              ],
            ),
          ),
        ],
        if (mine.issues.isNotEmpty) ...[
          _heading(context, t.mine.issues, hint: _latest(t, mine.issues.length, mine.issueTotal)),
          SectionCard(
            child: Column(
              children: [
                for (final i in mine.issues)
                  ListTile(
                    leading: Icon(AppIcons.issue(i.kind)),
                    title: placeLine(i.placeId),
                    subtitle: Text('${t.issueKind(i.kind)} · ${date(i.createdAt)}'),
                    trailing: deleteButton(
                      () => delete(ContributionKind.deleteIssueReport, i.id, placeId: i.placeId),
                    ),
                  ),
              ],
            ),
          ),
        ],
        if (mine.submissions.isNotEmpty) ...[
          _heading(
            context,
            t.mine.places,
            hint: _latest(t, mine.submissions.length, mine.submissionTotal),
          ),
          SectionCard(
            child: Column(
              children: [
                for (final s in mine.submissions)
                  ListTile(
                    leading: Icon(
                      s.kind == SubmissionKind.create ? AppIcons.addPlace : AppIcons.rename,
                    ),
                    title: s.placeId == null
                        ? Text(s.kind == SubmissionKind.create ? t.mine.newPlace : t.mine.edit)
                        : placeLine(s.placeId),
                    subtitle: Text(
                      [
                        if (s.kind == SubmissionKind.create) t.mine.newPlace else t.mine.edit,
                        t.submissionStatus(s.status),
                        date(s.createdAt),
                      ].join(' · '),
                    ),
                    trailing:
                        s.status == SubmissionStatus.withdrawn ||
                            s.status == SubmissionStatus.rejected
                        ? null
                        : deleteButton(
                            () => delete(
                              ContributionKind.deletePlaceSubmission,
                              s.id,
                              body: s.status == SubmissionStatus.applied
                                  ? t.mine.deleteApplied
                                  : null,
                            ),
                          ),
                  ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _MyPhoto extends ConsumerWidget {
  const new({required this.photo, required this.onDelete});

  final Photo photo;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.t;
    final theme = Theme.of(context);
    final hash = photo.thumbhash;
    final status = photo.status;
    return SizedBox(
      width: 148,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(LunaTokens.radiusM),
            child: Stack(
              children: [
                SizedBox(
                  width: 148,
                  height: 111,
                  child: Image(
                    image: ResizeImage(
                      CachedImage(photo.thumbUrl, fetcher: ref.watch(imageFetcherProvider)),
                      width: 400,
                    ),
                    fit: BoxFit.cover,
                    excludeFromSemantics: true,
                    frameBuilder: (context, child, frame, _) => frame != null || hash == null
                        ? child
                        : Image(image: ThumbHashImage(hash), fit: BoxFit.cover),
                    errorBuilder: (context, _, _) => hash == null
                        ? ColoredBox(color: theme.colorScheme.surfaceContainerHigh)
                        : Image(image: ThumbHashImage(hash), fit: BoxFit.cover),
                  ),
                ),
                Positioned(
                  right: Space.xxs,
                  top: Space.xxs,
                  child: IconButton.filledTonal(
                    tooltip: t.common.delete,
                    icon: const Icon(AppIcons.delete),
                    onPressed: onDelete,
                  ),
                ),
              ],
            ),
          ),
          if (status != null && status != ContributionStatus.published)
            Text(t.contributionStatus(status), style: theme.textTheme.labelMedium),
        ],
      ),
    );
  }
}
