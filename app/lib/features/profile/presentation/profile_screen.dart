import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lunaway/core/config/app_config.dart';
import 'package:lunaway/core/external_actions.dart';
import 'package:lunaway/core/layout/window_size.dart';
import 'package:lunaway/core/navigation_apps.dart';
import 'package:lunaway/core/providers.dart';
import 'package:lunaway/core/router/routes.dart';
import 'package:lunaway/features/account/application/account_providers.dart';
import 'package:lunaway/features/account/presentation/account_section.dart';
import 'package:lunaway/features/map/presentation/sync_banner.dart';
import 'package:lunaway/features/navigation/application/driving_aids.dart';
import 'package:lunaway/features/navigation/domain/enforcement.dart';
import 'package:lunaway/features/navigation/presentation/route_settings_section.dart';
import 'package:lunaway/features/offline/application/offline_providers.dart';
import 'package:lunaway/features/offline/presentation/offline_notices.dart';
import 'package:lunaway/features/places/application/places_providers.dart';
import 'package:lunaway/features/places/presentation/directions.dart';
import 'package:lunaway/features/profile/application/settings_controller.dart';
import 'package:lunaway/features/profile/data/settings_repository.dart';
import 'package:lunaway/features/vehicle/application/vehicle_providers.dart';
import 'package:lunaway/features/vehicle/domain/vehicle.dart';
import 'package:lunaway/features/vehicle/presentation/vehicle_editor.dart';
import 'package:lunaway/features/vehicle/presentation/vehicle_silhouette.dart';
import 'package:lunaway/i18n/strings.g.dart';
import 'package:lunaway/shared/labels.dart';
import 'package:lunaway/shared/theme/app_icons.dart';
import 'package:lunaway/shared/theme/motion.dart';
import 'package:lunaway/shared/theme/tokens.dart';
import 'package:lunaway/shared/theme/typography.dart';
import 'package:lunaway/shared/widgets/brand_mark.dart';
import 'package:lunaway/shared/widgets/segmented.dart';
import 'package:lunaway/shared/widgets/tab_reselect.dart';

/// The account (when there is one), the user's vehicle, the data kept on
/// the device, how the app looks and speaks, and where everything comes
/// from.
class ProfileScreen extends ConsumerWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.t;
    final theme = Theme.of(context);
    final size = WindowSize.of(context);
    final bottom = MediaQuery.paddingOf(context).bottom;
    final header = Padding(
      padding: const EdgeInsets.fromLTRB(0, Space.l, 0, Space.l),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            header: true,
            child: Text(t.profile.title, style: theme.textTheme.headlineMedium),
          ),
          const SizedBox(height: Space.xxs),
          Text(
            ref.watch(accountControllerProvider) is SignedIn
                ? t.profile.noTracking
                : t.profile.noAccountNeeded,
            style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
    const left = [
      AccountSection(),
      _Vehicle(),
      _OfflineData(),
      _Directions(),
      RouteSettingsSection(),
    ];
    const right = [_Appearance(), _Language(), _About(), _Attributions()];
    final padding = EdgeInsets.fromLTRB(
      size == .compact ? Space.l : Space.xxl,
      0,
      size == .compact ? Space.l : Space.xxl,
      bottom + Space.xl,
    );
    final body = size == .expanded
        ? SingleChildScrollView(
            padding: padding,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                header,
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: Column(children: _spaced(left))),
                    const SizedBox(width: Space.xxl),
                    Expanded(child: Column(children: _spaced(right))),
                  ],
                ),
              ],
            ),
          )
        : Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: ListView(
                padding: padding,
                children: [
                  header,
                  ..._spaced([...left, ...right]),
                ],
              ),
            ),
          );
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: ScrollsToTopOnReselect(tab: AppTabs.profile, child: body),
      ),
    );
  }

  static List<Widget> _spaced(List<Widget> sections) => [
    for (final (i, c) in sections.indexed) ...[if (i > 0) const SizedBox(height: Space.xxl), c],
  ];
}

/// A titled group of the profile.
class _Section extends StatelessWidget {
  const new({required this.title, required this.child, this.icon});

