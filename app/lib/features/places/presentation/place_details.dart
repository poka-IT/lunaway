import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lunaway/core/external_actions.dart';
import 'package:lunaway/core/geo/coordinate_format.dart';
import 'package:lunaway/core/providers.dart';
import 'package:lunaway/features/favorites/application/favorites_providers.dart';
import 'package:lunaway/features/favorites/presentation/save_to_lists.dart';
import 'package:lunaway/features/places/application/places_providers.dart';
import 'package:lunaway/features/places/domain/opening.dart';
import 'package:lunaway/features/places/domain/place.dart';
import 'package:lunaway/features/places/domain/place_content.dart';
import 'package:lunaway/features/places/domain/taxonomy.dart';
import 'package:lunaway/features/places/presentation/coordinates_card.dart';
import 'package:lunaway/features/places/presentation/directions.dart';
import 'package:lunaway/features/places/presentation/place_extras_view.dart';
import 'package:lunaway/i18n/strings.g.dart';
import 'package:lunaway/shared/icons/luna_icons.dart';
import 'package:lunaway/shared/labels.dart';
import 'package:lunaway/shared/source_names.dart';
import 'package:lunaway/shared/theme/app_icons.dart';
import 'package:lunaway/shared/theme/luna_colors.dart';
import 'package:lunaway/shared/theme/tokens.dart';
import 'package:lunaway/shared/widgets/place_avatar.dart';
import 'package:lunaway/shared/widgets/source_badge.dart';
import 'package:lunaway/shared/widgets/status_views.dart';

/// Everything about one place, for the bottom sheet (compact) and the side
/// panel (wider). The overnight status comes first: it is what a traveller
/// looks for.
class PlaceDetails extends ConsumerWidget {
  const new({required this.placeId, this.scrollController, this.onClose, super.key});

  final String placeId;
  final ScrollController? scrollController;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.t;
    return switch (ref.watch(placeProvider(placeId))) {
      AsyncData(value: final place?) => PlaceDetailsBody(
        place: place,
        scrollController: scrollController,
        onClose: onClose,
      ),
      AsyncData() => MessageView(icon: AppIcons.gone, title: t.place.gone),
      AsyncError() => MessageView(
        icon: AppIcons.error,
        title: t.place.loadError,
        action: t.common.retry,
        onAction: () => ref.invalidate(placeProvider(placeId)),
        error: true,
      ),
      AsyncLoading() => _DetailsSkeleton(scrollController: scrollController),
    };
  }
}

class PlaceDetailsBody extends ConsumerWidget {
  const new({required this.place, this.scrollController, this.onClose, super.key});

  final Place place;
  final ScrollController? scrollController;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.t;
    final now = ref.watch(clockProvider)();
    const gap = SizedBox(height: Space.l);
    return ListView(
      controller: scrollController,
      padding: const EdgeInsets.fromLTRB(Space.xl, Space.xxs, Space.xl, Space.huge),
      children: [
        _Header(place: place, onClose: onClose),
        gap,
        _OvernightCard(place: place, now: now),
        gap,
        _Actions(place: place),
        PlacePhotos(place: place),
        const SizedBox(height: Space.xxl),
        _Facts(place: place),
        if (place.openingHours != null) ...[gap, _OpeningHours(place: place, now: now)],
        _Section(
          title: t.place.services,
          child: place.services.isEmpty
              ? Text(t.place.noServices, style: _muted(context))
              : Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final s in Service.values.where(place.services.contains))
                      _ServiceChip(service: s),
                  ],
                ),
        ),
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
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final a in Activity.values.where(place.activities.contains))
                  Chip(label: Text(t.activity(a))),
              ],
            ),
          ),
        PlaceReviewsSection(place: place),
        if (place.externalLinks.isNotEmpty)
          _Section(
            title: t.place.links,
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final link in place.externalLinks)
                  OutlinedButton.icon(
                    onPressed: () => ref.read(externalActionsProvider).openUrl(Uri.parse(link.url)),
                    icon: const Icon(AppIcons.openExternal),
                    label: Text(link.label),
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
          spacing: 8,
          runSpacing: 4,
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
        Semantics(header: true, child: Text(title, style: Theme.of(context).textTheme.titleMedium)),
        const SizedBox(height: Space.m),
        child,
      ],
    ),
  );
}

class _Header extends StatelessWidget {
  const new({required this.place, this.onClose});

  final Place place;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final theme = Theme.of(context);
    final city = place.address?.city;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: Space.xxs),
          child: PlaceAvatar(kind: place.kind, size: 48),
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
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              if (combinedRating(place.ratings) case final rating?) ...[
                const SizedBox(height: Space.xs),
                RatingText(average: rating.average, count: rating.count),
              ],
            ],
          ),
        ),
        if (onClose != null)
          IconButton(tooltip: t.common.close, icon: const Icon(AppIcons.close), onPressed: onClose),
      ],
    );
  }
}

class _OvernightCard extends StatelessWidget {
  const new({required this.place, required this.now});

