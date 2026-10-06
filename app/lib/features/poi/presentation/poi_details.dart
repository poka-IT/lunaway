import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lunaway/core/external_actions.dart';
import 'package:lunaway/core/providers.dart';
import 'package:lunaway/core/time/place_zone.dart';
import 'package:lunaway/features/community/domain/contribution.dart';
import 'package:lunaway/features/community/presentation/contribute.dart';
import 'package:lunaway/features/map/application/map_state.dart';
import 'package:lunaway/features/map/presentation/point_details.dart';
import 'package:lunaway/features/places/application/places_providers.dart';
import 'package:lunaway/features/places/domain/place.dart';
import 'package:lunaway/features/places/presentation/coordinates_card.dart';
import 'package:lunaway/features/poi/application/poi_providers.dart';
import 'package:lunaway/features/poi/data/poi_operations.dart';
import 'package:lunaway/features/poi/data/poi_repository.dart';
import 'package:lunaway/features/poi/domain/poi.dart';
import 'package:lunaway/features/poi/presentation/poi_labels.dart';
import 'package:lunaway/features/vehicle/application/vehicle_providers.dart';
import 'package:lunaway/features/vehicle/domain/vehicle.dart';
import 'package:lunaway/i18n/strings.g.dart';
import 'package:lunaway/shared/hours_text.dart';
import 'package:lunaway/shared/labels.dart';
import 'package:lunaway/shared/messages.dart';
import 'package:lunaway/shared/source_names.dart';
import 'package:lunaway/shared/theme/app_icons.dart';
import 'package:lunaway/shared/theme/tokens.dart';
import 'package:lunaway/shared/widgets/source_badge.dart';
import 'package:lunaway/shared/widgets/status_views.dart';

/// The page of a point of interest, for the sheet (compact) and the panel
/// (wider): what it is, whether it is open and until when, how far, the
/// prices of a fuel station with their freshness, "still there?", the hours,
/// the contact and the sources. It opens at once from what the map tile
/// said; the rest comes from the API, or from the copy kept since the last
/// read.
class PoiDetails extends ConsumerWidget {
  const new({
    required this.feature,
    this.from,
    this.scrollController,
    this.onClose,
    this.actions = false,
    this.bottomPadding = Space.huge,
    super.key,
  });

  final PoiFeature feature;

  /// The place whose surroundings it was opened from: a link goes back.
  final String? from;
  final ScrollController? scrollController;
  final VoidCallback? onClose;

  /// The action bar at the foot of the content (a panel).
  final bool actions;
  final double bottomPadding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.t;
    final read = ref.watch(poiPageProvider(feature.id));
    final body = switch (read) {
      // A copy kept, shown with when it was read when the network did not
      // answer, or when the server refused to read it again.
      AsyncValue(
        value: Read(value: final page?, :final fetchedAt, :final offline),
        :final hasError,
      ) =>
        _Body(
          feature: feature,
          from: from,
          page: page,
          readAt: offline || hasError ? fetchedAt : null,
          readAgainFailed: hasError && !offline,
          scrollController: scrollController,
          onClose: onClose,
          bottomPadding: bottomPadding,
        ),
      // The server no longer has it: hidden after "gone" answers, or
      // removed by the last import.
      AsyncData() => ListView(
        controller: scrollController,
        padding: EdgeInsets.fromLTRB(Space.xl, 0, Space.xl, bottomPadding),
        children: [
          if (from != null) _BackToPlace(placeId: from!),
          _Header(feature: feature, onClose: onClose),
          const SizedBox(height: Space.l),
          MessageView(title: t.poi.goneTitle, hint: t.poi.goneHint, compact: true),
        ],
      ),
      AsyncError() => _Body(
        feature: feature,
        from: from,
        unreadable: true,
        onRetry: () => ref.invalidate(poiPageProvider(feature.id)),
        scrollController: scrollController,
        onClose: onClose,
        bottomPadding: bottomPadding,
      ),
      AsyncLoading() => _Body(
        feature: feature,
        from: from,
        loading: true,
        scrollController: scrollController,
        onClose: onClose,
        bottomPadding: bottomPadding,
      ),
    };
    if (!actions) return body;
    return Column(
      children: [
        Expanded(child: body),
        PointActionBar(position: feature.position),
      ],
    );
  }
}