  final String title;
  final IconData? icon;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: Space.xs, bottom: Space.s),
          child: Row(
            children: [
              if (icon != null) ...[
                Icon(icon, size: 20, color: theme.colorScheme.onSurfaceVariant),
                const SizedBox(width: Space.s),
              ],
              Expanded(
                child: Semantics(
                  header: true,
                  child: Text(title, style: theme.textTheme.titleLarge),
                ),
              ),
            ],
          ),
        ),
        DecoratedBox(
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(LunaTokens.radiusXl),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(LunaTokens.radiusXl),
            child: Material(type: MaterialType.transparency, child: child),
          ),
        ),
      ],
    );
  }
}

class _Vehicle extends ConsumerWidget {
  const new();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.t;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final vehicle = ref.watch(vehicleProvider).value;
    String dims(Vehicle v) => [
      if (v.heightM != null) t.vehicle.heightShort(value: t.metres(v.heightM!)),
      if (v.widthM != null) t.vehicle.widthShort(value: t.metres(v.widthM!)),
      if (v.lengthM != null) t.vehicle.lengthShort(value: t.metres(v.lengthM!)),
      if (v.weightT != null) t.tonnes(v.weightT!),
    ].join(' · ');
    return _Section(
      title: t.vehicle.title,
      icon: AppIcons.vehicle,
      child: vehicle == null
          ? Padding(
              padding: const EdgeInsets.all(Space.l),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(t.vehicle.none, style: theme.textTheme.bodyLarge),
                  const SizedBox(height: Space.m),
                  FilledButton.icon(
                    onPressed: () => showVehicleEditor(context),
                    icon: const Icon(AppIcons.add),
                    label: Text(t.vehicle.add),
                  ),
                ],
              ),
            )
          : InkWell(
              mouseCursor: WidgetStateMouseCursor.clickable,
              onTap: () => showVehicleEditor(context),
              child: Padding(
                padding: const EdgeInsets.all(Space.l),
                child: Row(
                  children: [
                    VehicleSilhouette(
                      vehicle.type,
                      towing: vehicle.towing,
                      color: scheme.onSurface,
                      width: 84,
                    ),
                    const SizedBox(width: Space.l),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            vehicle.towing == Towing.none
                                ? t.vehicleType(vehicle.type)
                                : '${t.vehicleType(vehicle.type)} · ${t.towing(vehicle.towing)}',
                            style: theme.textTheme.titleMedium,
                          ),
                          const SizedBox(height: Space.xxs),
                          Text(
                            dims(vehicle),
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Icon(
                      AppIcons.rename,
                      color: scheme.onSurfaceVariant,
                      semanticLabel: t.vehicle.edit,
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}

class _OfflineData extends ConsumerWidget {
  const new();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // The web keeps no places: nothing to download, nothing to show here.
    if (!ref.watch(keepsPlacesProvider)) return const SizedBox.shrink();
    final t = context.t;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final count = ref.watch(placeCountProvider).value;
    final size = ref.watch(storageSizeProvider).value;
    final state = ref.watch(syncStateProvider).value;
    final status = ref.watch(syncControllerProvider);
    final now = ref.watch(minuteClockProvider).value ?? ref.read(clockProvider)();
    final running = status is SyncRunning;
    final complete = state?.completedAt != null;
    final muted = theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant);
    final last = state?.completedAt;
    return _Section(
      title: t.profile.offline,
      icon: AppIcons.offlineData,
      child: Padding(
        padding: const EdgeInsets.all(Space.l),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: count == null ? ' ' : t.number(count),
                    style: LunaType.number(30, weight: 420, color: scheme.onSurface),
                  ),
                  TextSpan(
                    text: count == null ? '' : ' ${t.profile.placesOnDevice(n: count)}',
                    style: theme.textTheme.titleMedium,
                  ),
                ],
              ),
            ),
            const SizedBox(height: Space.xs),
            if (size != null) Text(t.profile.offlineSize(size: t.fileSize(size)), style: muted),
            Text(
              !complete
                  ? (count ?? 0) > 0
                        ? t.sync.incompleteShort
                        : t.profile.neverSynced
                  : t.profile.lastSync(when: t.ago(last!, now)),
              style: !complete && (count ?? 0) > 0
                  ? theme.textTheme.bodyMedium?.copyWith(
                      color: scheme.onSurface,
                      fontWeight: FontWeight.w600,
                    )
                  : muted,
            ),
            AnimatedSwitcher(
              duration: Motion.of(context, Motion.short),
              child: switch (status) {
                SyncRunning(:final received) => Padding(
                  key: const ValueKey('running'),
                  padding: const EdgeInsets.only(top: Space.m),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const ClipRRect(
                        borderRadius: BorderRadius.all(Radius.circular(LunaTokens.radiusPill)),
                        child: LinearProgressIndicator(minHeight: 6),
                      ),
                      const SizedBox(height: Space.xs),
                      Text(
                        '${t.profile.syncing} · ${t.map.downloadingCount(n: received, count: t.number(received))}',
                        style: muted,
                      ),
                    ],
                  ),
                ),
                SyncFailed(:final failure, :final retryIn) => Padding(
                  key: const ValueKey('failed'),
                  padding: const EdgeInsets.only(top: Space.m),
                  child: Text(
                    retryIn == null
                        ? syncFailureText(t, failure)
                        : '${syncFailureText(t, failure)} ${t.sync.willRetry}',
                    style: theme.textTheme.bodyMedium?.copyWith(color: scheme.error),
                  ),
                ),
                _ => const SizedBox.shrink(key: ValueKey('idle')),
              },
            ),
            const SizedBox(height: Space.m),
            OutlinedButton.icon(
              onPressed: running
                  ? null
                  : () => ref.read(syncControllerProvider.notifier).sync(asked: true),
              icon: const Icon(AppIcons.sync),
              label: Text(!complete && (count ?? 0) > 0 ? t.sync.resume : t.profile.syncNow),
            ),
            const Divider(height: Space.xxl),
            const OfflineMapsEntry(),
          ],
        ),
      ),
    );
  }
}

