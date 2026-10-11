import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:logging/logging.dart';
import 'package:lunaway/core/router/routes.dart';
import 'package:lunaway/features/account/application/account_providers.dart';
import 'package:lunaway/features/account/application/account_switch.dart';
import 'package:lunaway/features/account/data/account_service.dart';
import 'package:lunaway/features/account/domain/account.dart';
import 'package:lunaway/features/account/presentation/recovery_screens.dart';
import 'package:lunaway/features/community/application/community_providers.dart';
import 'package:lunaway/features/community/domain/contribution.dart';
import 'package:lunaway/features/places/data/graphql/graphql_client.dart';
import 'package:lunaway/i18n/strings.g.dart';
import 'package:lunaway/shared/messages.dart';
import 'package:lunaway/shared/theme/app_icons.dart';
import 'package:lunaway/shared/theme/tokens.dart';
import 'package:lunaway/shared/widgets/busy_button.dart';
import 'package:lunaway/shared/widgets/modal_sheet.dart';

final _log = Logger('account');

/// How the sheet of an imported account ended.
enum ImportOutcome {
  /// The device's account went into the imported one, which the device
  /// now uses.
  merged,

  /// The imported account took the device's account's place.
  replaced,

  /// The user wants the recovery card of the account left before
  /// replacing it.
  card,

  /// Given up: the device keeps its account.
  cancelled,
}

/// What becomes of the two accounts once [imported] was opened beside the
/// device's: a sheet that names both, offers to merge the device's account
/// into the imported one, to replace it without merging (one step further,
/// with what that leaves behind and the recovery card of the account left),
/// or to give up. A merge or a replacement runs in the sheet, which ends
/// only by one of its buttons; a failed merge stays in it, with "Réessayer".
Future<void> chooseForImported(
  BuildContext context,
  WidgetRef ref,
  ImportedAccount imported,
) async {
  final t = context.t;
  final messenger = ScaffoldMessenger.maybeOf(context);
  final router = GoRouter.of(context);
  final navigator = Navigator.of(context);
  final controller = ref.read(accountControllerProvider.notifier);
  final start = ref.read(accountControllerProvider);
  if (start is! SignedIn) return;
  final current = start.account;
  final homeWins = await ref.read(accountSwitchProvider).importedHomeWins(imported);
  final outbox = await ref.read(outboxStoreProvider).all();
  final waiting = outbox.where((e) => e.state != OutboxState.failed).length;
  var replacing = false;
  for (;;) {
    if (!context.mounted) {
      await controller.cancelImport(imported);
      return;
    }
    final state = ref.read(accountControllerProvider);
    final hasCard = state is SignedIn && state.recoveryCardAt != null;
    final outcome = await showSheet<ImportOutcome>(
      context,
      isScrollControlled: true,
      dismissible: false,
      builder: (_) => ImportChoice(
        current: current,
        imported: imported,
        homeWins: homeWins,
        waiting: waiting,
        hasCard: hasCard,
        replacing: replacing,
      ),
    );
    switch (outcome) {
      case ImportOutcome.merged:
        showMessage(messenger, t.accountImport.merged(name: imported.account.pseudonym));
        router.go(AppRoutes.profile);
        return;
      case ImportOutcome.replaced:
        showMessage(messenger, t.accountImport.replaced(name: imported.account.pseudonym));
        router.go(AppRoutes.profile);
        return;
      case ImportOutcome.card:
        // The card of the account left, made while the device still holds
        // it; the choice comes back at the replacement once it is kept.
        await navigator.push(
          MaterialPageRoute<void>(builder: (_) => const RecoveryCardScreen(returns: true)),
        );
        replacing = true;
      case ImportOutcome.cancelled || null:
        await controller.cancelImport(imported);
        showMessage(messenger, t.accountImport.cancelled(name: current.pseudonym));
        router.go(AppRoutes.profile);
        return;
    }
  }
}

/// The sheet itself: the choice, then the replacement's own step.
class ImportChoice extends ConsumerStatefulWidget {
  const new({
    required this.current,
    required this.imported,
    required this.homeWins,
    required this.waiting,
    required this.hasCard,
    this.replacing = false,
    super.key,
  });

  /// The account the device holds.
  final Account current;
  final ImportedAccount imported;

  /// Both have a home, and the imported account's stays.
  final bool homeWins;

  /// Contributions waiting on the device.
  final int waiting;

  /// The device knows a recovery card of [current].
  final bool hasCard;

  /// Opens at the replacement's step.
  final bool replacing;

  @override
  ConsumerState<ImportChoice> createState() => _ImportChoiceState();
}

class _ImportChoiceState extends ConsumerState<ImportChoice> {
  late bool _replacing = widget.replacing;
  bool _busy = false;

  /// What the last attempt to merge or replace left to say, in place of
  /// the explanation of what fails.
  String? _failure;