class _Body extends ConsumerWidget {
  const new({
    required this.feature,
    required this.bottomPadding,
    this.from,
    this.page,
    this.readAt,
    this.readAgainFailed = false,
    this.loading = false,
    this.unreadable = false,
    this.onRetry,
    this.scrollController,
    this.onClose,
  });

  final PoiFeature feature;
  final String? from;
  final PoiPage? page;

  /// When the copy shown was read, when the network did not answer now.
  final DateTime? readAt;

  /// The server answered, without the page: the copy shown is older.
  final bool readAgainFailed;
  final bool loading;
  final bool unreadable;
  final VoidCallback? onRetry;
  final ScrollController? scrollController;
  final VoidCallback? onClose;
  final double bottomPadding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.t;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final now = ref.watch(minuteClockProvider).value ?? ref.read(clockProvider)();
    final poi = page?.poi;
    final hours = poi?.hours ?? feature.hours;
    final vehicle = ref.watch(vehicleFuelProvider);
    final mine = [
      ?vehicle.fuel?.wire,
      if (vehicle.lpgHeating && vehicle.fuel != FuelType.lpg) 'LPG',
    ];
    const gap = SizedBox(height: Space.l);
    return ListView(
      controller: scrollController,
      padding: EdgeInsets.fromLTRB(Space.xl, 0, Space.xl, bottomPadding),
      children: [
        if (from != null) _BackToPlace(placeId: from!),
        _Header(feature: feature, poi: poi, onClose: onClose),
        const SizedBox(height: Space.l),
        _StateCard(feature: feature, poi: poi, hours: hours, now: now),
        if (readAt != null) ...[
          const SizedBox(height: Space.s),
          Text(
            readAgainFailed
                ? t.poi.readStale(when: t.agoFine(readAt!, now))
                : t.poi.readOffline(when: t.agoFine(readAt!, now)),
            style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ],
        gap,
        _StillThere(feature: feature, poi: poi, now: now),
        if (poi?.fuel case final fuel?) ...[
          gap,
          _FuelCard(fuel: fuel, now: now, mine: mine),
        ] else if (poi?.lpg ?? feature.lpg) ...[
          gap,
          _Line(icon: PoiLookIcons.lpg, text: t.poi.lpgYes),
        ],
        if (loading) ...[
          gap,
          const Skeleton(height: 72, radius: LunaTokens.radiusL),
        ] else if (unreadable) ...[
          gap,
          MessageView(
            title: t.poi.loadError,
            action: t.common.retry,
            onAction: onRetry,
            compact: true,
          ),
        ],
        if (poi != null) ..._details(context, ref, poi, page!.sources, now),
        gap,
        CoordinatesCard(position: feature.position),
      ],
    );
  }

