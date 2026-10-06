import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lunaway/core/external_actions.dart';
import 'package:lunaway/core/providers.dart';
import 'package:lunaway/core/time/place_zone.dart';
import 'package:lunaway/features/community/presentation/contribution_sheets.dart';
import 'package:lunaway/features/community/presentation/place_community.dart';
import 'package:lunaway/features/map/application/map_state.dart';
import 'package:lunaway/features/places/application/places_providers.dart';
import 'package:lunaway/features/places/domain/opening.dart';
import 'package:lunaway/features/places/domain/place.dart';
import 'package:lunaway/features/places/domain/place_content.dart';
import 'package:lunaway/features/places/domain/taxonomy.dart';
import 'package:lunaway/features/places/presentation/coordinates_card.dart';
import 'package:lunaway/features/places/presentation/place_actions.dart';
import 'package:lunaway/features/places/presentation/place_extras_view.dart';
import 'package:lunaway/features/places/presentation/rating_text.dart';
import 'package:lunaway/features/poi/presentation/place_surroundings.dart';
import 'package:lunaway/i18n/strings.g.dart';
import 'package:lunaway/shared/labels.dart';
import 'package:lunaway/shared/messages.dart';
import 'package:lunaway/shared/source_names.dart';
import 'package:lunaway/shared/theme/app_icons.dart';
import 'package:lunaway/shared/theme/tokens.dart';
import 'package:lunaway/shared/theme/typography.dart';
import 'package:lunaway/shared/widgets/night_badge.dart';
import 'package:lunaway/shared/widgets/night_scene.dart';
import 'package:lunaway/shared/widgets/place_hero.dart';
import 'package:lunaway/shared/widgets/source_badge.dart';
import 'package:lunaway/shared/widgets/status_views.dart';

/// Everything about one place, for the bottom sheet (compact) and the side
/// panel (wider). The night comes first, as a moon: it is what a traveller
/// looks for. With [actions], the action bar sits at the foot of the
/// content (a panel); on a phone the layout puts it where the dock was.
class PlaceDetails extends ConsumerWidget {
  const new({
    required this.placeId,
    this.scrollController,
    this.onClose,
    this.actions = false,
    this.bottomPadding = Space.huge,
    super.key,
  });

  final String placeId;
  final ScrollController? scrollController;
  final VoidCallback? onClose;
  final bool actions;
  final double bottomPadding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.t;
    return switch (ref.watch(placeProvider(placeId))) {
      AsyncValue(:final value, hasValue: true) when value != null =>
        actions
            ? Column(
                children: [
                  Expanded(
                    child: PlaceDetailsBody(
                      place: value,
                      scrollController: scrollController,
                      onClose: onClose,
                      bottomPadding: bottomPadding,
                    ),
                  ),
                  PlaceActionBar(place: value),
                ],
              )
            : PlaceDetailsBody(
                place: value,
                scrollController: scrollController,
                onClose: onClose,
                bottomPadding: bottomPadding,
              ),
      // Not on the device yet while the first download runs (a shared link
      // opened at first launch): it arrives with the download, and the page
      // follows the stored place, so it opens by itself.
      AsyncData() => _Gone(
        scrollController: scrollController,
        onClose: onClose,
        arriving: ref.watch(syncStateProvider).value?.completedAt == null,
      ),
      AsyncError() => ListView(
        controller: scrollController,
        children: [
          MessageView(
            mood: SceneMood.error,
            title: t.place.loadError,
            action: t.common.retry,
            onAction: () => ref.invalidate(placeProvider(placeId)),
            compact: true,
          ),
        ],
      ),
      AsyncLoading() => _DetailsSkeleton(scrollController: scrollController),
    };
  }
}

class _Gone extends StatelessWidget {
  const new({this.scrollController, this.onClose, this.arriving = false});

  final ScrollController? scrollController;
  final VoidCallback? onClose;

  /// The first download has not finished: the place may still come.
  final bool arriving;

