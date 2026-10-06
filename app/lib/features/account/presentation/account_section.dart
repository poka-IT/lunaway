import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:logging/logging.dart';
import 'package:lunaway/core/router/routes.dart';
import 'package:lunaway/features/account/application/account_providers.dart';
import 'package:lunaway/features/account/domain/account.dart';
import 'package:lunaway/features/community/application/community_providers.dart';
import 'package:lunaway/features/community/domain/contribution.dart';
import 'package:lunaway/features/community/presentation/community_labels.dart';
import 'package:lunaway/features/places/data/graphql/graphql_client.dart';
import 'package:lunaway/i18n/strings.g.dart';
import 'package:lunaway/shared/labels.dart';
import 'package:lunaway/shared/messages.dart';
import 'package:lunaway/shared/theme/app_icons.dart';
import 'package:lunaway/shared/theme/tokens.dart';

final _log = Logger('account');

/// The account in the profile: none yet (and how one comes), or the
/// pseudonym, the trust level with what the next one needs, the recovery
/// card, the contributions and the account's pages.
class AccountSection extends ConsumerWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.t;
    final theme = Theme.of(context);
    final state = ref.watch(accountControllerProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: Space.xs, bottom: Space.s),
          child: Row(
            children: [
              Icon(
                AppIcons.account,
                size: 20,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: Space.s),
              Expanded(
                child: Semantics(
                  header: true,
                  child: Text(
                    t.account.title,
                    style: theme.textTheme.titleLarge,
                  ),
                ),
              ),
            ],
          ),
        ),
        switch (state) {
          AccountLoading() => const SizedBox(height: 120),
          NoAccount() => const _NoAccount(),
          SignedIn() => _SignedIn(state: state),
        },
      ],
    );
  }
}

BoxDecoration _card(BuildContext context) => BoxDecoration(
  color: Theme.of(context).colorScheme.surfaceContainerLow,
  borderRadius: BorderRadius.circular(LunaTokens.radiusXl),
);

class _NoAccount extends StatelessWidget {
  const new();

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(Space.l),
      decoration: _card(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(t.account.noneTitle, style: theme.textTheme.titleMedium),
          const SizedBox(height: Space.xs),
          Text(
            t.account.noneBody,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: Space.m),
          OutlinedButton.icon(
            onPressed: () => context.go(AppRoutes.recover),
            icon: const Icon(AppIcons.recoveryCard),
            label: Text(t.account.recover),
          ),
        ],
      ),
    );
  }
}

class _SignedIn extends ConsumerWidget {
  const new({required this.state});

  final SignedIn state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.t;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final account = state.account;
    final pending = ref.watch(ownOutboxEntriesProvider).length;
    final muted = ref.watch(mutedAuthorIdsProvider).length;
    final locale = t.$meta.locale.languageCode;
    final initial = account.pseudonym.characters.first.toUpperCase();
    Widget link(
      IconData icon,
      String label,
      String route, {
      String? trailing,
      Color? color,
    }) => ListTile(
      leading: Icon(icon, color: color),
      title: Text(label, style: color == null ? null : TextStyle(color: color)),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (trailing != null)
            Text(
              trailing,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          const SizedBox(width: Space.xs),
          const Icon(AppIcons.chevron),
        ],
      ),
      onTap: () => context.go(route),
    );
    return Container(
      decoration: _card(context),
      clipBehavior: Clip.antiAlias,
      child: Material(
        type: MaterialType.transparency,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                Space.l,
                Space.l,
                Space.s,
                Space.m,
              ),
              child: Row(
                children: [
                  ExcludeSemantics(
                    child: CircleAvatar(
                      radius: 26,
                      backgroundColor: scheme.primaryContainer,
                      child: Text(
                        initial,
                        style: theme.textTheme.headlineSmall?.copyWith(
                          color: scheme.onPrimaryContainer,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: Space.m),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          account.pseudonym,
                          style: theme.textTheme.titleLarge,
                        ),
                        Text(
                          t.account.memberSince(
                            date: DateFormat.yMMMM(locale)
                                .format(account.createdAt.toLocal()),
                          ),
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: t.account.editPseudonym,
                    icon: const Icon(AppIcons.rename),
                    onPressed: () =>
                        editPseudonym(context, ref, account.pseudonym),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            _Level(account: account),
            const Divider(height: 1),
            _RecoveryCard(made: state.recoveryCardAt),
            const Divider(height: 1),
            if (pending > 0)
              link(
                AppIcons.waiting,
                t.account.pending(n: pending),
                AppRoutes.contributions,
                color: scheme.primary,
              ),
            link(
              AppIcons.contributions,
              t.account.contributions,
              AppRoutes.contributions,
            ),
            link(
              AppIcons.muted,
              t.account.mutedAuthors,
              AppRoutes.muted,
              trailing: muted == 0 ? null : t.number(muted),
            ),
            link(AppIcons.device, t.account.devices, AppRoutes.devices),
            ListTile(
              leading: const Icon(AppIcons.signOut),
              title: Text(t.account.signOut),
              onTap: () =>
                  signOut(context, ref, hasCard: state.recoveryCardAt != null),
            ),
            link(
              AppIcons.delete,
              t.account.delete,
              AppRoutes.deleteAccount,
              color: scheme.error,
            ),
          ],
        ),
      ),
    );
  }
}

