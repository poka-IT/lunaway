import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lunaway/features/account/application/account_providers.dart';
import 'package:lunaway/features/community/application/community_providers.dart';
import 'package:lunaway/features/community/domain/contribution.dart';
import 'package:lunaway/features/community/presentation/community_labels.dart';
import 'package:lunaway/i18n/strings.g.dart';
import 'package:lunaway/shared/messages.dart';
import 'package:lunaway/shared/theme/app_icons.dart';
import 'package:lunaway/shared/theme/motion.dart';
import 'package:lunaway/shared/theme/tokens.dart';
import 'package:lunaway/shared/widgets/form_sheet.dart';

/// What became of a contribution the user just made.
enum Submitted {
  /// The server has it.
  sent,

  /// It waits in the outbox for the network.
  queued,

  /// The server refused it; the message said why.
  refused,
}

/// Queues a contribution, sends it at once when the network allows, and
/// says what happened in one message: sent, waiting for the network, or
/// refused with the reason. Offline, nothing is lost: the outbox keeps it.
///
/// [context] must outlive the call: a sheet passes its navigator's context,
/// since the sheet itself closes first.
Future<Submitted> submitContribution(
  BuildContext context,
  ContributionKind kind, {
  required Map<String, Object?> payload,
  String? placeId,
  String? fileId,
  String? sentText,
}) async {
  final t = context.t;
  final messenger = ScaffoldMessenger.maybeOf(context);
  final container = ProviderScope.containerOf(context, listen: false);
  final runner = container.read(outboxRunnerProvider.notifier);
  final entry = await runner.enqueue(
    kind,
    payload: payload,
    placeId: placeId,
    fileId: fileId,
  );
  if (entry == null) {
    // It only cancelled a contribution still waiting: nothing to send.
    showMessage(messenger, sentText ?? t.outbox.sent);
    return Submitted.sent;
  }
  await runner.kick();
  final after = await container.read(outboxStoreProvider).byId(entry.id);
  if (after == null) {
    Haptics.confirm();
    showMessage(messenger, sentText ?? t.outbox.sent);
    return Submitted.sent;
  }
  if (after.failed) {
    showMessage(
      messenger,
      t.outbox.refused(reason: t.outboxError(after.errorCode)),
    );
    return Submitted.refused;
  }
  showMessage(messenger, t.outbox.queued);
  return Submitted.queued;
}

/// Lets an action through when the account's level allows it; otherwise
/// says, before any form, which level opens it and how it comes. A device
/// without an account counts as level 0, where every account starts.
Future<bool> passesGate(
  BuildContext context,
  WidgetRef ref, {
  required int level,
  required String title,
}) async {
  final gate = ref.read(gateProvider(level));
  if (gate.allowed) return true;
  await showFormSheet<void>(
    context,
    tall: false,
    builder: (context, scroll) =>
        _GateSheet(title: title, gate: gate, scrollController: scroll),
  );
  return false;
}

class _GateSheet extends ConsumerWidget {
  const new({required this.title, required this.gate, this.scrollController});

  final String title;
  final Gate gate;
  final ScrollController? scrollController;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.t;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final hasAccount = ref.watch(accountControllerProvider) is SignedIn;
    final next = gate.next;
    final nextIsIt = next != null && next.level == gate.required;
    return FormSheetFrame(
      title: title,
      scrollController: scrollController,
      action: FilledButton(
        onPressed: () => Navigator.of(context).pop(),
        child: Text(t.common.ok),
      ),
      children: [
        Text(t.gate.why, style: theme.textTheme.bodyLarge),
        const SizedBox(height: Space.l),
        Container(
          padding: const EdgeInsets.all(Space.l),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(LunaTokens.radiusL),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                hasAccount
                    ? t.gate.yourLevel(level: '${gate.level}')
                    : t.gate.noAccount,
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox(height: Space.s),
              if (nextIsIt) ...[
                Text(
                  t.account.nextLevel(level: '${next.level}'),
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: Space.xs),
                for (final r in next.missing)
                  _Requirement(text: t.requirement(r)),
                if (next.instead != null)
                  _Requirement(
                    text: t.account.orInstead(
                      requirement: t.requirement(next.instead!),
                    ),
                  ),
              ] else
                Text(
                  t.gate.later(level: '${gate.required}'),
                  style: theme.textTheme.bodyMedium,
                ),
            ],
          ),
        ),
        const SizedBox(height: Space.l),
        Text(
          t.gate.meanwhile,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _Requirement extends StatelessWidget {
  const new({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(
              AppIcons.chevron,
              size: 16,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: Space.s),
          Expanded(child: Text(text, style: theme.textTheme.bodyMedium)),
        ],
      ),
    );
  }
}