  List<Widget> _details(
    BuildContext context,
    WidgetRef ref,
    Poi poi,
    List<Source> sources,
    DateTime now,
  ) {
    final t = context.t;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final website = webLink(poi.website);
    final phones = phoneNumbers(poi.phone);
    final actions = ref.read(externalActionsProvider);
    Future<void> run(Future<bool> Function() open) async {
      final messenger = ScaffoldMessenger.maybeOf(context);
      final failed = t.place.openFailed;
      if (!await open()) showMessage(messenger, failed);
    }

    return [
      if (poi.openingHours != null)
        _Section(
          title: t.place.hours,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(readableHours(poi.openingHours!, t), style: theme.textTheme.bodyLarge),
              const SizedBox(height: Space.xxs),
              Text(
                t.hours.localTime,
                style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      if (poi.products.isNotEmpty)
        _Section(
          title: t.poi.products,
          child: _Chips([for (final p in poi.products) t.product(p)]),
        ),
      if (poi.payment.isNotEmpty)
        _Section(
          title: t.poi.paymentTitle,
          child: _Chips([for (final p in poi.payment) t.payment(p)]),
        ),
      if (poi.fee != null || poi.seasonal == true)
        Padding(
          padding: const EdgeInsets.only(top: Space.l),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (poi.fee != null)
                _Line(icon: AppIcons.priceServices, text: poi.fee! ? t.poi.fee : t.poi.free),
              if (poi.seasonal == true) _Line(icon: PoiLookIcons.seasonal, text: t.poi.seasonal),
            ],
          ),
        ),
      if (website != null || phones.isNotEmpty)
        _Section(
          title: t.place.contact,
          child: Column(
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
                  subtitle: readablePhone(phone),
                  onTap: () => run(() => actions.dial(phone)),
                ),
            ],
          ),
        ),
      if (poi.sources.isNotEmpty)
        _Section(
          title: t.place.sources,
          child: Column(
            children: [
              for (final s in poi.sources)
                _SourceCard(ref: s, source: sources.where((x) => x.id == s.sourceId).firstOrNull),
            ],
          ),
        ),
    ];
  }
}

/// Back to the place whose surroundings opened this point.
class _BackToPlace extends ConsumerWidget {
  const new({required this.placeId});

  final String placeId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.t;
    final place = ref.watch(placeProvider(placeId)).value;
    return Align(
      alignment: Alignment.centerLeft,
      child: TextButton.icon(
        onPressed: () => ref.read(selectionProvider.notifier).select(PlaceSelection(placeId)),
        icon: const Icon(AppIcons.back, size: 18),
        label: Text(
          place == null
              ? t.poi.backToPlace
              : t.poi.backTo(
                  name: t.placeTitle(name: place.name, kind: place.kind, city: place.address?.city),
                ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }
}

/// Icons of the page that are not in [AppIcons].
abstract final class PoiLookIcons {
  static const IconData lpg = AppIcons.priceServices;
  static const IconData seasonal = AppIcons.hours;
}

class _Header extends ConsumerWidget {
  const new({required this.feature, this.poi, this.onClose});

  final PoiFeature feature;
  final Poi? poi;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.t;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final city = poi?.address?.city;
    final user = ref.watch(userLocationProvider);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: Space.xxs),
          child: PoiAvatar(kind: feature.kind, size: 52),
        ),
        const SizedBox(width: Space.ml),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Semantics(
                header: true,
                child: Text(
                  t.poiTitle(poi?.name ?? feature.name, feature.kind),
                  style: theme.textTheme.headlineSmall,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(height: Space.xxs),
              Text(
                [
                  t.poiKind(feature.kind),
                  if (poi?.brand case final brand? when brand != poi?.name) brand,
                  ?city,
                ].join(' · '),
                style: theme.textTheme.bodyLarge?.copyWith(color: scheme.onSurfaceVariant),
              ),
              if (user != null) ...[
                const SizedBox(height: Space.xs),
                Text(
                  t.place.away(distance: t.distance(feature.position.distanceTo(user))),
                  style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ],
            ],
          ),
        ),
        if (onClose != null) ...[
          const SizedBox(width: Space.xs),
          IconButton(
            tooltip: t.common.close,
            onPressed: onClose,
            style: IconButton.styleFrom(backgroundColor: scheme.surfaceContainerHigh),
            icon: const Icon(AppIcons.close, size: 20),
          ),
        ],
      ],
    );
  }
}

/// Open or closed, until when, in the place's time; and what may keep it
/// shut (closed for good per FINESS, seasonal).
class _StateCard extends StatelessWidget {
  const new({required this.feature, required this.hours, required this.now, this.poi});

