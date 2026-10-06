import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lunaway/core/providers.dart';
import 'package:lunaway/features/account/application/account_providers.dart';
import 'package:lunaway/features/account/domain/account.dart';
import 'package:lunaway/features/community/application/community_providers.dart';
import 'package:lunaway/features/community/data/outbox.dart';
import 'package:lunaway/features/community/domain/community.dart';
import 'package:lunaway/features/community/domain/contribution.dart';
import 'package:lunaway/features/community/presentation/community_labels.dart';
import 'package:lunaway/features/community/presentation/contribute.dart';
import 'package:lunaway/features/community/presentation/contribution_sheets.dart';
import 'package:lunaway/features/community/presentation/place_form.dart';
import 'package:lunaway/features/places/application/places_providers.dart';
import 'package:lunaway/features/places/domain/place.dart';
import 'package:lunaway/features/places/domain/place_content.dart';
import 'package:lunaway/i18n/strings.g.dart';
import 'package:lunaway/shared/labels.dart';
import 'package:lunaway/shared/theme/app_icons.dart';
import 'package:lunaway/shared/theme/tokens.dart';

/// What the community says first about a place: "to verify" while two
/// travellers have not confirmed a place someone added, and the problems
/// reported over the last 30 days.
class PlaceCommunityNotes extends ConsumerWidget {
  const new({required this.place, super.key});

  final Place place;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.t;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final issues = place.reportedIssues.where((i) => i.count > 0).toList();
    if (place.verification != Verification.toVerify && issues.isEmpty) {
      return const SizedBox.shrink();
    }
    Widget note({
      required IconData icon,
      required String title,
      required String body,
      required Color background,
      required Color foreground,
      Widget? action,
    }) => Padding(
      padding: const EdgeInsets.only(top: Space.m),
      child: Container(
        padding: const EdgeInsets.all(Space.l),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(LunaTokens.radiusL),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: foreground),
            const SizedBox(width: Space.m),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: theme.textTheme.titleSmall?.copyWith(color: foreground)),
                  const SizedBox(height: Space.hair),
                  Text(body, style: theme.textTheme.bodyMedium?.copyWith(color: foreground)),
                  if (action != null) ...[const SizedBox(height: Space.xs), action],
                ],
              ),
            ),
          ],
        ),
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (place.verification == Verification.toVerify)
          note(
            icon: AppIcons.toVerify,
            title: t.contribute.toVerifyTitle,
            body: t.contribute.toVerifyBody,
            background: scheme.tertiaryContainer,
            foreground: scheme.onTertiaryContainer,
            action: FilledButton.tonal(
              onPressed: () => showConfirmSheet(context, placeId: place.id),
              child: Text(t.contribute.stillThere),
            ),
          ),
        if (issues.isNotEmpty)
          note(
            icon: AppIcons.warning,
            title: t.contribute.issuesTitle,
            body: [
              for (final i in issues)
                t.contribute.issueCount(kind: t.issueKind(i.kind), count: t.number(i.count)),
            ].join('\n'),
            background: scheme.errorContainer,
            foreground: scheme.onErrorContainer,
          ),
      ],
    );
  }
}

/// The place's other actions: a problem met there, a change to suggest, a
/// report to the moderators.
class PlaceMoreMenu extends ConsumerWidget {
  const new({required this.place, super.key});

  final Place place;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.t;
    final scheme = Theme.of(context).colorScheme;
    final direct = ref.watch(trustLevelProvider) >= TrustLevels.editDirectly;
    return PopupMenuButton<String>(
      tooltip: t.contribute.more,
      icon: const Icon(AppIcons.moreVertical),
      style: IconButton.styleFrom(backgroundColor: scheme.surfaceContainerHigh),
      onSelected: (action) async {
        switch (action) {
          case 'issue':
            await showIssueSheet(context, placeId: place.id);
          case 'edit':
            await startEditPlace(context, ref, place);
          case 'report':
            await showReportSheet(
              context,
              target: ReportTarget.place,
              id: place.id,
              placeId: place.id,
            );
        }
      },
      itemBuilder: (context) => [
        PopupMenuItem(
          value: 'issue',
          child: ListTile(
            leading: const Icon(AppIcons.warning),
            title: Text(t.contribute.reportIssue),
          ),
        ),
        PopupMenuItem(
          value: 'edit',
          child: ListTile(
            leading: const Icon(AppIcons.rename),
            title: Text(direct ? t.contribute.editPlace : t.contribute.proposeEdit),
          ),
        ),
        PopupMenuItem(
          value: 'report',
          child: ListTile(
            leading: const Icon(AppIcons.report),
            title: Text(t.contribute.reportPlace),
          ),
        ),
      ],
    );
  }
}

