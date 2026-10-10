import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lunaway/core/external_actions.dart';
import 'package:lunaway/core/geo/geo.dart';
import 'package:lunaway/core/providers.dart';
import 'package:lunaway/core/time/place_zone.dart';
import 'package:lunaway/features/community/application/community_providers.dart';
import 'package:lunaway/features/community/domain/contribution.dart';
import 'package:lunaway/features/community/presentation/contribute.dart';
import 'package:lunaway/features/community/presentation/place_community.dart';
import 'package:lunaway/features/favorites/application/favorites_providers.dart';
import 'package:lunaway/features/favorites/domain/saved_point.dart';
import 'package:lunaway/features/favorites/presentation/point_saving.dart';
import 'package:lunaway/features/map/application/map_flow.dart';
import 'package:lunaway/features/map/application/map_state.dart';
import 'package:lunaway/features/map/presentation/point_details.dart';
import 'package:lunaway/features/places/application/places_providers.dart';
import 'package:lunaway/features/places/data/graphql/graphql_client.dart';
import 'package:lunaway/features/places/domain/place.dart';
import 'package:lunaway/features/places/domain/place_content.dart';
import 'package:lunaway/features/places/presentation/coordinates_card.dart';
import 'package:lunaway/features/places/presentation/place_extras_view.dart';
import 'package:lunaway/features/places/presentation/rating_text.dart';
import 'package:lunaway/features/poi/application/poi_providers.dart';
import 'package:lunaway/features/poi/data/poi_operations.dart';
import 'package:lunaway/features/poi/data/poi_repository.dart';
import 'package:lunaway/features/poi/domain/poi.dart';
import 'package:lunaway/features/poi/presentation/fuel_trend.dart';
import 'package:lunaway/features/poi/presentation/poi_labels.dart';
import 'package:lunaway/features/vehicle/application/vehicle_providers.dart';
import 'package:lunaway/features/vehicle/domain/vehicle.dart';
import 'package:lunaway/i18n/strings.g.dart';
import 'package:lunaway/shared/hours_text.dart';
import 'package:lunaway/shared/images/cached_image.dart';
import 'package:lunaway/shared/images/retrying_image.dart';
import 'package:lunaway/shared/images/thumbhash.dart';
import 'package:lunaway/shared/labels.dart';
import 'package:lunaway/shared/messages.dart';
import 'package:lunaway/shared/source_names.dart';
import 'package:lunaway/shared/theme/app_icons.dart';
import 'package:lunaway/shared/theme/phosphor_glyphs.dart';
import 'package:lunaway/shared/theme/tokens.dart';
import 'package:lunaway/shared/widgets/source_badge.dart';
import 'package:lunaway/shared/widgets/status_views.dart';

/// The page of a point of interest, for the sheet (compact) and the panel
/// (wider): what it is, a photo from an open source, whether it is open and
/// until when, how far, the prices of a fuel station with their freshness,
/// "still there?", what one finds there by what it is ([PoiProfile]: a
/// restaurant's cuisine, a hotel's stars, what a garage works on), the
/// hours, the contact, the ratings and reviews and the sources. It opens at
/// once from what the map tile or the search said; the rest comes from the
/// API, or from the copy kept since the last read. Nothing shows of what
/// the source does not say.
class PoiDetails extends ConsumerWidget {
  const new({
    required this.feature,
    this.from,
    this.scrollController,
    this.onClose,
    this.actions = false,
    this.bottomPadding = Space.huge,
    this.copyCoordinates = false,
    super.key,
  });

  final PoiFeature feature;

