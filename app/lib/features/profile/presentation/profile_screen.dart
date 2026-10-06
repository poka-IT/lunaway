import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lunaway/core/config/app_config.dart';
import 'package:lunaway/core/external_actions.dart';
import 'package:lunaway/core/layout/window_size.dart';
import 'package:lunaway/core/providers.dart';
import 'package:lunaway/features/places/application/places_providers.dart';
import 'package:lunaway/features/profile/application/settings_controller.dart';
import 'package:lunaway/i18n/strings.g.dart';
import 'package:lunaway/shared/icons/luna_icons.dart';
import 'package:lunaway/shared/labels.dart';
import 'package:lunaway/shared/theme/app_icons.dart';
import 'package:lunaway/shared/theme/tokens.dart';

/// Settings and the about page: language, the third-party layer, the data
/// kept on the device, and where everything comes from.
class ProfileScreen extends ConsumerWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.t;
    final size = WindowSize.of(context);
    const left = [_Brand(), _Language(), _OfflineData()];
    const right = [_About(), _Attributions()];
    final body = size == .expanded
        ? SingleChildScrollView(
            padding: const EdgeInsets.all(Space.xxl),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: Column(children: _spaced(left))),
                const SizedBox(width: Space.xxl),
                Expanded(child: Column(children: _spaced(right))),
              ],
            ),
          )
        : Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: ListView(
                padding: EdgeInsets.symmetric(
                  horizontal: size == .compact ? Space.l : Space.xxl,
                  vertical: Space.l,
                ),
                children: _spaced([...left, ...right]),
              ),
            ),
          );
    return Scaffold(
      appBar: AppBar(title: Text(t.profile.title)),
      body: body,
    );
  }

  static List<Widget> _spaced(List<Widget> cards) => [
    for (final (i, c) in cards.indexed) ...[if (i > 0) const SizedBox(height: Space.l), c],
  ];
}

class _Card extends StatelessWidget {
  const new({required this.title, required this.child, this.icon});

  final String title;
  final IconData? icon;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.xl, Space.lx, Space.xl, Space.s),
            child: Row(
              children: [
                if (icon != null) ...[
                  Icon(icon, color: theme.colorScheme.primary),
                  const SizedBox(width: Space.m),
                ],
                Expanded(
                  child: Semantics(
                    header: true,
                    child: Text(title, style: theme.textTheme.titleMedium),
                  ),
                ),
              ],
            ),
          ),
          child,
        ],
      ),
    );
  }
}

class _Brand extends StatelessWidget {
  const new();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.all(Space.xl),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(LunaTokens.of(context).radiusXl),
        gradient: LinearGradient(
          colors: [
            scheme.primary,
            Color.alphaBlend(scheme.tertiary.withValues(alpha: 0.35), scheme.primary),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: scheme.onPrimary.withValues(alpha: 0.14),
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: LunaIcon(LunaIcons.moonStar, size: 32, color: scheme.tertiaryContainer),
          ),
          const SizedBox(width: Space.l),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.t.appTitle,
                  style: theme.textTheme.headlineSmall?.copyWith(color: scheme.onPrimary),
                ),
                const SizedBox(height: Space.xxs),
                Text(
                  context.t.profile.noAccountNeeded,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: scheme.onPrimary.withValues(alpha: 0.92),
                  ),
                ),
              ],
            ),
          ),
        ],
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
    return _Card(
      title: t.profile.language,
      icon: AppIcons.language,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(Space.xl, Space.xxs, Space.xl, Space.xl),
        child: SegmentedButton<AppLocale?>(
          showSelectedIcon: false,
          segments: [
            ButtonSegment(value: null, label: Text(t.profile.languageSystem)),
            ButtonSegment(value: AppLocale.fr, label: Text(t.locale.fr)),
            ButtonSegment(value: AppLocale.en, label: Text(t.locale.en)),
          ],
          selected: {selected},
          onSelectionChanged: (s) => ref.read(settingsProvider.notifier).setLocale(s.first),
        ),
      ),
    );
  }
}