/// The account's own rating or review of a place: the server's, with what
/// waits in the outbox laid over it.
@immutable
final class OwnReview {
  const new({this.stars, this.text, this.review, this.pending = false});

  final int? stars;
  final String? text;

  /// The server's review, to edit or delete; null while only a pending
  /// one exists.
  final Review? review;

  /// Not sent yet.
  final bool pending;

  static OwnReview? of(Review? server, List<PendingContribution> waiting) {
    for (final e in waiting.reversed) {
      // A refused one waits for nothing: the place shows what the server
      // holds, and "My contributions" says why it was refused.
      if (e.failed) continue;
      // Deleted while it was being sent: gone, as far as the user goes.
      if (e.payload[OutboxStore.deleteOnceSent] == true) return null;
      switch (e.kind) {
        case ContributionKind.deleteReview:
          return null;
        case ContributionKind.review:
          return OwnReview(
            stars: e.payload['stars'] as int?,
            text: e.payload['text'] as String?,
            review: server,
            pending: true,
          );
        case ContributionKind.rate:
          return OwnReview(
            stars: e.payload['stars'] as int?,
            text: server?.text,
            review: server,
            pending: true,
          );
        case _:
          continue;
      }
    }
    if (server == null) return null;
    return OwnReview(stars: server.rating, text: server.text, review: server);
  }
}

/// "Your rating" in one tap on a star, and the way to write (or edit) a
/// review, with the review the account already wrote.
class YourReview extends ConsumerWidget {
  const new({required this.place, super.key});

  final Place place;

  Future<void> _rate(BuildContext context, int stars) => submitContribution(
    context,
    ContributionKind.rate,
    placeId: place.id,
    payload: {'placeId': place.id, 'stars': stars},
  );

  Future<void> _write(BuildContext context, WidgetRef ref, OwnReview? own) async {
    final t = context.t;
    if (!await passesGate(context, ref, level: TrustLevels.review, title: t.gate.review)) return;
    if (!context.mounted) return;
    await showReviewSheet(
      context,
      placeId: place.id,
      existing: own?.review == null && own == null
          ? null
          : Review(
              id: own?.review?.id ?? '',
              sourceId: communityCcBySourceId,
              createdAt: own?.review?.createdAt ?? ref.read(clockProvider)(),
              rating: own?.stars,
              text: own?.text,
              visitedAt: own?.review?.visitedAt,
              authorVehicle: own?.review?.authorVehicle,
            ),
    );
  }