  final PoiFeature feature;
  final Poi? poi;
  final PoiHours hours;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final zone = PlaceZone.ofCountry(poi?.address?.countryCode);
    final closedOn = poi?.reportedClosed;
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
              Icon(AppIcons.hours, color: poiOpeningColor(scheme, hours, now)),
              const SizedBox(width: Space.m),
              Expanded(
                child: Text(
                  t.poiOpening(hours, now, zone: zone),
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: poiOpeningColor(scheme, hours, now),
                  ),
                ),
              ),
            ],
          ),
          if (closedOn != null || feature.maybeClosed) ...[
            const SizedBox(height: Space.s),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(AppIcons.error, size: 20, color: scheme.error),
                const SizedBox(width: Space.m),
                Expanded(
                  child: Text(
                    closedOn == null
                        ? t.poi.maybeClosed
                        : t.poi.maybeClosedSince(
                            date: MaterialLocalizations.of(context).formatMediumDate(closedOn),
                          ),
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// "Still there?" in two gestures: the page, then one of two answers. No
/// position is sent.
class _StillThere extends ConsumerWidget {
  const new({required this.feature, required this.now, this.poi});

  final PoiFeature feature;
  final Poi? poi;
  final DateTime now;

  Future<void> _answer(BuildContext context, {required bool there}) async {
    final t = context.t;
    await submitContribution(
      context,
      ContributionKind.confirmPoi,
      payload: {'poiId': feature.id, 'stillThere': there},
      sentText: there ? t.poi.thanksThere : t.poi.thanksGone,
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.t;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final confirmed = poi?.lastConfirmedAt;
    final checked = poi?.checkedOn;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(t.poi.stillThereTitle, style: theme.textTheme.titleMedium),
        const SizedBox(height: Space.xxs),
        Text(
          confirmed != null
              ? t.poi.lastConfirmed(when: t.ago(confirmed, now))
              : checked != null
              ? t.poi.checkedOn(date: MaterialLocalizations.of(context).formatMediumDate(checked))
              : t.poi.stillThereHint,
          style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
        ),
        const SizedBox(height: Space.s),
        Wrap(
          spacing: Space.s,
          runSpacing: Space.s,
          children: [
            OutlinedButton.icon(
              onPressed: () => _answer(context, there: true),
              icon: const Icon(AppIcons.confirmed),
              label: Text(t.poi.stillThere),
            ),
            TextButton.icon(
              onPressed: () => _answer(context, there: false),
              icon: const Icon(AppIcons.gone),
              label: Text(t.poi.gone),
            ),
          ],
        ),
      ],
    );
  }
}

/// The prices of a station, LPG first, each with its date, and the feed's
/// own reading time.
class _FuelCard extends StatelessWidget {
  const new({required this.fuel, required this.now, required this.mine});

  final FuelInfo fuel;
  final DateTime now;

  /// The fuels of the user's vehicle (`FuelKind`), shown first and larger;
  /// LPG stands out when it is empty.
  final List<String> mine;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final muted = theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant);
    final prices = mine.isEmpty ? fuel.sortedPrices : fuel.pricesFirst(mine);
    bool stands(String f) => mine.isEmpty ? f == 'LPG' : mine.contains(f);
    final soldOut = [
      for (final s in fuel.shortages)
        if (!prices.any((p) => p.fuel == s.fuel)) s,
    ];
    return Container(
      padding: const EdgeInsets.all(Space.l),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(LunaTokens.radiusXl),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // The card's title is the feed's own name; its licence and link
          // are in the sources at the foot of the page.
          Semantics(
            header: true,
            child: Text(t.poi.fuelPrices, style: theme.textTheme.titleMedium),
          ),
          const SizedBox(height: Space.s),
          for (final p in prices)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: Space.xxs),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          t.fuelName(p.fuel),
                          style: stands(p.fuel)
                              ? theme.textTheme.titleSmall
                              : theme.textTheme.bodyLarge,
                        ),
                        if (fuel.shortageOf(p.fuel) case final shortage?)
                          Text(
                            shortage.definitive
                                ? t.poi.shortageDefinitive
                                : t.poi.shortageTemporary,
                            style: theme.textTheme.bodySmall?.copyWith(color: scheme.error),
                          )
                        else
                          Text(t.poi.priceUpdated(when: t.agoFine(p.updatedAt, now)), style: muted),
                      ],
                    ),
                  ),
                  Text(t.pricePerLitre(p.priceEur), style: theme.textTheme.titleLarge),
                ],
              ),
            ),
          for (final s in soldOut)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: Space.xxs),
              child: Text(
                '${t.fuelName(s.fuel)} · ${s.definitive ? t.poi.shortageDefinitive : t.poi.shortageTemporary}',
                style: theme.textTheme.bodyMedium?.copyWith(color: scheme.error),
              ),
            ),
          if (fuel.selfService24h || fuel.highway) ...[
            const SizedBox(height: Space.s),
            _Chips([
              if (fuel.selfService24h) t.poi.selfService24h,
              if (fuel.highway) t.poi.highway,
            ]),
          ],
          const SizedBox(height: Space.s),
          Text(t.poi.feedRead(when: t.agoFine(fuel.fetchedAt, now)), style: muted),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const new({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: Space.xxl),
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

class _Line extends StatelessWidget {
  const new({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Space.xxs),
      child: Row(
        children: [
          Icon(icon, size: 20, color: scheme.onSurfaceVariant),
          const SizedBox(width: Space.m),
          Expanded(child: Text(text, style: Theme.of(context).textTheme.bodyLarge)),
        ],
      ),
    );
  }
}