  final Place place;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final theme = Theme.of(context);
    final colors = LunaColors.of(context);
    final status = place.overnight;
    final tone = colors.overnight(status);
    final pin = LunaColors.pinOvernight(status) ?? colors.unknown;
    final stale = now.difference(place.freshness).inDays > 365;
    final dark = theme.brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(Space.l),
      decoration: BoxDecoration(
        color: Color.alphaBlend(
          pin.withValues(alpha: dark ? 0.2 : 0.1),
          theme.colorScheme.surfaceContainerLow,
        ),
        borderRadius: BorderRadius.circular(LunaTokens.of(context).radiusXl),
        border: Border.all(color: pin.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(color: pin, shape: BoxShape.circle),
                alignment: Alignment.center,
                child: LunaIcon(
                  LunaIcons.overnight(status),
                  size: 28,
                  color: LunaTokens.of(context).onAccent,
                ),
              ),
              const SizedBox(width: Space.ml),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      t.overnightLabel(status),
                      style: theme.textTheme.titleLarge?.copyWith(
                        color: tone,
                        fontWeight: FontWeight.w800,
                      ),
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
                size: 20,
                color: stale ? theme.colorScheme.error : theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: Space.s),
              Expanded(
                child: Text(
                  stale
                      ? t.freshness.stale
                      : place.lastConfirmedAt != null
                      ? t.freshness.confirmed(when: t.ago(place.lastConfirmedAt!, now))
                      : t.freshness.updated(when: t.ago(place.updatedAt, now)),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: stale ? theme.colorScheme.error : theme.colorScheme.onSurfaceVariant,
                    fontWeight: stale ? FontWeight.w700 : null,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Actions extends ConsumerWidget {
  const new({required this.place});

  final Place place;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.t;
    final lists = ref.watch(placeListsProvider(place.id)).value ?? const <int>{};
    final saved = lists.isNotEmpty;
    final title = t.placeTitle(name: place.name, kind: place.kind, city: place.address?.city);
    return Row(
      children: [
        Expanded(
          child: _TileButton(
            filled: true,
            icon: AppIcons.directions,
            label: t.place.directions,
            onPressed: () => openDirections(context, ref, place.position, label: title),
          ),
        ),
        const SizedBox(width: Space.sm),
        Expanded(
          child: _TileButton(
            icon: saved ? AppIcons.favoriteSelected : AppIcons.favorite,
            iconColor: saved ? Theme.of(context).colorScheme.tertiary : null,
            label: saved ? t.place.saved : t.place.save,
            tooltip: t.place.saveTo,
            onPressed: () async {
              final messenger = ScaffoldMessenger.maybeOf(context);
              final repo = ref.read(favoritesRepositoryProvider);
              final message = saved ? t.place.removedToast : t.place.savedToast;
              if (saved) {
                await repo.removeEverywhere(place.id);
              } else {
                await repo.addToDefault(place.summary);
              }
              messenger
                ?..hideCurrentSnackBar()
                ..showSnackBar(SnackBar(content: Text(message)));
            },
            onLongPress: () => showSaveToLists(context, place.summary),
          ),
        ),
        const SizedBox(width: Space.sm),
        Expanded(
          child: Builder(
            builder: (buttonContext) => _TileButton(
              icon: AppIcons.share,
              label: t.place.share,
              onPressed: () async {
                final box = buttonContext.findRenderObject() as RenderBox?;
                final origin = box == null ? null : box.localToGlobal(Offset.zero) & box.size;
                await ref
                    .read(externalActionsProvider)
                    .share(
                      [
                        title,
                        CoordinateFormat.decimal.format(place.position),
                        CoordinateFormat.openStreetMap.format(place.position),
                      ].join('\n'),
                      subject: title,
                      origin: origin,
                    );
              },
            ),
          ),
        ),
      ],
    );
  }
}

/// A big button with its icon above the label: three fit side by side on a
/// phone and every one reads without a tooltip.
class _TileButton extends StatelessWidget {
  const new({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.onLongPress,
    this.filled = false,
    this.iconColor,
    this.tooltip,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;
  final VoidCallback? onLongPress;
  final bool filled;
  final Color? iconColor;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final child = Padding(
      padding: const EdgeInsets.symmetric(vertical: Space.sm),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: iconColor),
          const SizedBox(height: Space.xxs),
          Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center),
        ],
      ),
    );
    final style = ButtonStyle(
      padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: Space.xs)),
      minimumSize: const WidgetStatePropertyAll(Size(64, 68)),
      shape: WidgetStatePropertyAll(
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(LunaTokens.of(context).radiusL)),
      ),
    );
    final button = filled
        ? FilledButton(onPressed: onPressed, onLongPress: onLongPress, style: style, child: child)
        : OutlinedButton(
            onPressed: onPressed,
            onLongPress: onLongPress,
            style: style,
            child: child,
          );
    return tooltip == null ? button : Tooltip(message: tooltip, child: button);
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
        (AppIcons.priceServices, t.place.priceServices, t.euros(place.priceServicesEur!)),
      if (place.maxHeightM != null)
        (AppIcons.height, t.place.maxHeight, t.metres(place.maxHeightM!)),
      if (place.capacity != null) (AppIcons.capacity, t.place.capacity, '${place.capacity}'),
      if (place.stars != null)
        (AppIcons.classification, t.place.classification, t.place.classStars(n: place.stars!)),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          header: true,
          child: Text(t.place.facts, style: Theme.of(context).textTheme.titleMedium),
        ),
        const SizedBox(height: Space.m),
        LayoutBuilder(
          builder: (context, constraints) {
            final columns = constraints.maxWidth > 520 ? 4 : 2;
            final width = (constraints.maxWidth - 10 * (columns - 1)) / columns;
            return Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final (icon, label, value) in facts)
                  SizedBox(
                    width: width,
                    child: _Fact(icon: icon, label: label, value: value),
                  ),
              ],
            );
          },
        ),
      ],
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
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(Space.ml),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 18, color: theme.colorScheme.onSurfaceVariant),
                const SizedBox(width: Space.xs),
                Expanded(
                  child: Text(
                    label,
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: Space.xs),
            Text(value, style: theme.textTheme.titleLarge),
          ],
        ),
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
    final colors = LunaColors.of(context);
    final state = openingStateAt(place.openingIntervals, now, validUntil: place.openingValidUntil);
    final open = state is OpenUntil || state is OpenThroughWindow;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(Space.l),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(AppIcons.hours, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(width: Space.ml),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    t.place.hours,
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  if (state != null) ...[
                    const SizedBox(height: Space.xxs),
                    Text(
                      t.opening(state, now),
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: open ? colors.allowed : colors.forbidden,
                      ),
                    ),
                  ] else if (place.openingIntervals != null) ...[
                    // The server's window has run out since the last sync:
                    // a time in no interval may not be closed any more.
                    const SizedBox(height: Space.xxs),
                    Text(
                      t.hours.stale,
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                  const SizedBox(height: Space.xxs),
                  Text(place.openingHours!, style: theme.textTheme.bodyMedium),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ServiceChip extends StatelessWidget {
  const new({required this.service});

  final Service service;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      constraints: const BoxConstraints(minHeight: 44),
      padding: const EdgeInsets.symmetric(horizontal: Space.m, vertical: Space.s),
      decoration: BoxDecoration(
        color: theme.colorScheme.secondaryContainer.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(LunaTokens.of(context).radiusM),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          LunaIcon(
            LunaIcons.service(service),
            size: 22,
            color: theme.colorScheme.onSecondaryContainer,
          ),
          const SizedBox(width: Space.s),
          Flexible(
            child: Text(
              context.t.service(service),
              style: theme.textTheme.labelLarge?.copyWith(
                color: theme.colorScheme.onSecondaryContainer,
              ),
            ),
          ),
        ],
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
    final website = place.website;
    final phone = place.phone;
    Future<void> open(Uri uri) async {
      final messenger = ScaffoldMessenger.maybeOf(context);
      final failed = t.place.openFailed;
      if (!await ref.read(externalActionsProvider).openUrl(uri)) {
        messenger?.showSnackBar(SnackBar(content: Text(failed)));
      }
    }

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          if (website != null)
            ListTile(
              leading: const Icon(AppIcons.website),
              title: Text(t.place.website),
              subtitle: Text(website, maxLines: 1, overflow: TextOverflow.ellipsis),
              trailing: const Icon(AppIcons.openExternal),
              onTap: () =>
                  open(Uri.parse(website.startsWith('http') ? website : 'https://$website')),
            ),
          if (phone != null)
            ListTile(
              leading: const Icon(AppIcons.call),
              title: Text(t.place.call),
              subtitle: Text(phone),
              onTap: () => open(Uri(scheme: 'tel', path: phone.replaceAll(' ', ''))),
            ),
        ],
      ),
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
    return Column(
      children: [
        for (final s in place.sources)
          Padding(
            padding: const EdgeInsets.only(bottom: Space.sm),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(Space.l),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
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
                    if (s.externalUrl != null) ...[
                      const SizedBox(height: Space.xxs),
                      TextButton.icon(
                        style: TextButton.styleFrom(padding: EdgeInsets.zero),
                        onPressed: () =>
                            ref.read(externalActionsProvider).openUrl(Uri.parse(s.externalUrl!)),
                        icon: const Icon(AppIcons.openExternal, size: 18),
                        label: Text(t.place.viewSource),
                      ),
                    ],
                  ],
                ),
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
    padding: const EdgeInsets.fromLTRB(Space.xl, Space.xxs, Space.xl, Space.huge),
    children: const [
      Row(
        children: [
          Skeleton(width: 48, height: 48, radius: 24),
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
      Skeleton(height: 120, radius: 20),
      SizedBox(height: Space.l),
      Skeleton(height: 68, radius: 18),
      SizedBox(height: Space.xxl),
      Skeleton(height: 90, radius: 20),
    ],
  );
}