class _Directions extends ConsumerWidget {
  const new();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.t;
    final id = ref.watch(settingsProvider.select((s) => s.navigationApp));
    final app = NavigationApp.fromId(id);
    return _Section(
      title: t.directions.settingTitle,
      icon: AppIcons.navigationApps,
      child: ListTile(
        title: Text(app == null ? t.directions.askEachTime : app.label(t)),
        subtitle: Text(t.directions.settingHint),
        trailing: const Icon(AppIcons.chevron),
        onTap: () async {
          final actions = ref.read(externalActionsProvider);
          final settings = ref.read(settingsProvider.notifier);
          final available = await availableNavigationApps(
            actions,
            NavigationApp.offeredOn(Theme.of(context).platform, web: kIsWeb),
          );
          if (!context.mounted) return;
          final picked = await showNavigationAppChooser(context, available, selected: app);
          if (picked == null) return;
          await settings.setNavigationApp(picked.remember ? picked.app.id : null);
        },
      ),
    );
  }
}

class _Appearance extends ConsumerWidget {
  const new();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.t;
    final theme = Theme.of(context);
    final selected = ref.watch(settingsProvider.select((s) => s.theme));
    return _Section(
      title: t.profile.appearance,
      icon: AppIcons.appearance,
      child: Padding(
        padding: const EdgeInsets.all(Space.l),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            LunaSegmented<ThemePreference>(
              segments: [
                Segment(
                  value: ThemePreference.auto,
                  label: t.profile.themeAuto,
                  icon: AppIcons.themeAuto,
                ),
                Segment(
                  value: ThemePreference.light,
                  label: t.profile.themeLight,
                  icon: AppIcons.themeLight,
                ),
                Segment(
                  value: ThemePreference.dark,
                  label: t.profile.themeDark,
                  icon: AppIcons.themeDark,
                ),
              ],
              selected: selected,
              onChanged: (p) => ref.read(settingsProvider.notifier).setTheme(p),
            ),
            const SizedBox(height: Space.s),
            Text(
              switch (selected) {
                ThemePreference.auto => t.profile.themeAutoHint,
                ThemePreference.light => t.profile.themeLightHint,
                ThemePreference.dark => t.profile.themeDarkHint,
              },
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Language extends ConsumerWidget {
  const new();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.t;
    final code = ref.watch(settingsProvider.select((s) => s.localeCode));
    final selected = code == null ? null : AppLocaleUtils.parse(code);
    final autoTranslate = ref.watch(settingsProvider.select((s) => s.autoTranslateReviews));
    // Each language under its own name, in the order of those names, and
    // read aloud in its language by a screen reader.
    final languages = [
      (AppLocale.de, t.locale.de),
      (AppLocale.en, t.locale.en),
      (AppLocale.es, t.locale.es),
      (AppLocale.fr, t.locale.fr),
      (AppLocale.it, t.locale.it),
      (AppLocale.nl, t.locale.nl),
    ];
    return _Section(
      title: t.profile.language,
      icon: AppIcons.language,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: Space.xs),
            child: RadioGroup<AppLocale?>(
              groupValue: selected,
              onChanged: (l) => ref.read(settingsProvider.notifier).setLocale(l),
              child: Column(
                children: [
                  RadioListTile<AppLocale?>(value: null, title: Text(t.profile.languageSystem)),
                  for (final (locale, name) in languages)
                    RadioListTile<AppLocale?>(
                      value: locale,
                      title: Text(name, locale: locale.flutterLocale),
                    ),
                ],
              ),
            ),
          ),
          const Divider(height: 1),
          SwitchListTile(
            value: autoTranslate,
            onChanged: (on) => ref.read(settingsProvider.notifier).setAutoTranslateReviews(on: on),
            title: Text(t.translation.autoReviews),
            subtitle: Text(t.translation.autoReviewsHint),
          ),
        ],
      ),
    );
  }
}

