import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lunaway/core/geo/geo.dart';
import 'package:lunaway/features/account/domain/account.dart';
import 'package:lunaway/features/community/application/community_providers.dart';
import 'package:lunaway/features/community/domain/contribution.dart';
import 'package:lunaway/features/community/presentation/community_labels.dart';
import 'package:lunaway/features/community/presentation/contribute.dart';
import 'package:lunaway/features/map/application/map_flow.dart';
import 'package:lunaway/features/poi/domain/poi.dart';
import 'package:lunaway/features/poi/presentation/poi_look.dart';
import 'package:lunaway/i18n/strings.g.dart';
import 'package:lunaway/shared/messages.dart';
import 'package:lunaway/shared/theme/app_icons.dart';
import 'package:lunaway/shared/theme/motion.dart';
import 'package:lunaway/shared/theme/tokens.dart';
import 'package:lunaway/shared/widgets/form_sheet.dart';

/// "A vending machine here?" under a chosen point: the three kinds a
/// traveller adds, one tap each. With the long press (or the add button)
/// that chose the point, a machine takes two gestures; its name, operator
/// and payment are for later.
class VendingQuickAdd extends ConsumerWidget {
  const new({required this.position, super.key});

  final LatLng position;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.t;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(t.poi.add.title, style: theme.textTheme.titleMedium),
        const SizedBox(height: Space.xxs),
        Text(
          t.poi.add.hint,
          style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
        ),
        const SizedBox(height: Space.s),
        Wrap(
          spacing: Space.s,
          runSpacing: Space.s,
          children: [
            for (final kind in PoiKind.addable)
              OutlinedButton.icon(
                onPressed: () => addVendingMachine(context, ref, position, kind),
                icon: Icon(PoiLook.kind(kind), color: PoiLook.tone(kind.category)),
                label: Text(_label(t, kind)),
                style: OutlinedButton.styleFrom(minimumSize: const Size(0, 48)),
              ),
          ],
        ),
      ],
    );
  }

  static String _label(Translations t, PoiKind kind) => switch (kind) {
    PoiKind.vendingPizza => t.poi.add.pizza,
    PoiKind.vendingBread => t.poi.add.bread,
    _ => t.poi.add.other,
  };
}

/// Adds a machine of [kind] at [position]: level 1 first, then the outbox,
/// which sends it at once when the network allows. A machine of the same
/// kind within 25 m is refused by the server: the user is then asked about
/// that one instead.
Future<void> addVendingMachine(
  BuildContext context,
  WidgetRef ref,
  LatLng position,
  PoiKind kind,
) async {
  final t = context.t;
  if (!await passesGate(
    context,
    ref,
    level: TrustLevels.addVendingMachine,
    title: t.poi.add.gate,
  )) {
    return;
  }
  if (!context.mounted) return;
  final messenger = ScaffoldMessenger.maybeOf(context);
  final container = ProviderScope.containerOf(context, listen: false);
  final runner = container.read(outboxRunnerProvider.notifier);
  final entry = await runner.enqueue(
    ContributionKind.addVendingMachine,
    payload: {
      'input': {'lat': position.lat, 'lon': position.lon, 'kind': kind.wire},
    },
  );
  if (entry == null) return;
  await runner.kick();
  final store = container.read(outboxStoreProvider);
  final after = await store.byId(entry.id);
  if (after == null) {
    Haptics.confirm();
    showMessage(messenger, t.poi.add.sent);
    // The point's marker gives way: the machine comes with the tiles.
    container.read(mapFlowProvider.notifier).select(null);
    return;
  }
  if (!after.failed) {
    showMessage(messenger, t.outbox.queued);
    return;
  }
  final existing = after.payload[OutboxError.existingIdKey];
  if (after.errorCode == OutboxError.duplicate && existing is String) {
    // Nothing to keep: the answer below replaces the refused machine.
    await store.discard(after.id);
    if (!context.mounted) return;
    await _askAboutExisting(context, existing);
    return;
  }
  showMessage(messenger, t.outbox.refused(reason: t.outboxError(after.errorCode)));
}

/// The machine already on the map: still there, or gone?
Future<void> _askAboutExisting(BuildContext context, String poiId) async {
  final t = context.t;
  final answer = await showFormSheet<bool>(
    context,
    tall: false,
    builder: (context, scroll) => FormSheetFrame(
      title: t.poi.add.duplicateTitle,
      scrollController: scroll,
      action: FilledButton.icon(
        onPressed: () => Navigator.of(context).pop(true),
        icon: const Icon(AppIcons.confirmed),
        label: Text(t.poi.add.duplicateThere),
      ),
      children: [
        Text(t.poi.add.duplicateBody, style: Theme.of(context).textTheme.bodyLarge),
        const SizedBox(height: Space.l),
        OutlinedButton.icon(
          onPressed: () => Navigator.of(context).pop(false),
          icon: const Icon(AppIcons.gone),
          label: Text(t.poi.add.duplicateGone),
          style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(56)),
        ),
      ],
    ),
  );
  if (answer == null || !context.mounted) return;
  await submitContribution(
    context,
    ContributionKind.confirmPoi,
    payload: {'poiId': poiId, 'stillThere': answer},
    sentText: answer ? t.poi.thanksThere : t.poi.thanksGone,
  );
}