class _Chips extends StatelessWidget {
  const new(this.labels);

  final List<String> labels;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Wrap(
      spacing: Space.s,
      runSpacing: Space.s,
      children: [
        for (final label in labels)
          Container(
            constraints: const BoxConstraints(minHeight: 36),
            padding: const EdgeInsets.symmetric(horizontal: Space.m, vertical: Space.xs),
            decoration: BoxDecoration(
              color: scheme.secondaryContainer,
              borderRadius: BorderRadius.circular(LunaTokens.radiusPill),
            ),
            child: Text(
              label,
              style: theme.textTheme.labelLarge?.copyWith(color: scheme.onSecondaryContainer),
            ),
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
                        Text(title, style: theme.textTheme.titleSmall),
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

/// One source of a point: its name and licence, its attribution, when
/// Lunaway read it, and its page.
class _SourceCard extends ConsumerWidget {
  const new({required this.ref, this.source});

  final PoiSourceRef ref;
  final Source? source;

  @override
  Widget build(BuildContext context, WidgetRef widgetRef) {
    final t = context.t;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final now = widgetRef.watch(minuteClockProvider).value ?? widgetRef.read(clockProvider)();
    final source = this.source;
    return Padding(
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
                SourceBadge(label: source?.name ?? sourceName(t, ref.sourceId)),
                if (source != null) Text(source.licence, style: theme.textTheme.labelMedium),
              ],
            ),
            if (source != null) ...[
              const SizedBox(height: Space.s),
              Text(source.attribution, style: theme.textTheme.bodyMedium),
            ],
            const SizedBox(height: Space.xs),
            Text(
              t.place.fetched(when: t.agoFine(ref.fetchedAt, now)),
              style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
            ),
            if (webLink(ref.externalUrl) case final url?) ...[
              const SizedBox(height: Space.xxs),
              TextButton.icon(
                style: TextButton.styleFrom(padding: EdgeInsets.zero),
                onPressed: () => widgetRef.read(externalActionsProvider).openUrl(url),
                icon: const Icon(AppIcons.openExternal, size: 18),
                label: Text(t.place.viewSource),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