class _About extends ConsumerWidget {
  const new();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.t;
    final version = ref.watch(appVersionProvider);
    final open = ref.read(externalActionsProvider).openUrl;
    final language = t.$meta.locale.languageCode;
    Widget link(IconData icon, String label, Uri url) => ListTile(
      leading: Icon(icon),
      title: Text(label),
      trailing: const Icon(AppIcons.openExternal, size: 20),
      onTap: () => open(url),
    );
    return _Section(
      title: t.profile.about,
      icon: AppIcons.about,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.l, Space.l, Space.l, Space.xs),
            child: Row(
              children: [
                const BrandMark(height: 36),
                const SizedBox(width: Space.m),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(t.appTitle, style: Theme.of(context).textTheme.titleLarge),
                      Text(
                        t.profile.version(version: version),
                        style: Theme.of(context).textTheme.bodyMedium
                            ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          // What the routes rest on, said here once rather than before
          // every trip.
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.l, Space.s, Space.l, Space.s),
            child: Text(
              t.profile.routeData,
              style: Theme.of(context).textTheme.bodyMedium
                  ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
          ),
          link(AppIcons.website, t.profile.website, AppConfig.sitePage(language, '')),
          link(AppIcons.privacy, t.profile.privacy, AppConfig.sitePage(language, 'privacy')),
          link(AppIcons.sourceCode, t.profile.sourceCode, Uri.parse(AppConfig.sourceCode)),
          ListTile(
            leading: const Icon(AppIcons.licences),
            title: Text(t.profile.licences),
            subtitle: Text(t.profile.appLicence),
            trailing: const Icon(AppIcons.chevron),
            onTap: () => showLicensePage(
              context: context,
              applicationName: t.appTitle,
              applicationVersion: version,
            ),
          ),
        ],
      ),
    );
  }
}

/// Every source whose data the app shows, by what it brings, each with its
/// licence; a link where one licence covers it. The offline maps' credits
/// only where the app makes offline maps.
class _Attributions extends ConsumerWidget {
  const new();

  static const _odbl = 'https://opendatacommons.org/licenses/odbl/';
  static const _licenceOuverte = 'https://www.etalab.gouv.fr/licence-ouverte-open-licence/';
  static const _ccBy = 'https://creativecommons.org/licenses/by/4.0/';
  static const _ccBySa = 'https://creativecommons.org/licenses/by-sa/4.0/';