class _OfflineData extends ConsumerWidget {
  const new();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.t;
    final theme = Theme.of(context);
    final count = ref.watch(placeCountProvider).value;
    final size = ref.watch(storageSizeProvider).value;
    final last = ref.watch(lastSyncProvider).value;
    final status = ref.watch(syncControllerProvider);
    final now = ref.watch(clockProvider)();
    final running = status is SyncRunning;
    final muted = theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    return _Card(
      title: t.profile.offline,
      icon: AppIcons.offlineData,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(Space.xl, 0, Space.xl, Space.xl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              count == null ? ' ' : t.profile.offlinePlaces(n: count),
              style: theme.textTheme.titleLarge,
            ),
            const SizedBox(height: Space.xxs),
            Text(size == null ? ' ' : t.profile.offlineSize(size: t.fileSize(size)), style: muted),
            Text(
              last == null ? t.profile.neverSynced : t.profile.lastSync(when: t.ago(last, now)),
              style: muted,
            ),
            const SizedBox(height: Space.m),
            AnimatedSwitcher(
              duration: Motion.short,
              child: switch (status) {
                SyncRunning(:final received) => Row(
                  key: const ValueKey('running'),
                  children: [
                    const SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(strokeWidth: 2.5),
                    ),
                    const SizedBox(width: Space.m),
                    Expanded(
                      child: Text('${t.profile.syncing} · ${t.map.downloadingCount(n: received)}'),
                    ),
                  ],
                ),
                SyncDone() => Text(t.profile.syncDone, key: const ValueKey('done'), style: muted),
                SyncFailed() => Text(
                  t.profile.syncFailed,
                  key: const ValueKey('failed'),
                  style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.error),
                ),
                SyncIdle() => const SizedBox.shrink(key: ValueKey('idle')),
              },
            ),
            const SizedBox(height: Space.m),
            FilledButton.tonalIcon(
              onPressed: running ? null : () => ref.read(syncControllerProvider.notifier).sync(),
              icon: const Icon(AppIcons.sync),
              label: Text(t.profile.syncNow),
            ),
          ],
        ),
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
    Widget link(IconData icon, String label, String url) => ListTile(
      leading: Icon(icon),
      title: Text(label),
      trailing: const Icon(AppIcons.openExternal, size: 20),
      onTap: () => open(Uri.parse(url)),
    );
    return _Card(
      title: t.profile.about,
      icon: AppIcons.about,
      child: Column(
        children: [
          ListTile(
            leading: const Icon(AppIcons.confirmed),
            title: Text(t.profile.version(version: version)),
          ),
          link(AppIcons.website, t.profile.website, AppConfig.website),
          link(AppIcons.privacy, t.profile.privacy, AppConfig.privacyPolicy),
          link(AppIcons.sourceCode, t.profile.sourceCode, AppConfig.sourceCode),
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
          const SizedBox(height: Space.s),
        ],
      ),
    );
  }
}

class _Attributions extends ConsumerWidget {
  const new();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.t;
    final theme = Theme.of(context);
    final open = ref.read(externalActionsProvider).openUrl;
    Widget entry(String text, String url) => ListTile(
      title: Text(text, style: theme.textTheme.bodyMedium),
      trailing: const Icon(AppIcons.openExternal, size: 20),
      onTap: () => open(Uri.parse(url)),
    );
    return _Card(
      title: t.profile.attributions,
      icon: AppIcons.map,
      child: Column(
        children: [
          entry(t.profile.attributionOsm, 'https://www.openstreetmap.org/copyright'),
          entry(
            t.profile.attributionAtout,
            'https://www.etalab.gouv.fr/licence-ouverte-open-licence/',
          ),
          entry(t.profile.attributionTiles, 'https://openfreemap.org'),
          entry(
            t.profile.attributionFont,
            'https://github.com/googlefonts/atkinson-hyperlegible-next',
          ),
          const SizedBox(height: Space.s),
        ],
      ),
    );
  }
}