  Future<void> _run(ImportOutcome outcome, Future<void> Function() action) async {
    final t = context.t;
    final navigator = Navigator.of(context);
    setState(() {
      _busy = true;
      _failure = null;
    });
    try {
      await action();
      if (mounted) navigator.pop(outcome);
    } on GraphQLRateLimitedException {
      _failed(t.recover.tooMany);
    } on GraphQLResponseException catch (e) {
      _log.info('the account import did not finish: ${e.errors.map((x) => x.code).join(',')}');
      _failed(
        e.hasCode(GraphQLError.rateLimited)
            ? t.recover.tooMany
            : e.transient
            ? t.accountImport.failed
            : t.accountImport.refused,
      );
    } on Object catch (e) {
      // Offline, a timeout, a lost answer: the server answers the same
      // merge again, whether it made it or not.
      _log.info('the account import did not finish: ${e.runtimeType}');
      _failed(t.accountImport.failed);
    }
  }

  void _failed(String text) {
    if (!mounted) return;
    setState(() {
      _busy = false;
      _failure = text;
    });
  }

  Future<void> _merge() => _run(
    ImportOutcome.merged,
    () => ref.read(accountControllerProvider.notifier).merge(widget.imported),
  );

  Future<void> _replace() => _run(
    ImportOutcome.replaced,
    () => ref.read(accountControllerProvider.notifier).replace(widget.imported),
  );

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final current = widget.current.pseudonym;
    final imported = widget.imported.account.pseudonym;
    Widget line(String text, {Color? color}) => Padding(
      padding: const EdgeInsets.only(bottom: Space.s),
      child: Text(text, style: theme.textTheme.bodyLarge?.copyWith(color: color)),
    );
    final failure = _failure;
    final choose = <Widget>[
      Semantics(
        header: true,
        child: Text(t.accountImport.choiceTitle, style: theme.textTheme.titleLarge),
      ),
      const SizedBox(height: Space.s),
      line(t.accountImport.choiceBody(current: current, imported: imported)),
      const SizedBox(height: Space.s),
      line(t.accountImport.mergeMoves(current: current, imported: imported)),
      line(t.accountImport.mergePublic(imported: imported)),
      if (widget.homeWins) line(t.accountImport.mergeHomeKept(imported: imported)),
      line(t.accountImport.mergeDuplicates(imported: imported)),
      line(t.accountImport.mergeDeletes(current: current)),
      if (failure != null) line(failure, color: scheme.error),
      const SizedBox(height: Space.m),
      BusyButton(
        onPressed: _busy ? null : _merge,
        busy: _busy,
        icon: const Icon(AppIcons.mergeAccounts),
        label: Text(failure == null ? t.accountImport.merge(imported: imported) : t.common.retry),
        style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(56)),
      ),
      const SizedBox(height: Space.s),
      TextButton(
        onPressed: _busy
            ? null
            : () => setState(() {
                _replacing = true;
                _failure = null;
              }),
        child: Text(t.accountImport.replace),
      ),
      TextButton(
        onPressed: _busy ? null : () => Navigator.of(context).pop(ImportOutcome.cancelled),
        child: Text(t.common.cancel),
      ),
    ];
    final replace = <Widget>[
      Semantics(
        header: true,
        child: Text(
          t.accountImport.replaceTitle(current: current, imported: imported),
          style: theme.textTheme.titleLarge,
        ),
      ),
      const SizedBox(height: Space.m),
      if (widget.hasCard)
        line(t.accountImport.replaceKeeps(current: current))
      else
        line(t.accountImport.replaceNoCard(current: current), color: scheme.error),
      line(t.accountImport.replaceLocal(imported: imported)),
      if (widget.waiting > 0) line(t.accountImport.replacePending(n: widget.waiting)),
      if (failure != null) line(failure, color: scheme.error),
      const SizedBox(height: Space.m),
      OutlinedButton.icon(
        onPressed: _busy ? null : () => Navigator.of(context).pop(ImportOutcome.card),
        icon: const Icon(AppIcons.recoveryCard),
        label: Text(t.accountImport.card(current: current)),
        style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(56)),
      ),
      const SizedBox(height: Space.s),
      BusyButton(
        onPressed: _busy ? null : _replace,
        busy: _busy,
        label: Text(t.accountImport.replaceConfirm),
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(56),
          backgroundColor: scheme.error,
          foregroundColor: scheme.onError,
        ),
      ),
      const SizedBox(height: Space.s),
      TextButton(
        onPressed: _busy
            ? null
            : () => setState(() {
                _replacing = false;
                _failure = null;
              }),
        child: Text(t.accountImport.back),
      ),
    ];
    return PopScope(
      // The system back gives up, as "Annuler" does; never while the
      // server is asked.
      canPop: !_busy,
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(Space.l, Space.s, Space.l, Space.l),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: _replacing ? replace : choose,
          ),
        ),
      ),
    );
  }
}