  Future<void> _delete(BuildContext context, OwnReview own) async {
    final t = context.t;
    final hasText = own.text != null;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(hasText ? t.contribute.deleteReviewTitle : t.contribute.deleteRatingTitle),
        content: Text(hasText ? t.contribute.deleteReviewBody : t.contribute.deleteRatingBody),
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
    final container = ProviderScope.containerOf(context, listen: false);
    final store = container.read(outboxStoreProvider);
    // What still waits is simply dropped; what the server has is deleted
    // there. One already on its way is marked: the sender deletes it as
    // soon as the server has it, even after a failed attempt or a restart.
    for (final e in container.read(pendingForPlaceProvider(place.id))) {
      if (e.kind != ContributionKind.rate && e.kind != ContributionKind.review) continue;
      if (e.state == OutboxState.sending) {
        await store.updatePayload(e.id, {...e.payload, OutboxStore.deleteOnceSent: true});
      } else {
        await store.discard(e.id);
      }
    }
    final id = own.review?.id;
    if (id == null || !context.mounted) return;
    await submitContribution(
      context,
      ContributionKind.deleteReview,
      placeId: place.id,
      payload: {'id': id},
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.t;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final server = ref.watch(placeExtrasProvider(place.id)).value?.myReview;
    final waiting = ref.watch(pendingForPlaceProvider(place.id));
    final own = OwnReview.of(server, waiting);
    final hasText = own?.text != null;
    final status = own?.review?.status;
    return Container(
      padding: const EdgeInsets.fromLTRB(Space.l, Space.m, Space.l, Space.m),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(LunaTokens.radiusL),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(t.contribute.yourRating, style: theme.textTheme.titleMedium)),
              if (own?.pending ?? false)
                _Tag(icon: AppIcons.waiting, label: t.contribute.pendingSend),
            ],
          ),
          StarPicker(value: own?.stars, onChanged: (stars) => _rate(context, stars), size: 34),
          if (own == null)
            Text(
              t.contribute.rateHint,
              style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
          if (hasText) ...[
            const SizedBox(height: Space.s),
            Text(own!.text!, style: theme.textTheme.bodyLarge),
            if (status != null && status != ContributionStatus.published)
              Padding(
                padding: const EdgeInsets.only(top: Space.xs),
                child: _Tag(
                  icon: AppIcons.waiting,
                  label: switch (status) {
                    ContributionStatus.pending => t.contribute.statusPending,
                    ContributionStatus.hidden => t.contribute.statusHidden,
                    _ => t.contribute.statusRemoved,
                  },
                ),
              ),
          ],
          const SizedBox(height: Space.s),
          Wrap(
            spacing: Space.s,
            runSpacing: Space.xs,
            children: [
              OutlinedButton.icon(
                onPressed: () => _write(context, ref, own),
                icon: const Icon(AppIcons.writeReview),
                label: Text(hasText ? t.contribute.editReview : t.contribute.writeReview),
              ),
              if (own != null)
                TextButton.icon(
                  onPressed: () => _delete(context, own),
                  icon: const Icon(AppIcons.delete),
                  label: Text(hasText ? t.contribute.deleteReview : t.contribute.deleteRating),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  const new({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Space.s, vertical: Space.xxs),
      decoration: BoxDecoration(
        color: scheme.secondaryContainer,
        borderRadius: BorderRadius.circular(LunaTokens.radiusPill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: scheme.onSecondaryContainer),
          const SizedBox(width: Space.xxs),
          Flexible(
            child: Text(
              label,
              style: theme.textTheme.labelMedium?.copyWith(color: scheme.onSecondaryContainer),
            ),
          ),
        ],
      ),
    );
  }
}

/// The menu of a review by someone else: report it, or hide its author.
class ReviewMenu extends ConsumerWidget {
  const new({required this.review, this.placeId, super.key});

  final Review review;
  final String? placeId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.t;
    final account = ref.watch(accountControllerProvider);
    final mine = account is SignedIn && account.account.id == review.authorId;
    final author = review.authorId;
    final name = review.authorName;
    if (mine || !isLunawayCommunity(review.sourceId)) return const SizedBox.shrink();
    return PopupMenuButton<String>(
      tooltip: t.contribute.more,
      icon: const Icon(AppIcons.moreVertical),
      onSelected: (action) async {
        if (action == 'report') {
          await showReportSheet(
            context,
            target: ReportTarget.review,
            id: review.id,
            placeId: placeId,
          );
        } else if (author != null && name != null) {
          await confirmMute(context, ref, Author(id: author, pseudonym: name));
        }
      },
      itemBuilder: (context) => [
        PopupMenuItem(
          value: 'report',
          child: ListTile(leading: const Icon(AppIcons.report), title: Text(t.reportSheet.review)),
        ),
        if (author != null && name != null)
          PopupMenuItem(
            value: 'mute',
            child: ListTile(
              leading: const Icon(AppIcons.muted),
              title: Text(t.reportSheet.mute(name: name)),
            ),
          ),
      ],
    );
  }
}