  /// The lists of speed cameras `profile.attributionDangerZones` names, and
  /// Catalonia's, suspended (its host refuses robots) and no longer served.
  static const _namedCameraLists = {
    'securite-routiere',
    'fr-dsr',
    'pl-canard',
    'lu-pch-radars',
    'be-bru-radars',
    'no-nvdb-atk',
    'ie-garda',
    'cat-sct-radars',
    'osm',
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.t;
    final theme = Theme.of(context);
    final open = ref.read(externalActionsProvider).openUrl;
    final offlineMaps = ref.watch(offlineMapsSupportedProvider);
    Widget entry(String text, String url) => ListTile(
      title: Text(text, style: theme.textTheme.bodyMedium),
      trailing: const Icon(AppIcons.openExternal, size: 20),
      onTap: () => open(Uri.parse(url)),
    );
    // Several licences, or a partner whose address would name it: the
    // text alone.
    Widget plain(String text) => ListTile(title: Text(text, style: theme.textTheme.bodyMedium));
    Widget group(String title) => Padding(
      padding: const EdgeInsets.fromLTRB(Space.l, Space.l, Space.l, Space.xxs),
      child: Semantics(
        header: true,
        child: Text(
          title,
          style: theme.textTheme.labelLarge?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
      ),
    );
    return _Section(
      title: t.profile.attributions,
      icon: AppIcons.attributions,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          group(t.profile.creditsPlaces),
          entry(t.profile.attributionOsm, 'https://www.openstreetmap.org/copyright'),
          entry(t.profile.attributionOdbl, _odbl),
          entry(t.profile.attributionDatatourisme, _licenceOuverte),
          entry(t.profile.attributionAtout, _licenceOuverte),
          entry(t.profile.attributionCommunes, _odbl),
          entry(t.profile.attributionCommunityPlaces, _odbl),
          // The partner's places, reviews and photos under the wording its
          // agreement sets, never its own name, and no link that would give
          // it.
          ListTile(
            title: Text(t.sources.extcom.label, style: theme.textTheme.bodyMedium),
            subtitle: Text(t.profile.attributionExtcom),
          ),
          group(t.profile.creditsContent),
          entry(t.profile.attributionCommunity, _ccBy),
          plain(t.profile.attributionCommons),
          plain(t.profile.attributionPanoramax),
          entry(t.profile.attributionWikipedia, _ccBySa),
          entry(t.profile.attributionMangrove, _ccBy),
          entry(t.profile.attributionTranslation, _ccBy),
          group(t.profile.creditsRoutes),
          entry(t.profile.attributionBdTopo, _licenceOuverte),
          plain(t.profile.attributionRoadEvents),
          plain(t.profile.attributionRoadEventsAbroad),
          plain(t.profile.attributionDangerZones),
          // A list the sentence above does not name yet, as the API
          // credits it.
          for (final s
              in ref.watch(heldEnforcementSourcesProvider).value ?? const <EnforcementSource>[])
            if (!_namedCameraLists.contains(s.id))
              plain(t.profile.attributionCameraSource(attribution: s.attribution)),
          entry(t.profile.attributionPoiOdbl, _odbl),
          entry(t.profile.attributionPoiLo, _licenceOuverte),
          // The establishments the search finds; the licence named without
          // a link, whose host the app would otherwise name.
          plain(t.profile.attributionOverture),
          group(t.profile.creditsSearch),
          entry(t.profile.attributionAddresses, _licenceOuverte),
          entry(t.profile.attributionAddressesOsm, _odbl),
          group(t.profile.creditsMap),
          entry(t.profile.attributionTiles, 'https://github.com/protomaps/basemaps'),
          if (offlineMaps) ...[
            entry(t.profile.attributionPacks, _odbl),
            entry(
              t.profile.attributionOfflineLabels,
              'https://github.com/protomaps/basemaps-assets',
            ),
          ],
          group(t.profile.creditsApp),
          entry(t.profile.attributionFonts, 'https://github.com/undercasetype/Fraunces'),
          entry(t.profile.attributionIcons, 'https://github.com/phosphor-icons/flutter'),
        ],
      ),
    );
  }
}