  /// The coordinates card's own copy button: a page shown without the
  /// action bar (its card over a route).
  final bool copyCoordinates;

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
          copyCoordinates: copyCoordinates,
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
        copyCoordinates: copyCoordinates,
      ),
      AsyncLoading() => _Body(
        feature: feature,
        from: from,
        loading: true,
        scrollController: scrollController,
        onClose: onClose,
        bottomPadding: bottomPadding,
        copyCoordinates: copyCoordinates,
      ),
    };
    if (!actions) return body;
    return Column(
      children: [
        Expanded(child: body),
        PointActionBar(position: feature.position, poi: feature),
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
    this.copyCoordinates = false,
  });

  final PoiFeature feature;
  final bool copyCoordinates;
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
        if (poi != null && poi.photos.isNotEmpty) ...[
          const SizedBox(height: Space.l),
          _PoiPhoto(poi: poi, title: t.poiTitle(poi.name, poi.kind)),
        ],
        SavedPointBlock(
          id: savedPoiPointId(feature.id),
          shownName: t.poiTitle(poi?.name ?? feature.name, feature.kind),
        ),
        // A shop kept in the favourites is a place to set out from, as any
        // saved point.
        if (ref.watch(savedPointProvider(savedPoiPointId(feature.id))).value case final saved?) ...[
          const SizedBox(height: Space.l),
          StartHereButton(position: feature.position, label: saved.name),
        ],
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
          // The vehicle's fuel when the station sells it, else the first.
          if ((mine.isEmpty ? fuel.sortedPrices : fuel.pricesFirst(mine)).firstOrNull
              case final shown?) ...[
            gap,
            FuelTrendCard(poiId: poi!.id, fuel: shown.fuel),
          ],
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
        CoordinatesCard(position: feature.position, copy: copyCoordinates),
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
    final profile = PoiProfile.of(poi.kind);
    Future<void> run(Future<bool> Function() open) async {
      final messenger = ScaffoldMessenger.maybeOf(context);
      final failed = t.place.openFailed;
      if (!await open()) showMessage(messenger, failed);
    }

    // What one finds there, each said only when the source says it: a no
    // is said too, nothing is not.
    final facilities = <_Line>[
      if (profile == PoiProfile.eat) ...[
        if (poi.takeaway case final yes?)
          _Line(
            icon: PoiLookIcons.takeaway,
            text: yes ? t.poi.details.takeaway : t.poi.details.noTakeaway,
          ),
        if (poi.delivery case final yes?)
          _Line(
            icon: PoiLookIcons.delivery,
            text: yes ? t.poi.details.delivery : t.poi.details.noDelivery,
          ),
        if (poi.outdoorSeating case final yes?)
          _Line(
            icon: PoiLookIcons.outdoorSeating,
            text: yes ? t.poi.details.outdoorSeating : t.poi.details.noOutdoorSeating,
          ),
      ],
      if (profile == PoiProfile.eat || profile == PoiProfile.stay)
        if (poi.reservation case final r?)
          _Line(icon: PoiLookIcons.reservation, text: t.reservation(r)),
      if (profile == PoiProfile.health)
        if (poi.emergency case final yes?)
          _Line(
            icon: PoiLookIcons.emergency,
            text: yes ? t.poi.details.emergency : t.poi.details.noEmergency,
          ),
      if (profile == PoiProfile.eat || profile == PoiProfile.stay || profile == PoiProfile.shop)
        if (poi.internetAccess case final yes?)
          _Line(icon: PoiLookIcons.wifi, text: yes ? t.poi.details.wifi : t.poi.details.noWifi),
      if (profile.facilities)
        if (t.wheelchair(poi.wheelchair) case final access?)
          _Line(icon: PoiLookIcons.wheelchair, text: access),
    ];
    return [
      if (profile == PoiProfile.eat && poi.cuisine.isNotEmpty)
        _Section(
          title: t.poi.details.cuisineTitle,
          child: _Chips([for (final c in poi.cuisine) t.cuisine(c)]),
        ),
      if (profile == PoiProfile.eat && poi.diets.isNotEmpty)
        _Section(
          title: t.poi.details.dietsTitle,
          child: _Chips([for (final d in poi.diets) t.diet(d)]),
        ),
      if (facilities.isNotEmpty)
        _Section(
          title: t.poi.details.facilitiesTitle,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: facilities),
        ),
      if (profile == PoiProfile.garage && poi.vehicleServices.isNotEmpty)
        _Section(
          title: t.poi.details.vehicleServicesTitle,
          child: _Chips([for (final v in poi.vehicleServices) t.vehicleService(v)]),
        ),
      if (poi.openingHours != null)
        _Section(
          // A market's hours are the days it is held.
          title: poi.kind == PoiKind.marketplace ? t.poi.marketDays : t.place.hours,
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
        _Section(title: t.poi.paymentTitle, child: _Chips(t.payments(poi.payment))),
      if (poi.fee != null || poi.seasonal == true)
        Padding(
          padding: const EdgeInsets.only(top: Space.l),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (poi.fee != null)
                _Line(
                  icon: poi.fee! ? AppIcons.paid : AppIcons.free,
                  text: poi.fee! ? t.poi.fee : t.poi.free,
                ),
              if (poi.seasonal == true) _Line(icon: PoiLookIcons.seasonal, text: t.poi.seasonal),
            ],
          ),
        ),
      // What a wash or a garage takes, when OpenStreetMap says it: a
      // motorhome's height is what a car wash refuses.
      if (poi.motorhome != null || poi.hgv != null || poi.maxHeightM != null)
        Padding(
          padding: const EdgeInsets.only(top: Space.l),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (poi.motorhome case final yes?)
                _Line(
                  icon: AppIcons.vehicle,
                  text: yes ? t.poi.vehicles.motorhomeYes : t.poi.vehicles.motorhomeNo,
                ),
              if (poi.hgv case final yes?)
                _Line(
                  icon: AppIcons.towing,
                  text: yes ? t.poi.vehicles.hgvYes : t.poi.vehicles.hgvNo,
                ),
              if (poi.maxHeightM case final height?)
                _Line(
                  icon: AppIcons.height,
                  text: t.poi.vehicles.maxHeight(height: t.metres(height)),
                ),
            ],
          ),
        ),
      if (website != null || phones.isNotEmpty)
        _Section(
          title: t.place.contact,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final phone in phones)
                _LinkRow(
                  icon: AppIcons.call,
                  title: t.place.call,
                  subtitle: readablePhone(phone),
                  onTap: () => run(() => actions.dial(phone)),
                ),
              if (website != null)
                _LinkRow(
                  icon: AppIcons.website,
                  title: t.place.website,
                  subtitle: website.host,
                  onTap: () => run(() => actions.openUrl(website)),
                ),
            ],
          ),
        ),
      _PoiReviews(poi: poi),
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
        onPressed: () => ref.read(mapFlowProvider.notifier).select(PlaceSelection(placeId)),
        icon: const Icon(AppIcons.back, size: 18),
        label: Text(
          place == null ? t.poi.backToPlace : t.poi.backTo(name: t.summaryTitle(place.summary)),
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
  static const IconData takeaway = PhosphorRegular.bagSimple;
  static const IconData delivery = PhosphorRegular.moped;
  static const IconData outdoorSeating = PhosphorRegular.umbrella;
  static const IconData reservation = PhosphorRegular.calendarCheck;
  static const IconData wifi = PhosphorRegular.wifiHigh;
  static const IconData emergency = PhosphorRegular.firstAid;
  static const IconData wheelchair = PhosphorRegular.wheelchair;
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
    final title = t.poiTitle(poi?.name ?? feature.name, feature.kind);
    // An unnamed point is titled by its kind: the line under it does not
    // say it again ("Borne de recharge" twice).
    final subtitle = [
      if (t.poiKind(feature.kind) != title) t.poiKind(feature.kind),
      // A hotel's stars; another kind's would be another scale.
      if (poi?.stars case final stars?
          when stars > 0 && PoiProfile.of(feature.kind) == PoiProfile.stay)
        t.poi.details.stars(n: stars),
      if (poi?.brand case final brand? when brand != poi?.name) brand,
      ?city,
    ];
    // Lunaway's travellers' rating first, else another source's, as the
    // reviews below show them with their badges.
    final rating = [...?poi?.ratings, ...?poi?.externalRatings].firstOrNull;
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
                  title,
                  style: theme.textTheme.headlineSmall,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (subtitle.isNotEmpty) ...[
                const SizedBox(height: Space.xxs),
                Text(
                  subtitle.join(' · '),
                  style: theme.textTheme.bodyLarge?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ],
              if (rating != null) ...[
                const SizedBox(height: Space.xs),
                RatingText(
                  average: rating.average,
                  count: rating.count,
                  externalSource: isLunawayCommunity(rating.sourceId)
                      ? null
                      : sourceName(t, rating.sourceId),
                ),
              ],
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
  const new({
    required this.icon,
    required this.title,
    required this.onTap,
    this.subtitle,
    this.subtitleLines = 1,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final int subtitleLines;
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
          mouseCursor: WidgetStateMouseCursor.clickable,
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
                            maxLines: subtitleLines,
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

/// What a page puts forward of a point, by what it is: a restaurant its
/// cuisine and what one finds there, a hotel its stars, a garage what it
/// works on.
enum PoiProfile {
  /// Restaurants, cafés, bars: cuisine, diets, takeaway, terrace, booking,
  /// Wi-Fi.
  eat,

  /// Hotels and other places to stay: stars, booking, Wi-Fi.
  stay,

  /// Health: emergencies.
  health,

  /// Garages, tyres, dealers: what they work on, the vehicles they take.
  garage,

  /// Shops and services: payment, access.
  shop,

  /// Leisure and sights: hours, website, access.
  leisure,

  /// Water, fuel, vending machines: what the page said before.
  other;

  static PoiProfile of(PoiKind kind) => switch (kind) {
    .carRepair ||
    .carWash ||
    .tyres ||
    .carParts ||
    .carDealer ||
    .motorcycleShop ||
    .motorhomeShop ||
    .vehicleInspection => garage,
    _ => switch (kind.category) {
      .food => eat,
      .lodging => stay,
      .health => health,
      .leisure || .sights => leisure,
      .shopping || .services || .groceries => shop,
      .water || .fuel || .vending => other,
    },
  };

  /// Whether the page says what one finds there (a terrace, Wi-Fi) for
  /// this kind of point.
  bool get facilities => this != other && this != garage;
}

/// The page of Google Maps searching [name] around [position], at the zoom
/// of a street: opened by the user from the page, never fetched by the app.
Uri googleMapsSearchUrl(String name, LatLng position) => Uri.parse(
  'https://www.google.com/maps/search/${Uri.encodeComponent(name)}/'
  '@${position.lat.toStringAsFixed(6)},${position.lon.toStringAsFixed(6)},17z',
);

/// The first photo of a point, from an open source, at the width of the
/// page; its frame is reserved before it arrives. A tap opens every photo
/// full screen; under it, its author, its licence and its page.
class _PoiPhoto extends ConsumerWidget {
  const new({required this.poi, required this.title});

  final Poi poi;
  final String title;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.t;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final photo = poi.photos.first;
    final fetcher = ref.watch(imageFetcherProvider);
    final hash = photo.thumbhash;
    final placeholder = hash == null
        ? ColoredBox(color: scheme.surfaceContainerHigh)
        : Image(image: ThumbHashImage(hash), fit: BoxFit.cover, excludeFromSemantics: true);
    final terms = [photoCredit(t, photo), ?termsLine(t, photo.terms)].join(' · ');
    final page = webLink(photo.terms?.pageUrl);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          button: true,
          label: '${t.poi.details.photoOf(name: title)}, $terms',
          child: ClipRRect(
            borderRadius: BorderRadius.circular(LunaTokens.radiusXl),
            child: AspectRatio(
              aspectRatio: 16 / 9,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  RetryingImage(
                    image: ResizeImage(CachedImage(photo.largeUrl, fetcher: fetcher), width: 1080),
                    fit: BoxFit.cover,
                    placeholder: placeholder,
                    waiting: placeholder,
                    error: placeholder,
                  ),
                  Material(
                    type: MaterialType.transparency,
                    child: InkWell(
                      mouseCursor: WidgetStateMouseCursor.clickable,
                      onTap: () => showPhotoViewer(
                        context,
                        poi.photos,
                        0,
                        fetcher: ref.read(imageFetcherProvider),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: Space.xs),
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: Space.s,
          children: [
            Text(terms, style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
            if (page != null)
              TextButton.icon(
                style: TextButton.styleFrom(padding: EdgeInsets.zero),
                onPressed: () => ref.read(externalActionsProvider).openUrl(page),
                icon: const Icon(AppIcons.openExternal, size: 18),
                label: Text(t.place.viewSource),
              ),
          ],
        ),
      ],
    );
  }
}

/// The ratings and reviews of a point: each source's average with its
/// badge, the account's own rating and review, the reviews of Lunaway's
/// travellers and of the other sources, newest first, and a link to read
/// more on Google Maps.
class _PoiReviews extends ConsumerWidget {
  const new({required this.poi});

  final Poi poi;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.t;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final read = ref.watch(pointReviewsProvider(poi.id));
    final ratings = [...poi.ratings, ...poi.externalRatings];
    final ownText =
        OwnReview.of(ownPoiReview(ref, poi.id), ref.watch(pendingForPoiProvider(poi.id)))?.text !=
        null;
    final muted = theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant);
    final named = poi.name;
    return _Section(
      title: t.place.reviewsTitle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (ratings.isNotEmpty) ...[
            Wrap(
              spacing: Space.ml,
              runSpacing: Space.s,
              children: [
                for (final r in ratings)
                  Wrap(
                    spacing: Space.s,
                    runSpacing: Space.xxs,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      SourceBadge(label: itemSourceLabel(t, r.sourceId), maxLines: 2),
                      RatingText(average: r.average, count: r.count),
                    ],
                  ),
              ],
            ),
            const SizedBox(height: Space.m),
          ],
          // A care practitioner's practice takes no rating: a review would
          // say a patient's health under a public licence.
          if (poi.takesReviews) ...[
            YourReview.poi(poiId: poi.id, name: t.poiTitle(poi.name, poi.kind)),
            const SizedBox(height: Space.l),
          ],
          ...switch (read) {
            AsyncData(value: final reviews?) => [
              for (final r in _newestFirst([...reviews.ours.nodes, ...reviews.external.nodes]))
                Padding(
                  padding: const EdgeInsets.only(bottom: Space.sm),
                  child: ReviewCard(review: r, ofPoi: true),
                ),
              if (reviews.ours.nodes.isEmpty && reviews.external.nodes.isEmpty)
                Text(ownText ? t.place.noOtherReviews : t.place.noReviews, style: muted),
            ],
            AsyncData() => const <Widget>[],
            // Offline, plainly: the reviews are read online, nothing is
            // broken.
            AsyncError(:final error)
                when error is GraphQLNetworkException && error is! GraphQLRateLimitedException =>
              [Text(t.poi.details.reviewsOffline, style: muted)],
            AsyncError() => [
              MessageView(
                title: t.poi.details.reviewsError,
                action: t.common.retry,
                onAction: () => ref.invalidate(pointReviewsProvider(poi.id)),
                compact: true,
              ),
            ],
            AsyncLoading() => const [Skeleton(height: 96, radius: 20)],
          },
          if (named != null && named.trim().isNotEmpty) ...[
            const SizedBox(height: Space.s),
            _LinkRow(
              icon: AppIcons.googleMaps,
              title: t.poi.details.googleMaps,
              subtitle: t.poi.details.googleMapsHint,
              subtitleLines: 2,
              onTap: () => ref
                  .read(externalActionsProvider)
                  .openUrl(googleMapsSearchUrl(named, poi.position)),
            ),
          ],
        ],
      ),
    );
  }

  static List<Review> _newestFirst(List<Review> reviews) =>
      reviews..sort((a, b) => b.createdAt.compareTo(a.createdAt));
}
