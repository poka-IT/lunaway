import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:logging/logging.dart';
import 'package:lunaway/core/config/app_config.dart';
import 'package:lunaway/core/external_actions.dart';
import 'package:lunaway/core/providers.dart';
import 'package:lunaway/core/router/routes.dart';
import 'package:lunaway/features/account/application/account_providers.dart';
import 'package:lunaway/features/account/domain/account.dart';
import 'package:lunaway/features/community/application/community_providers.dart';
import 'package:lunaway/features/community/domain/contribution.dart';
import 'package:lunaway/features/community/presentation/contribute.dart';
import 'package:lunaway/i18n/strings.g.dart';
import 'package:lunaway/shared/labels.dart';
import 'package:lunaway/shared/messages.dart';
import 'package:lunaway/shared/theme/app_icons.dart';
import 'package:lunaway/shared/theme/app_theme.dart';
import 'package:lunaway/shared/theme/tokens.dart';
import 'package:lunaway/shared/widgets/night_scene.dart';
import 'package:lunaway/shared/widgets/status_views.dart';
import 'package:lunaway/shared/widgets/sub_page.dart';

final _log = Logger('account');

/// The authors the account hides, each with the way back.
class MutedAuthorsScreen extends ConsumerWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.t;
    final account = ref.watch(accountControllerProvider);
    final hidden = ref.watch(mutedAuthorIdsProvider);
    final authors = account is SignedIn
        ? account.muted.where((a) => hidden.contains(a.id)).toList()
        : const <Author>[];
    return SubPage(
      title: t.muted.title,
      children: [
        if (authors.isEmpty)
          MessageView(title: t.muted.empty, hint: t.muted.emptyHint)
        else
          SectionCard(
            child: Column(
              children: [
                for (final a in authors)
                  ListTile(
                    leading: const Icon(AppIcons.muted),
                    title: Text(a.pseudonym),
                    trailing: TextButton(
                      onPressed: () async {
                        final current = ref.read(accountControllerProvider);
                        if (current is SignedIn) {
                          ref
                              .read(accountControllerProvider.notifier)
                              .showMuted(
                                current.muted
                                    .where((m) => m.id != a.id)
                                    .toList(),
                              );
                        }
                        await submitContribution(
                          context,
                          ContributionKind.unmute,
                          payload: {'id': a.id},
                          sentText: t.muted.unmuted(name: a.pseudonym),
                        );
                      },
                      child: Text(t.muted.unmute),
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

/// The devices of the account: this one, the others, and the way to cut
/// one off.
class DevicesScreen extends ConsumerWidget {
  const new({super.key});

  Future<void> _revoke(
    BuildContext context,
    WidgetRef ref,
    Device device,
  ) async {
    final t = context.t;
    final messenger = ScaffoldMessenger.maybeOf(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(t.devices.revokeTitle),
        content: Text(t.devices.revokeBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(t.common.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(t.devices.revoke),
          ),
        ],
      ),
    );
    if (!(ok ?? false) || !context.mounted) return;
    // The container, not the page's ref: the user may leave before the
    // answer, which must still refresh the list and say the result.
    final container = ProviderScope.containerOf(context, listen: false);
    try {
      await container.read(accountServiceProvider).revokeDevice(device.id);
    } on Object catch (e) {
      _log.info('device not revoked: $e');
      showMessage(messenger, t.common.offline);
      return;
    }
    container.invalidate(accountDevicesProvider);
    showMessage(messenger, t.devices.revoked);
  }

  Future<void> _signOutOthers(BuildContext context, WidgetRef ref) async {
    final t = context.t;
    final messenger = ScaffoldMessenger.maybeOf(context);
    final container = ProviderScope.containerOf(context, listen: false);
    final int n;
    try {
      n = await container.read(accountServiceProvider).signOutElsewhere();
    } on Object catch (e) {
      _log.info('other sessions not closed: $e');
      showMessage(messenger, t.common.offline);
      return;
    }
    container.invalidate(accountDevicesProvider);
    showMessage(messenger, t.devices.signedOutOthers(n: n));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.t;
    final theme = Theme.of(context);
    final locale = t.$meta.locale.languageCode;
    final now =
        ref.watch(minuteClockProvider).value ?? ref.read(clockProvider)();
    final devices = ref.watch(accountDevicesProvider);
    return SubPage(
      title: t.devices.title,
      subtitle: t.devices.intro,
      children: [
        switch (devices) {
          AsyncData(:final value) => SectionCard(
            child: Column(
              children: [
                for (final d in value)
                  ListTile(
                    leading: Icon(
                      AppIcons.device,
                      color: d.current ? theme.colorScheme.primary : null,
                    ),
                    title: Text(
                      d.current ? t.devices.thisDevice : t.devices.other,
                    ),
                    subtitle: Text(
                      [
                        t.devices.added(
                          date: DateFormat.yMMMd(locale)
                              .format(d.createdAt.toLocal()),
                        ),
                        t.devices.lastUsed(when: t.ago(d.lastUsedAt, now)),
                      ].join('\n'),
                    ),
                    isThreeLine: true,
                    trailing: d.current
                        ? null
                        : TextButton(
                            onPressed: () => _revoke(context, ref, d),
                            child: Text(t.devices.revoke),
                          ),
                  ),
              ],
            ),
          ),
          AsyncError() => MessageView(
            mood: SceneMood.offline,
            title: t.devices.error,
            action: t.common.retry,
            onAction: () => ref.invalidate(accountDevicesProvider),
            compact: true,
          ),
          AsyncLoading() => const Column(
            children: [
              Skeleton(height: 72, radius: LunaTokens.radiusL),
              SizedBox(height: Space.s),
              Skeleton(height: 72, radius: LunaTokens.radiusL),
            ],
          ),
        },
        const SizedBox(height: Space.l),
        OutlinedButton.icon(
          onPressed: () => _signOutOthers(context, ref),
          icon: const Icon(AppIcons.signOut),
          label: Text(t.devices.signOutOthers),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(56),
          ),
        ),
      ],
    );
  }
}

/// Deleting the account, in two steps: what goes and what stays (the same
/// words as lunaway.net/account/delete), then a confirmation that cannot be
/// passed by accident.
class DeleteAccountScreen extends ConsumerStatefulWidget {
  const new({super.key});

  @override
  ConsumerState<DeleteAccountScreen> createState() =>
      _DeleteAccountScreenState();
}

class _DeleteAccountScreenState extends ConsumerState<DeleteAccountScreen> {
  bool _deleting = false;

  Future<void> _confirm() async {
    final t = context.t;
    final account = ref.read(accountControllerProvider);
    if (account is! SignedIn) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => _FinalConfirm(name: account.account.pseudonym),
    );
    if (!(ok ?? false) || !mounted) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    final router = GoRouter.of(context);
    // Read before the request: the user may leave the page meanwhile.
    final controller = ref.read(accountControllerProvider.notifier);
    final outbox = ref.read(outboxStoreProvider);
    setState(() => _deleting = true);
    try {
      await controller.delete();
      // Nothing of the account is sent any more; the account is gone even
      // if the queue cannot be emptied now (each entry then fails as made
      // for another account).
      try {
        await outbox.clear();
      } on Object catch (e) {
        _log.info('waiting contributions not cleared: $e');
      }
      showMessage(messenger, t.deletion.done);
      router.go(AppRoutes.profile);
    } on Object catch (e) {
      _log.info('account not deleted: $e');
      showMessage(messenger, t.deletion.failed);
    } finally {
      if (mounted) setState(() => _deleting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    Widget item(String text) => Padding(
      padding: const EdgeInsets.only(bottom: Space.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 3),
            child: Icon(AppIcons.close, size: 16, color: scheme.error),
          ),
          const SizedBox(width: Space.s),
          Expanded(child: Text(text, style: theme.textTheme.bodyLarge)),
        ],
      ),
    );
    return SubPage(
      title: t.deletion.title,
      subtitle: t.deletion.intro,
      children: [
        SectionCard(
          padding: const EdgeInsets.all(Space.l),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(t.deletion.goneTitle, style: theme.textTheme.titleMedium),
              const SizedBox(height: Space.s),
              item(t.deletion.gone.identity),
              item(t.deletion.gone.sessions),
              item(t.deletion.gone.lists),
              item(t.deletion.gone.photos),
              item(t.deletion.gone.pending),
            ],
          ),
        ),
        const SizedBox(height: Space.m),
        SectionCard(
          padding: const EdgeInsets.all(Space.l),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(t.deletion.keptTitle, style: theme.textTheme.titleMedium),
              const SizedBox(height: Space.s),
              Text(t.deletion.kept, style: theme.textTheme.bodyLarge),
            ],
          ),
        ),
        const SizedBox(height: Space.m),
        Text(t.deletion.backups, style: theme.textTheme.bodyMedium),
        const SizedBox(height: Space.xs),
        Text(t.deletion.device, style: theme.textTheme.bodyMedium),
        const SizedBox(height: Space.m),
        Text(t.deletion.web, style: theme.textTheme.bodyMedium),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => ref
                .read(externalActionsProvider)
                .openUrl(
                  AppConfig.sitePage(
                    t.$meta.locale.languageCode,
                    'account/delete',
                  ),
                ),
            icon: const Icon(AppIcons.openExternal, size: 18),
            label: Text(t.deletion.webLink),
          ),
        ),
        const SizedBox(height: Space.xl),
        FilledButton(
          onPressed:
              _deleting || ref.watch(accountControllerProvider) is! SignedIn
              ? null
              : _confirm,
          style: FilledButton.styleFrom(
            backgroundColor: scheme.error,
            foregroundColor: scheme.onError,
            minimumSize: const Size.fromHeight(56),
          ).copyWith(side: focusRingIn(scheme.onError)),
          child: _deleting
              ? SizedBox.square(
                  dimension: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    color: scheme.onError,
                  ),
                )
              : Text(t.common.next),
        ),
      ],
    );
  }
}

class _FinalConfirm extends StatefulWidget {
  const new({required this.name});

  final String name;

  @override
  State<_FinalConfirm> createState() => _FinalConfirmState();
}

class _FinalConfirmState extends State<_FinalConfirm> {
  bool _understood = false;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final scheme = Theme.of(context).colorScheme;
    return AlertDialog(
      icon: Icon(AppIcons.warning, color: scheme.error, size: 36),
      scrollable: true,
      title: Text(t.deletion.confirmTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(t.deletion.confirmBody(name: widget.name)),
          const SizedBox(height: Space.m),
          CheckboxListTile(
            value: _understood,
            contentPadding: EdgeInsets.zero,
            onChanged: (v) => setState(() => _understood = v ?? false),
            title: Text(t.deletion.confirmCheck),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(t.common.cancel),
        ),
        FilledButton(
          onPressed: _understood ? () => Navigator.of(context).pop(true) : null,
          style: FilledButton.styleFrom(
            backgroundColor: scheme.error,
            foregroundColor: scheme.onError,
          ).copyWith(side: focusRingIn(scheme.onError)),
          child: Text(t.deletion.confirm),
        ),
      ],
    );
  }
}
