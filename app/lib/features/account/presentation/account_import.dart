import 'dart:async';

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
import 'package:lunaway/features/favorites/application/favorites_providers.dart';
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
  // The card's page covers the dock and the rail too: nothing navigates
  // away from the choice while it is open.
  final navigator = Navigator.of(context, rootNavigator: true);
  final controller = ref.read(accountControllerProvider.notifier);
  final switcher = ref.read(accountSwitchProvider);
  final outboxStore = ref.read(outboxStoreProvider);
  // Read now: an import ended with no one left to ask still holds them.
  final favorites = ref.read(favoritesSyncControllerProvider.notifier);
  final outboxRunner = ref.read(outboxRunnerProvider.notifier);
  // Kept across the sheet's openings: the card's detour closes it.
  final progress = ImportProgress();
  Future<void> giveUp() =>
      favorites.holding(() => outboxRunner.holding(() => _giveUp(controller, switcher, imported)));
  final start = ref.read(accountControllerProvider);
  if (start is! SignedIn) {
    await controller.cancelImport(imported);
    return;
  }
  final current = start.account;
  final homeWins = await switcher.importedHomeWins(imported);
  final outbox = await outboxStore.all();
  final waiting = outbox.where((e) => e.state != OutboxState.failed).length;
  var replacing = false;
  for (;;) {
    if (!context.mounted) {
      await giveUp();
      return;
    }
    final state = ref.read(accountControllerProvider);
    final hasCard = state is SignedIn && state.recoveryCardAt != null;
    final outcome = await showSheet<ImportOutcome>(
      context,
      // Over the whole window, the dock and the rail with it: nothing but
      // the sheet's own buttons ends the choice while the server is asked.
      useRootNavigator: true,
      useSafeArea: true,
      isScrollControlled: true,
      dismissible: false,
      builder: (_) => ImportChoice(
        current: current,
        imported: imported,
        homeWins: homeWins,
        waiting: waiting,
        hasCard: hasCard,
        replacing: replacing,
        progress: progress,
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
      case ImportOutcome.cancelled:
        // The sheet's "Annuler" closes it once nothing is uncertain.
        await controller.cancelImport(imported);
        showMessage(messenger, t.accountImport.cancelled(name: current.pseudonym));
        router.go(AppRoutes.profile);
        return;
      case null:
        // The sheet removed with the pages under it (an address typed in a
        // browser): nobody chose.
        await giveUp();
        return;
    }
  }
}

/// The import ends with no one left to ask (the page closed under the
/// sheet or the card's detour): a replacement under way is finished, a
/// merge that may have been made is finished when the server says it was,
/// else the device keeps its account. Unanswered, the import is given up
/// all the same: the device's key then says, at its next sign-in, where its
/// account went if it did.
Future<void> _giveUp(
  AccountController controller,
  AccountSwitch switcher,
  ImportedAccount imported,
) async {
  // What a choice still under way leaves decides.
  await switcher.quiet();
  // A merge made on the server, or a replacement begun, ends; giving it up
  // would detach the key of the only account the device can still open.
  bool committed() => switcher.left || switcher.landing != null;
  try {
    if (switcher.left) {
      await controller.replace(imported);
      return;
    }
    if (switcher.mayHaveMerged(imported) && await controller.settleImport(imported)) return;
  } on Object catch (e) {
    _log.info('the import did not end: ${e.runtimeType}');
    if (committed()) return;
  }
  await controller.cancelImport(imported);
}

/// What the attempts of an import learnt, kept across the sheet's openings.
final class ImportProgress {
  /// A merge was asked and its answer did not come: the server may have
  /// made it. Any other choice first asks whether it did, and finishes it
  /// if so: the device then holds the merged account, nothing is lost.
  bool uncertain = false;

  /// The server refused the merge for good: asked again, it refuses again.
  bool refused = false;

  /// A replacement detached the device's key from its account and failed
  /// after: only the replacement, tried again, can end.
  bool left = false;
}

/// The settling of an uncertain merge did not answer.
final class _Unsettled implements Exception {
  const new(this.cause);

  final Object cause;
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
    this.progress,
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

  /// What earlier openings of the sheet learnt; a sheet of its own when
  /// null.
  final ImportProgress? progress;

  @override
  ConsumerState<ImportChoice> createState() => _ImportChoiceState();
}

class _ImportChoiceState extends ConsumerState<ImportChoice> {
  late bool _replacing = widget.replacing;
  late final ImportProgress _progress = widget.progress ?? ImportProgress();
  bool _busy = false;

  /// What the last attempt to merge or replace left to say, in place of
  /// the explanation of what fails.
  String? _failure;