class _Level extends StatelessWidget {
  const new({required this.account});

  final Account account;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final next = account.nextLevel;
    return Padding(
      padding: const EdgeInsets.all(Space.l),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(AppIcons.trust, color: scheme.secondary),
          const SizedBox(width: Space.m),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  t.account.level(level: '${account.trustLevel}'),
                  style: theme.textTheme.titleMedium,
                ),
                const SizedBox(height: Space.xxs),
                Text(
                  t.levelOpens(account.trustLevel),
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: Space.s),
                if (next == null)
                  Text(
                    t.account.levelTop,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  )
                else ...[
                  Text(
                    t.account.nextLevel(level: '${next.level}'),
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  for (final r in next.missing)
                    Padding(
                      padding: const EdgeInsets.only(top: Space.xxs),
                      child: Text(
                        '· ${t.requirement(r)}',
                        style: theme.textTheme.bodyMedium,
                      ),
                    ),
                  if (next.instead != null)
                    Padding(
                      padding: const EdgeInsets.only(top: Space.xxs),
                      child: Text(
                        t.account.orInstead(
                          requirement: t.requirement(next.instead!),
                        ),
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RecoveryCard extends StatelessWidget {
  const new({required this.made});

  final DateTime? made;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final made = this.made;
    if (made == null) {
      return Container(
        margin: const EdgeInsets.all(Space.m),
        padding: const EdgeInsets.all(Space.l),
        decoration: BoxDecoration(
          color: scheme.primaryContainer,
          borderRadius: BorderRadius.circular(LunaTokens.radiusL),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(AppIcons.recoveryCard, color: scheme.onPrimaryContainer),
                const SizedBox(width: Space.m),
                Expanded(
                  child: Text(
                    t.account.recoveryNone,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: scheme.onPrimaryContainer,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: Space.m),
            FilledButton(
              onPressed: () => context.go(AppRoutes.recoveryCard),
              child: Text(t.account.recoveryCreate),
            ),
          ],
        ),
      );
    }
    return ListTile(
      leading: Icon(AppIcons.recoveryCard, color: scheme.secondary),
      title: Text(
        t.account.recoveryMade(
          date: DateFormat.yMMMd(t.$meta.locale.languageCode)
              .format(made.toLocal()),
        ),
      ),
      trailing: TextButton(
        onPressed: () => context.go(AppRoutes.recoveryCard),
        child: Text(t.account.recoveryRemake),
      ),
    );
  }
}

/// Changes the public pseudonym.
Future<void> editPseudonym(
  BuildContext context,
  WidgetRef ref,
  String current,
) async {
  final t = context.t;
  final messenger = ScaffoldMessenger.maybeOf(context);
  final controller = ref.read(accountControllerProvider.notifier);
  final next = await showDialog<String>(
    context: context,
    builder: (context) => _PseudonymDialog(initial: current),
  );
  if (next == null || next == current) return;
  try {
    await controller.rename(next);
    showMessage(messenger, t.account.pseudonymSaved);
  } on GraphQLResponseException catch (e) {
    _log.info('pseudonym refused: $e');
    showMessage(
      messenger,
      e.hasCode(GraphQLError.invalidInput)
          ? t.account.pseudonymRefused
          : t.common.failed,
    );
  } on Object catch (e) {
    _log.info('pseudonym not saved: $e');
    showMessage(messenger, t.common.offline);
  }
}

class _PseudonymDialog extends StatefulWidget {
  const new({required this.initial});

  final String initial;

  @override
  State<_PseudonymDialog> createState() => _PseudonymDialogState();
}

class _PseudonymDialogState extends State<_PseudonymDialog> {
  late final _text = TextEditingController(text: widget.initial);
  String? _error;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _save() {
    final cleaned = Pseudonym.clean(_text.text);
    if (cleaned == null) {
      setState(() => _error = context.t.account.pseudonymInvalid);
      return;
    }
    Navigator.of(context).pop(cleaned);
  }

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return AlertDialog(
      title: Text(t.account.pseudonymTitle),
      content: TextField(
        controller: _text,
        autofocus: true,
        maxLength: Pseudonym.maxLength,
        textCapitalization: TextCapitalization.words,
        onSubmitted: (_) => _save(),
        decoration: InputDecoration(
          helperText: t.account.pseudonymHint,
          errorText: _error,
          helperMaxLines: 3,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(t.common.cancel),
        ),
        FilledButton(onPressed: _save, child: Text(t.common.save)),
      ],
    );
  }
}

/// Signs this device out, after saying what it means; without a recovery
/// card made here, the warning says the account would be lost.
Future<void> signOut(
  BuildContext context,
  WidgetRef ref, {
  required bool hasCard,
}) async {
  final t = context.t;
  final messenger = ScaffoldMessenger.maybeOf(context);
  final controller = ref.read(accountControllerProvider.notifier);
  final outbox = ref.read(outboxStoreProvider);
  // What waits belongs to this account: it is dropped with it, and said so.
  final waiting = (await outbox.all())
      .where((e) => e.state != OutboxState.failed)
      .length;
  if (!context.mounted) return;
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) {
      final scheme = Theme.of(context).colorScheme;
      return AlertDialog(
        title: Text(t.account.signOutTitle),
        // Three warnings at large text sizes outgrow a small screen.
        scrollable: true,
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(t.account.signOutBody),
            if (!hasCard) ...[
              const SizedBox(height: Space.m),
              Text(
                t.account.signOutNoCard,
                style: TextStyle(color: scheme.error),
              ),
            ],
            if (waiting > 0) ...[
              const SizedBox(height: Space.m),
              Text(t.account.signOutPending(n: waiting)),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(t.common.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(t.account.signOut),
          ),
        ],
      );
    },
  );
  if (!(ok ?? false)) return;
  await controller.signOut();
  await outbox.clear();
  showMessage(messenger, t.account.signedOut);
}

/// The welcome after the first contribution made the account: its name,
/// what it is, and the recovery card. Shown once.
Future<void> showAccountWelcome(BuildContext context, Account account) {
  final t = context.t;
  final router = GoRouter.of(context);
  return showDialog<void>(
    context: context,
    builder: (context) {
      final theme = Theme.of(context);
      return AlertDialog(
        icon: const Icon(AppIcons.account, size: 36),
        title: Text(t.account.welcomeTitle),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                t.account.welcomeBody(name: account.pseudonym),
                style: theme.textTheme.bodyLarge,
              ),
              const SizedBox(height: Space.m),
              Text(
                t.account.welcomeFavorites,
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: Space.m),
              Text(t.account.welcomeCard, style: theme.textTheme.bodyMedium),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(t.common.later),
          ),
          FilledButton(
            onPressed: () {
              Navigator.of(context).pop();
              router.go(AppRoutes.recoveryCard);
            },
            child: Text(t.account.recoveryCreate),
          ),
        ],
      );
    },
  );
}
