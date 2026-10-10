import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lunaway/features/profile/application/settings_controller.dart';
import 'package:lunaway/features/vehicle/application/vehicle_providers.dart';
import 'package:lunaway/features/vehicle/domain/vehicle.dart';
import 'package:lunaway/i18n/strings.g.dart';
import 'package:lunaway/shared/theme/app_icons.dart';
import 'package:lunaway/shared/theme/motion.dart';
import 'package:lunaway/shared/theme/tokens.dart';
import 'package:lunaway/shared/widgets/app_form.dart';
import 'package:lunaway/shared/widgets/busy_button.dart';
import 'package:lunaway/shared/widgets/modal_sheet.dart';

/// Opens the short entry of the vehicle's height, for "my vehicle fits"
/// used before any vehicle was described; returns the saved vehicle, or
/// null when the user left without saving.
Future<Vehicle?> showVehicleHeightSheet(BuildContext context) => showSheet<Vehicle>(
  context,
  // Above the dock and the panels: the shell holds the branches.
  useRootNavigator: true,
  isScrollControlled: true,
  useSafeArea: true,
  builder: (context) => Padding(
    // The keyboard pushes the sheet up rather than covering its button.
    padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
    child: SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(Space.xxl, 0, Space.xxl, Space.xl),
      child: VehicleHeightEntry(
        heading: true,
        onSaved: (vehicle) {
          // The sheet may have been closed while the height was stored.
          if (context.mounted) Navigator.of(context).pop(vehicle);
        },
      ),
    ),
  ),
);

/// The height of the vehicle, and its total weight if the user wants, in
/// two fields and one button: what "my vehicle fits" needs, without the
/// full editor. Saving keeps whatever else was described of the vehicle;
/// without one, it stores a campervan with only these figures, never a
/// typical width or length the user did not give.
class VehicleHeightEntry extends ConsumerStatefulWidget {
  const new({required this.onSaved, this.heading = false, super.key});

  /// Called once the vehicle is stored.
  final ValueChanged<Vehicle> onSaved;

  /// With its own title and explanation, as a sheet; without, inside a card
  /// that already says what it is for.
  final bool heading;

  @override
  ConsumerState<VehicleHeightEntry> createState() => _VehicleHeightEntryState();
}

class _VehicleHeightEntryState extends ConsumerState<VehicleHeightEntry> {
  late final _height = TextEditingController(
    text: _format(ref.read(vehicleProvider).value?.heightM, 2),
  );
  late final _weight = TextEditingController(
    text: _format(ref.read(vehicleProvider).value?.weightT, 1),
  );

  String _format(double? v, int digits) =>
      v == null ? '' : formatDecimal(context, v, digits: digits);

  @override
  void dispose() {
    _height.dispose();
    _weight.dispose();
    super.dispose();
  }

  /// Stores the height (the form has checked it); a failure keeps the
  /// figures typed, with a way to try again.
  Future<void> _save() async {
    final height = parseDecimal(_height.text);
    if (height == null) return;
    final weight = parseDecimal(_weight.text);
    final existing = ref.read(vehicleProvider).value;
    final vehicle =
        existing?.copyWith(
          heightM: () => height,
          // An empty weight leaves the one already described.
          weightT: weight == null ? null : () => weight,
        ) ??
        Vehicle(type: VehicleType.campervan, heightM: height, weightT: weight);
    // Read before the write: once the height is stored, the filters' card
    // may already have swapped this entry for its switch, and the filter
    // must still turn on.
    final onSaved = widget.onSaved;
    final settings = ref.read(settingsProvider.notifier);
    await ref.read(vehicleRepositoryProvider).save(vehicle);
    // Inside the form's guard of a second tap: the sheet closes only after.
    await settings.vehicleDescribed(vehicle);
    Haptics.confirm();
    onSaved(vehicle);
  }

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return LunaForm(
      onSubmit: _save,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (widget.heading) ...[
            Text(t.vehicleHeight.title, style: theme.textTheme.headlineSmall),
            const SizedBox(height: Space.s),
            Text(
              t.vehicleHeight.why,
              style: theme.textTheme.bodyLarge?.copyWith(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: Space.xl),
          ],
          LunaTextField(
            controller: _height,
            label: t.vehicle.height,
            kind: FieldKind.decimal,
            unit: 'm',
            icon: AppIcons.height,
            validator: decimalCheck(
              context,
              range: Vehicle.heightRange,
              unit: 'm',
              required: t.vehicleHeight.needed,
            ),
          ),
          const SizedBox(height: Space.m),
          // "Optional" under the field rather than in its label: in the
          // label it cut the name of the weight in Spanish, Italian and
          // Dutch on a phone.
          LunaTextField(
            controller: _weight,
            label: t.vehicleHeight.weight,
            kind: FieldKind.decimal,
            unit: 't',
            icon: AppIcons.weight,
            helper: t.vehicleHeight.optional,
            textInputAction: TextInputAction.done,
            validator: decimalCheck(context, range: Vehicle.weightRange, unit: 't', digits: 1),
          ),
          const SizedBox(height: Space.l),
          // In a sheet the button is the one action; inside the filters it
          // stays second to the sheet's own button.
          SubmitButton(
            label: t.vehicleHeight.apply,
            look: widget.heading ? BusyLook.filled : BusyLook.tonal,
          ),
          const SizedBox(height: Space.s),
          Text(
            t.vehicleHeight.later,
            style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}