  @override
  Widget build(BuildContext context) => ListView(
    controller: scrollController,
    children: [
      if (onClose != null)
        Align(
          alignment: Alignment.centerRight,
          child: Padding(
            padding: const EdgeInsets.only(right: Space.s),
            child: _CloseButton(onClose: onClose!),
          ),
        ),
      if (arriving)
        MessageView(
          title: context.t.place.arriving,
          hint: context.t.place.arrivingHint,
          compact: true,
        )
      else
        MessageView(title: context.t.place.gone, hint: context.t.place.goneHint, compact: true),
    ],
  );
}

class PlaceDetailsBody extends ConsumerWidget {
  const new({
    required this.place,
    this.scrollController,
    this.onClose,
    this.bottomPadding = Space.huge,
    super.key,
  });

  final Place place;
  final ScrollController? scrollController;
  final VoidCallback? onClose;
  final double bottomPadding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.t;
    // The minute clock: "open now" and "confirmed today" turn over by
    // themselves.
    final now = ref.watch(minuteClockProvider).value ?? ref.read(clockProvider)();
    const gap = SizedBox(height: Space.l);
    return ListView(
      controller: scrollController,
      padding: EdgeInsets.fromLTRB(Space.xl, 0, Space.xl, bottomPadding),
      children: [
        _Header(place: place, onClose: onClose),
        const SizedBox(height: Space.l),
        _NightCard(place: place, now: now),
        PlaceCommunityNotes(place: place),
        PlacePhotos(place: place),
        gap,
        _Facts(place: place),
        if (place.openingHours != null) ...[gap, _OpeningHours(place: place, now: now)],
        _Section(
          title: t.place.services,
          child: place.services.isEmpty
              ? Text(t.place.noServices, style: _muted(context))
              : Wrap(
                  spacing: Space.s,
                  runSpacing: Space.s,
                  children: [
                    for (final s in Service.values.where(place.services.contains))
                      _IconChip(icon: AppIcons.service(s), label: t.service(s)),
                  ],
                ),
        ),
        PlaceSurroundings(place: place),
        gap,
        CoordinatesCard(position: place.position),
        if (place.descriptions.isNotEmpty || place.description != null)
          _Section(
            title: t.place.description,
            child: _Description(place: place),
          ),
        if (place.website != null || place.phone != null)
          _Section(
            title: t.place.contact,
            child: _Contact(place: place),
          ),
        if (place.activities.isNotEmpty)
          _Section(
            title: t.place.activities,
            child: Wrap(
              spacing: Space.s,
              runSpacing: Space.s,
              children: [
                for (final a in Activity.values.where(place.activities.contains))
                  _IconChip(icon: AppIcons.activity(a), label: t.activity(a)),
              ],
            ),
          ),
        PlaceReviewsSection(place: place),
        if (place.externalLinks.isNotEmpty)
          _Section(
            title: t.place.links,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final link in place.externalLinks)
                  if (webLink(link.url) case final url?)
                    _LinkRow(
                      icon: AppIcons.openExternal,
                      title: link.label,
                      subtitle: sourceName(t, link.sourceId, sources: place.sources),
                      onTap: () => ref.read(externalActionsProvider).openUrl(url),
                    ),
              ],
            ),
          ),
        _Section(
          title: t.place.sources,
          child: _Sources(place: place, now: now),
        ),
      ],
    );
  }
}

TextStyle? _muted(BuildContext context) =>
    Theme.of(context).textTheme.bodyMedium
        ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant);

class _Section extends StatelessWidget {
  const new({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: Space.xxxl),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(header: true, child: Text(title, style: Theme.of(context).textTheme.titleLarge)),
        const SizedBox(height: Space.m),
        child,
      ],
    ),
  );
}

class _CloseButton extends StatelessWidget {
  const new({required this.onClose});

  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return IconButton(
      tooltip: context.t.common.close,
      onPressed: onClose,
      style: IconButton.styleFrom(backgroundColor: scheme.surfaceContainerHigh),
      icon: const Icon(AppIcons.close, size: 20),
    );
  }
}

