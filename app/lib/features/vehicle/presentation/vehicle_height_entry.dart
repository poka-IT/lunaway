import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:lunaway/features/vehicle/application/vehicle_providers.dart';
import 'package:lunaway/features/vehicle/domain/vehicle.dart';
import 'package:lunaway/features/vehicle/presentation/vehicle_editor.dart';
import 'package:lunaway/i18n/strings.g.dart';
import 'package:lunaway/shared/theme/app_icons.dart';
import 'package:lunaway/shared/theme/motion.dart';
import 'package:lunaway/shared/theme/tokens.dart';
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
        onSaved: (vehicle) => Navigator.of(context).pop(vehicle),
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
  final _form = GlobalKey<FormState>();
  late final _height = TextEditingController(
    text: _format(ref.read(vehicleProvider).value?.heightM, '0.00'),
  );
  late final _weight = TextEditingController(
    text: _format(ref.read(vehicleProvider).value?.weightT, '0.0'),
  );
  bool _saving = false;

  String _format(double? v, String pattern) =>
      v == null ? '' : NumberFormat(pattern, LocaleSettings.currentLocale.languageCode).format(v);

  @override
  void dispose() {
    _height.dispose();
    _weight.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving || !(_form.currentState?.validate() ?? false)) return;
    final height = VehicleEditor.parse(_height.text);
    if (height == null) return;
    final weight = VehicleEditor.parse(_weight.text);
    final existing = ref.read(vehicleProvider).value;
    final vehicle =
        existing?.copyWith(
          heightM: () => height,
          // An empty weight leaves the one already described.
          weightT: weight == null ? null : () => weight,
        ) ??
        Vehicle(type: VehicleType.campervan, heightM: height, weightT: weight);
    setState(() => _saving = true);
    await ref.read(vehicleRepositoryProvider).save(vehicle);
    if (!mounted) return;
    setState(() => _saving = false);
    Haptics.confirm();
    widget.onSaved(vehicle);
  }

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final locale = t.$meta.locale.languageCode;
    String? Function(String?) inRange(
      ({double min, double max}) range,
      String unit, {
      required bool required,
    }) => (text) {
      if (text == null || text.trim().isEmpty) return required ? t.vehicleHeight.needed : null;
      final v = VehicleEditor.parse(text);
      if (v == null) return t.vehicle.notANumber;
      if (v < range.min || v > range.max) {
        return t.vehicle.outOfRange(
          min: NumberFormat('0.0#', locale).format(range.min),
          max: NumberFormat('0.0#', locale).format(range.max),
          unit: unit,
        );
      }
      return null;
    };

    Widget field(
      TextEditingController controller,
      String label,
      String unit,
      IconData icon,
      String? Function(String?) check, {
      required TextInputAction action,
    }) => TextFormField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      textInputAction: action,
      inputFormatters: [FilteringTextInputFormatter.allow(RegExp('[0-9.,]'))],
      decoration: InputDecoration(labelText: label, suffixText: unit, prefixIcon: Icon(icon)),
      style: theme.textTheme.bodyLarge,
      validator: check,
      onFieldSubmitted: action == TextInputAction.done ? (_) => _save() : null,
    );

    return Form(
      key: _form,
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
          field(
            _height,
            t.vehicle.height,
            'm',
            AppIcons.height,
            inRange(Vehicle.heightRange, 'm', required: true),
            action: TextInputAction.next,
          ),
          const SizedBox(height: Space.m),
          field(
            _weight,
            t.vehicleHeight.weightOptional,
            't',
            AppIcons.weight,
            inRange(Vehicle.weightRange, 't', required: false),
            action: TextInputAction.done,
          ),
          const SizedBox(height: Space.l),
          // In a sheet the button is the one action; inside the filters it
          // stays second to the sheet's own button.
          if (widget.heading)
            FilledButton(onPressed: _saving ? null : _save, child: Text(t.vehicleHeight.apply))
          else
            FilledButton.tonal(
              onPressed: _saving ? null : _save,
              child: Text(t.vehicleHeight.apply),
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