  /// Runs [action] in the sheet, which closes with [outcome] once it is
  /// done; a failure stays in the sheet, said in its words. A merge that
  /// may have been made is settled first ([ImportProgress.uncertain]).
  Future<void> _run(
    ImportOutcome outcome,
    Future<void> Function(AccountController controller) action,
  ) async {
    final t = context.t;
    final merging = outcome == ImportOutcome.merged;
    final navigator = Navigator.of(context);
    final controller = ref.read(accountControllerProvider.notifier);
    final favorites = ref.read(favoritesSyncControllerProvider.notifier);
    final outbox = ref.read(outboxRunnerProvider.notifier);
    final switcher = ref.read(accountSwitchProvider);
    final progress = _progress;
    // A replacement that failed: before the device left its account,
    // nothing changed; after, only the replacement can end.
    String replaceFailure() {
      if (!switcher.left) return t.accountImport.replaceFailed;
      progress.left = true;
      return t.accountImport.replaceUnfinished(current: widget.current.pseudonym);
    }

    setState(() {
      _busy = true;
      _failure = null;
    });
    Future<bool> run() async {
      // A merge asked again needs no settling: the server answers it the
      // same whether it made it or not.
      if (progress.uncertain && !merging) {
        final bool landed;
        try {
          landed = await controller.settleImport(widget.imported);
        } on Object catch (e) {
          throw _Unsettled(e);
        }
        if (landed) return true;
        progress.uncertain = false;
      }
      await action(controller);
      return false;
    }

    try {
      // While the device changes accounts, neither the favourites' sync nor
      // the outbox runs: under the account left, one would bring back the
      // lists it clears, the other send what the account taken must not.
      final switching = outcome != ImportOutcome.cancelled || progress.uncertain;
      final settled = switching ? await favorites.holding(() => outbox.holding(run)) : await run();
      if (mounted) navigator.pop(settled ? ImportOutcome.merged : outcome);
    } on _Unsettled catch (e) {
      _log.info('the merge is still unsettled: ${e.cause.runtimeType}');
      _failed(_onDevice(e.cause) ? t.accountImport.deviceFailed : t.accountImport.unsettled);
    } on MergeUnsettledException catch (e) {
      // Sent, and no answer: the server may have made it, and answers the
      // same when asked again. Or made, and the device could not keep it.
      _log.info('the merge did not end: ${e.cause.runtimeType}');
      progress.uncertain = true;
      _failed(_onDevice(e) ? t.accountImport.deviceFailed : t.accountImport.failed);
    } on GraphQLRateLimitedException {
      _failed(t.accountImport.tooMany);
    } on GraphQLResponseException catch (e) {
      _log.info('the account import did not finish: ${e.errors.map((x) => x.code).join(',')}');
      if (e.hasCode(GraphQLError.rateLimited)) {
        _failed(t.accountImport.tooMany);
      } else if (merging && !e.transient) {
        progress.refused = true;
        _failed(t.accountImport.refused);
      } else {
        _failed(merging ? t.accountImport.failed : replaceFailure());
      }
    } on Object catch (e) {
      // Offline before the merge left, or the replacement unanswered or
      // refused by the device's storage.
      _log.info('the account import did not finish: ${e.runtimeType}');
      _failed(merging ? t.accountImport.failed : replaceFailure());
    }
  }

  /// A merge the server made that the device's own storage could not keep:
  /// the network is not to blame.
  static bool _onDevice(Object error) => error is MergeUnsettledException && error.onDevice;

  void _failed(String text) {
    if (!mounted) return;
    setState(() {
      _busy = false;
      _failure = text;
    });
  }

  Future<void> _merge() =>
      _run(ImportOutcome.merged, (controller) => controller.merge(widget.imported));

  Future<void> _replace() =>
      _run(ImportOutcome.replaced, (controller) => controller.replace(widget.imported));

  /// Gives up; a merge that may have been made is settled first.
  Future<void> _cancel() => _run(ImportOutcome.cancelled, (_) async {});

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
    final left = _progress.left;
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
        onPressed: _busy || _progress.refused ? null : _merge,
        busy: _busy,
        icon: const Icon(AppIcons.mergeAccounts),
        label: Text(
          _progress.uncertain ? t.common.retry : t.accountImport.merge(imported: imported),
        ),
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
      TextButton(onPressed: _busy ? null : _cancel, child: Text(t.common.cancel)),
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
      // Once the device left its account, only the replacement can end:
      // no card of an account it left, no way back to a choice it made.
      if (!left) ...[
        OutlinedButton.icon(
          // After a merge that may have been made, the account left may be
          // gone: no card of it until the server says.
          onPressed: _busy || _progress.uncertain
              ? null
              : () => Navigator.of(context).pop(ImportOutcome.card),
          icon: const Icon(AppIcons.recoveryCard),
          label: Text(t.accountImport.card(current: current)),
          style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(56)),
        ),
        const SizedBox(height: Space.s),
      ],
      BusyButton(
        onPressed: _busy ? null : _replace,
        busy: _busy,
        label: Text(left ? t.common.retry : t.accountImport.replaceConfirm),
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(56),
          backgroundColor: scheme.error,
          foregroundColor: scheme.onError,
        ),
      ),
      if (!left) ...[
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
      ],
    ];
    return PopScope(
      // The system back gives up as "Annuler" does, through it: never while
      // the server is asked, after a merge that may have been made by
      // asking first, and never once the device left its account. The sheet
      // closes only with an outcome.
      canPop: false,
      onPopInvokedWithResult: (popped, _) {
        if (popped || _busy || left) return;
        // At the replacement's step, back to the choice, as "Retour".
        if (_replacing) {
          setState(() {
            _replacing = false;
            _failure = null;
          });
          return;
        }
        unawaited(_cancel());
      },
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