class _Header extends ConsumerWidget {
  const new({required this.place, this.onClose});

  final Place place;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.t;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final city = place.address?.city;
    final user = ref.watch(userLocationProvider);
    final rating = combinedRating(place.ratings);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: Space.xxs),
          child: PlaceHeroTarget(
            placeId: place.id,
            kind: place.kind,
            overnight: place.overnight,
            size: 52,
          ),
        ),
        const SizedBox(width: Space.ml),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Semantics(
                header: true,
                child: Text(
                  t.placeTitle(name: place.name, kind: place.kind, city: city),
                  style: theme.textTheme.headlineSmall,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(height: Space.xxs),
              Text(
                [t.kind(place.kind), ?city].join(' · '),
                style: theme.textTheme.bodyLarge?.copyWith(color: scheme.onSurfaceVariant),
              ),
              if (rating != null || user != null) ...[
                const SizedBox(height: Space.xs),
                Wrap(
                  spacing: Space.l,
                  runSpacing: Space.xxs,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    if (rating != null) RatingText(average: rating.average, count: rating.count),
                    if (user != null)
                      Text(
                        t.place.away(distance: t.distance(place.position.distanceTo(user))),
                        style: LunaType.number(15, weight: 420, color: scheme.onSurfaceVariant),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
        const SizedBox(width: Space.xs),
        PlaceMoreMenu(place: place),
        if (onClose != null) ...[const SizedBox(width: Space.xs), _CloseButton(onClose: onClose!)],
      ],
    );
  }
}

/// The night, first: the moon phase, what it means, and how fresh the
/// information is. Unknown reads as a blank to fill, never as a warning.
class _NightCard extends StatelessWidget {
  const new({required this.place, required this.now});

  final Place place;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final status = place.overnight;
    final tone = LunaTokens.of(context).nightTone(status);
    final stale = now.difference(place.freshness).inDays > 365;
    return Container(
      padding: const EdgeInsets.all(Space.l),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(LunaTokens.radiusXl),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              NightBadge(status, size: 44),
              const SizedBox(width: Space.ml),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      t.overnightShort(status),
                      style: theme.textTheme.titleLarge?.copyWith(color: tone.label),
                    ),
                    const SizedBox(height: Space.hair),
                    Text(t.overnightHint(status), style: theme.textTheme.bodyMedium),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: Space.m),
          Row(
            children: [
              Icon(
                stale ? AppIcons.stale : AppIcons.confirmed,
                size: 18,
                color: scheme.onSurfaceVariant,
              ),
              const SizedBox(width: Space.s),
              Expanded(
                child: Text(
                  stale
                      ? t.freshness.stale
                      : place.lastConfirmedAt != null
                      ? t.freshness.confirmed(when: t.ago(place.lastConfirmedAt!, now))
                      : t.freshness.updated(when: t.ago(place.updatedAt, now)),
                  style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ),
            ],
          ),
          // Where a traveller judges how fresh the page is, the way to
          // refresh it: two taps, no position sent.
          Padding(
            padding: const EdgeInsets.only(top: Space.xs),
            child: OutlinedButton.icon(
              onPressed: () => showConfirmSheet(context, placeId: place.id),
              icon: const Icon(AppIcons.confirmed),
              label: Text(t.contribute.stillThere),
            ),
          ),
        ],
      ),
    );
  }
}

class _Facts extends StatelessWidget {
  const new({required this.place});

  final Place place;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final price = place.priceParkingEur;
    final facts = [
      (
        AppIcons.pricePerNight,
        t.place.pricePerNight,
        price == null
            ? t.place.priceUnknown
            : price == 0
            ? t.place.priceFree
            : t.euros(price),
      ),
      if (place.priceServicesEur != null)
        (
          AppIcons.priceServices,
          t.place.priceServices,
          place.priceServicesEur == 0 ? t.place.priceFree : t.euros(place.priceServicesEur!),
        ),
      if (place.maxHeightM != null)
        (AppIcons.height, t.place.maxHeight, t.metres(place.maxHeightM!)),
      if (place.capacity != null) (AppIcons.capacity, t.place.capacity, t.number(place.capacity!)),
      if (place.stars != null)
        (AppIcons.classification, t.place.classification, t.place.classStars(n: place.stars!)),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        // As many columns as facts, up to what the width holds: one fact
        // spans the row rather than sitting alone in a corner.
        final fit = constraints.maxWidth > 520 ? 4 : (constraints.maxWidth > 300 ? 3 : 2);
        final columns = facts.length.clamp(1, fit);
        final width = (constraints.maxWidth - Space.s * (columns - 1)) / columns;
        return Wrap(
          spacing: Space.s,
          runSpacing: Space.s,
          children: [
            for (final (icon, label, value) in facts)
              SizedBox(
                width: width,
                child: _Fact(icon: icon, label: label, value: value),
              ),
          ],
        );
      },
    );
  }
}

class _Fact extends StatelessWidget {
  const new({required this.icon, required this.label, required this.value});

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.all(Space.m),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(LunaTokens.radiusL),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: scheme.onSurfaceVariant),
          const SizedBox(height: Space.xs),
          Text(value, style: LunaType.number(19, color: scheme.onSurface)),
          const SizedBox(height: Space.hair),
          Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(color: scheme.onSurfaceVariant),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

class _OpeningHours extends StatelessWidget {
  const new({required this.place, required this.now});

  final Place place;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final zone = PlaceZone.ofCountry(place.address?.countryCode);
    final state = openingStateAt(place.openingIntervals, now, validUntil: place.openingValidUntil);
    final open = state is OpenUntil || state is OpenThroughWindow;
    return Container(
      padding: const EdgeInsets.all(Space.l),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(LunaTokens.radiusXl),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(AppIcons.hours, color: scheme.onSurfaceVariant),
          const SizedBox(width: Space.ml),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  t.place.hours,
                  style: theme.textTheme.labelLarge?.copyWith(color: scheme.onSurfaceVariant),
                ),
                if (state != null) ...[
                  const SizedBox(height: Space.xxs),
                  Text(
                    t.opening(state, now, zone: zone),
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: open ? scheme.secondary : scheme.error,
                    ),
                  ),
                ] else if (place.openingIntervals != null) ...[
                  // The server's window has run out since the last sync:
                  // a time in no interval may not be closed any more.
                  const SizedBox(height: Space.xxs),
                  Text(
                    t.hours.stale,
                    style: theme.textTheme.titleSmall?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                ],
                const SizedBox(height: Space.xxs),
                Text(place.openingHours!, style: theme.textTheme.bodyMedium),
                const SizedBox(height: Space.xxs),
                Text(
                  t.hours.localTime,
                  style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _IconChip extends StatelessWidget {
  const new({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      constraints: const BoxConstraints(minHeight: 40),
      padding: const EdgeInsets.symmetric(horizontal: Space.m, vertical: Space.s),
      decoration: BoxDecoration(
        color: scheme.secondaryContainer,
        borderRadius: BorderRadius.circular(LunaTokens.radiusPill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 20, color: scheme.onSecondaryContainer),
          const SizedBox(width: Space.s),
          Flexible(
            child: Text(
              label,
              style: theme.textTheme.labelLarge?.copyWith(color: scheme.onSecondaryContainer),
            ),
          ),
        ],
      ),
    );
  }
}

/// The description in the user's language when a source wrote one; another
/// language otherwise, saying which, and from which source.
class _Description extends StatelessWidget {
  const new({required this.place});

  final Place place;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final theme = Theme.of(context);
    final chosen = descriptionFor(place.descriptions, t.$meta.locale.languageCode);
    if (chosen == null) return Text(place.description!, style: theme.textTheme.bodyLarge);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(chosen.text.text, style: theme.textTheme.bodyLarge),
        const SizedBox(height: Space.s),
        Wrap(
          spacing: Space.s,
          runSpacing: Space.xxs,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SourceBadge(label: sourceName(t, chosen.text.sourceId, sources: place.sources)),
            if (!chosen.inUserLanguage)
              Text(
                t.place.originalLanguage(language: t.languageName(chosen.text.lang)),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _LinkRow extends StatelessWidget {
  const new({required this.icon, required this.title, required this.onTap, this.subtitle});

  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.s),
      child: Material(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(LunaTokens.radiusL),
        child: InkWell(
          borderRadius: BorderRadius.circular(LunaTokens.radiusL),
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 56),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: Space.l, vertical: Space.s),
              child: Row(
                children: [
                  Icon(icon, color: scheme.onSurfaceVariant),
                  const SizedBox(width: Space.m),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: theme.textTheme.titleSmall,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (subtitle != null)
                          Text(
                            subtitle!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                      ],
                    ),
                  ),
                  Icon(AppIcons.openExternal, size: 20, color: scheme.onSurfaceVariant),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Contact extends ConsumerWidget {
  const new({required this.place});

  final Place place;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.t;
    final website = webLink(place.website);
    final phones = phoneNumbers(place.phone);
    final actions = ref.read(externalActionsProvider);
    Future<void> run(Future<bool> Function() open) async {
      final messenger = ScaffoldMessenger.maybeOf(context);
      final failed = t.place.openFailed;
      if (!await open()) showMessage(messenger, failed);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (website != null)
          _LinkRow(
            icon: AppIcons.website,
            title: t.place.website,
            subtitle: website.host,
            onTap: () => run(() => actions.openUrl(website)),
          ),
        for (final phone in phones)
          _LinkRow(
            icon: AppIcons.call,
            title: t.place.call,
            subtitle: phone,
            onTap: () => run(() => actions.dial(phone)),
          ),
      ],
    );
  }
}

class _Sources extends ConsumerWidget {
  const new({required this.place, required this.now});

  final Place place;
  final DateTime now;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.t;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Column(
      children: [
        for (final s in place.sources)
          Padding(
            padding: const EdgeInsets.only(bottom: Space.s),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(Space.l),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(LunaTokens.radiusL),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: Space.s,
                    runSpacing: Space.xs,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      SourceBadge(label: s.source.name),
                      Text(s.source.licence, style: theme.textTheme.labelMedium),
                    ],
                  ),
                  const SizedBox(height: Space.s),
                  Text(s.source.attribution, style: theme.textTheme.bodyMedium),
                  const SizedBox(height: Space.xs),
                  Text(
                    [
                      t.place.fetched(when: t.ago(s.fetchedAt, now)),
                      if (s.matchScore != null)
                        t.place.matchScore(score: (s.matchScore! * 100).round()),
                    ].join(' · '),
                    style: _muted(context),
                  ),
                  if (webLink(s.externalUrl) case final url?) ...[
                    const SizedBox(height: Space.xxs),
                    TextButton.icon(
                      style: TextButton.styleFrom(padding: EdgeInsets.zero),
                      onPressed: () => ref.read(externalActionsProvider).openUrl(url),
                      icon: const Icon(AppIcons.openExternal, size: 18),
                      label: Text(t.place.viewSource),
                    ),
                  ],
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _DetailsSkeleton extends StatelessWidget {
  const new({this.scrollController});

  final ScrollController? scrollController;

  @override
  Widget build(BuildContext context) => ListView(
    controller: scrollController,
    padding: const EdgeInsets.fromLTRB(Space.xl, 0, Space.xl, Space.huge),
    children: const [
      Row(
        children: [
          Skeleton(width: 52, height: 52, radius: 16),
          SizedBox(width: Space.ml),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Skeleton(width: 220, height: 24),
                SizedBox(height: Space.s),
                Skeleton(width: 140),
              ],
            ),
          ),
        ],
      ),
      SizedBox(height: Space.l),
      Skeleton(height: 112, radius: LunaTokens.radiusXl),
      SizedBox(height: Space.l),
      Skeleton(height: 88, radius: LunaTokens.radiusL),
    ],
  );
}
