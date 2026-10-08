import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:lunaway/features/navigation/application/navigation_providers.dart';
import 'package:lunaway/features/navigation/domain/route_settings.dart';
import 'package:lunaway/features/navigation/presentation/navigation_texts.dart';
import 'package:lunaway/features/vehicle/application/vehicle_providers.dart';
import 'package:lunaway/features/vehicle/domain/vehicle.dart';
import 'package:lunaway/features/vehicle/presentation/vehicle_silhouette.dart';
import 'package:lunaway/i18n/strings.g.dart';
import 'package:lunaway/shared/labels.dart';
import 'package:lunaway/shared/theme/app_icons.dart';
import 'package:lunaway/shared/theme/motion.dart';
import 'package:lunaway/shared/theme/phosphor_glyphs.dart';
import 'package:lunaway/shared/theme/tokens.dart';
import 'package:lunaway/shared/widgets/modal_sheet.dart';
import 'package:lunaway/shared/widgets/segmented.dart';

/// Opens the vehicle editor; returns the saved vehicle, or null when the
/// user left without saving.
Future<Vehicle?> showVehicleEditor(BuildContext context) => showSheet<Vehicle>(
  context,
  // Above the dock and the panels: the shell holds the branches.
  useRootNavigator: true,
  isScrollControlled: true,
  useSafeArea: true,
  builder: (context) => DraggableScrollableSheet(
    expand: false,
    initialChildSize: 0.92,
    minChildSize: 0.5,
    maxChildSize: 0.96,
    builder: (context, scroll) => VehicleEditor(scrollController: scroll),
  ),
);

/// The user's vehicle: its type, what it tows and its size. Every dimension
/// is optional; picking a type fills in typical values to correct.
class VehicleEditor extends ConsumerStatefulWidget {
  const new({this.scrollController, super.key});

  final ScrollController? scrollController;

  /// A dimension typed with a point or a comma; null when empty or not a
  /// number. Shared with the short entry of the height.
  static double? parse(String text) {
    final cleaned = text.trim().replaceAll(',', '.').replaceAll(' ', '');
    if (cleaned.isEmpty) return null;
    return double.tryParse(cleaned);
  }

  @override
  ConsumerState<VehicleEditor> createState() => _VehicleEditorState();
}

class _VehicleEditorState extends ConsumerState<VehicleEditor> {
  final _form = GlobalKey<FormState>();
  late Vehicle _draft = ref.read(vehicleProvider).value ?? Vehicle.typical(VehicleType.campervan);
  late final Map<String, TextEditingController> _fields = {
    'height': TextEditingController(text: _format(_draft.heightM, 2)),
    'width': TextEditingController(text: _format(_draft.widthM, 2)),
    'length': TextEditingController(text: _format(_draft.lengthM, 1)),
    'weight': TextEditingController(text: _format(_draft.weightT, 1)),
    'consumption': TextEditingController(text: _format(_draft.consumptionL100, 1)),
  };

  String get _locale => context.t.$meta.locale.languageCode;

  String _format(double? v, int digits) => v == null
      ? ''
      : NumberFormat(
          digits == 2 ? '0.00' : '0.0',
          LocaleSettings.currentLocale.languageCode,
        ).format(v);

  @override
  void dispose() {
    for (final c in _fields.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _pickType(VehicleType type) {
    // A new type brings its typical size, unless the user typed their own.
    final previous = _draft.type;
    setState(() {
      _draft = _draft.copyWith(type: type);
      void retype(String key, double old, double next, int digits) {
        final current = VehicleEditor.parse(_fields[key]!.text);
        if (current == null || (current - old).abs() < 0.001) {
          _fields[key]!.text = NumberFormat(digits == 2 ? '0.00' : '0.0', _locale).format(next);
        }
      }

      retype('height', previous.heightM, type.heightM, 2);
      retype('width', previous.widthM, type.widthM, 2);
      retype('length', previous.lengthM, type.lengthM, 1);
      retype('weight', previous.weightT, type.weightT, 1);
    });
  }

  Future<void> _save() async {
    if (!(_form.currentState?.validate() ?? false)) return;
    final vehicle = _draft.copyWith(
      heightM: () => VehicleEditor.parse(_fields['height']!.text),
      widthM: () => VehicleEditor.parse(_fields['width']!.text),
      lengthM: () => VehicleEditor.parse(_fields['length']!.text),
      weightT: () => VehicleEditor.parse(_fields['weight']!.text),
      consumptionL100: () => VehicleEditor.parse(_fields['consumption']!.text),
    );
    final navigator = Navigator.of(context);
    await ref.read(vehicleRepositoryProvider).save(vehicle);
    Haptics.confirm();
    navigator.pop(vehicle);
  }

  Future<void> _clear() async {
    final navigator = Navigator.of(context);
    await ref.read(vehicleRepositoryProvider).clear();
    navigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final existing = ref.watch(vehicleProvider).value != null;
    // The speeds read in the units the guidance speaks; they are kept in
    // km/h, as the router takes them.
    final units = ref.watch(routeSettingsControllerProvider).value?.units ?? DistanceUnits.metric;
    String? Function(String?) inRange(({double min, double max}) range, String unit) => (text) {
      if (text == null || text.trim().isEmpty) return null;
      final v = VehicleEditor.parse(text);
      if (v == null) return t.vehicle.notANumber;
      if (v < range.min || v > range.max) {
        return t.vehicle.outOfRange(
          min: NumberFormat('0.0#', _locale).format(range.min),
          max: NumberFormat('0.0#', _locale).format(range.max),
          unit: unit,
        );
      }
      return null;
    };

    Widget field(
      String key,
      String label,
      String unit,
      IconData icon,
      String? Function(String?) check,
    ) => TextFormField(
      controller: _fields[key],
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [FilteringTextInputFormatter.allow(RegExp('[0-9.,]'))],
      decoration: InputDecoration(labelText: label, suffixText: unit, prefixIcon: Icon(icon)),
      style: theme.textTheme.bodyLarge,
      validator: check,
    );

    return Form(
      key: _form,
      child: Column(
        children: [
          Expanded(
            child: ListView(
              controller: widget.scrollController,
              padding: const EdgeInsets.fromLTRB(Space.xxl, 0, Space.xxl, Space.xxl),
              children: [
                Text(t.vehicle.title, style: theme.textTheme.headlineMedium),
                const SizedBox(height: Space.s),
                Text(
                  t.vehicle.why,
                  style: theme.textTheme.bodyLarge?.copyWith(color: scheme.onSurfaceVariant),
                ),
                const SizedBox(height: Space.xl),
                Text(t.vehicle.type, style: theme.textTheme.titleLarge),
                const SizedBox(height: Space.m),
                LayoutBuilder(
                  builder: (context, constraints) {
                    // Columns by the room the labels have at the reader's
                    // text size: a large text gets fewer, wider cards
                    // rather than "Teilintegriert" cut in two.
                    final room = constraints.maxWidth / MediaQuery.textScalerOf(context).scale(1);
                    final columns = room > 520 ? 5 : (room > 340 ? 3 : (room > 230 ? 2 : 1));
                    final w = (constraints.maxWidth - Space.s * (columns - 1)) / columns;
                    return Wrap(
                      spacing: Space.s,
                      runSpacing: Space.s,
                      children: [
                        for (final type in VehicleType.values)
                          SizedBox(
                            width: w,
                            child: _TypeCard(
                              type: type,
                              towing: _draft.towing,
                              selected: _draft.type == type,
                              onTap: () => _pickType(type),
                            ),
                          ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: Space.xl),
                Text(t.vehicle.towingTitle, style: theme.textTheme.titleLarge),
                const SizedBox(height: Space.m),
                LunaSegmented<Towing>(
                  segments: [for (final w in Towing.values) Segment(value: w, label: t.towing(w))],
                  selected: _draft.towing,
                  onChanged: (w) => setState(() => _draft = _draft.copyWith(towing: w)),
                ),
                const SizedBox(height: Space.xl),
                Text(t.vehicle.size, style: theme.textTheme.titleLarge),
                const SizedBox(height: Space.xs),
                Text(
                  t.vehicle.sizeHint,
                  style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
                ),
                const SizedBox(height: Space.m),
                field(
                  'height',
                  t.vehicle.height,
                  'm',
                  AppIcons.height,
                  inRange(Vehicle.heightRange, 'm'),
                ),
                const SizedBox(height: Space.m),
                field(
                  'width',
                  t.vehicle.width,
                  'm',
                  AppIcons.width,
                  inRange(Vehicle.widthRange, 'm'),
                ),
                const SizedBox(height: Space.m),
                field(
                  'length',
                  t.vehicle.length,
                  'm',
                  AppIcons.length,
                  inRange(Vehicle.lengthRange, 'm'),
                ),
                const SizedBox(height: Space.m),
                field(
                  'weight',
                  t.vehicle.weight,
                  't',
                  AppIcons.weight,
                  inRange(Vehicle.weightRange, 't'),
                ),
                const SizedBox(height: Space.xl),
                Text(t.vehicle.cruiseTitle, style: theme.textTheme.titleLarge),
                const SizedBox(height: Space.xs),
                Text(
                  t.vehicle.cruiseHint,
                  style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
                ),
                const SizedBox(height: Space.m),
                DropdownButtonFormField<int?>(
                  initialValue: _draft.cruiseSpeedKph,
                  decoration: InputDecoration(
                    labelText: t.vehicle.cruiseTitle,
                    prefixIcon: const Icon(AppIcons.hours),
                  ),
                  items: [
                    DropdownMenuItem(child: Text(t.vehicle.cruiseNone)),
                    for (final kmh in Vehicle.cruiseSpeeds)
                      DropdownMenuItem(value: kmh, child: Text(t.speedLimit(kmh, units))),
                  ],
                  onChanged: (kmh) =>
                      setState(() => _draft = _draft.copyWith(cruiseSpeedKph: () => kmh)),
                  mouseCursor: WidgetStateMouseCursor.clickable,
                  dropdownMenuItemMouseCursor: WidgetStateMouseCursor.clickable,
                ),
                const SizedBox(height: Space.xl),
                Text(t.vehicle.fuelTitle, style: theme.textTheme.titleLarge),
                const SizedBox(height: Space.xs),
                Text(
                  t.vehicle.fuelHint,
                  style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
                ),
                const SizedBox(height: Space.m),
                Wrap(
                  spacing: Space.s,
                  runSpacing: Space.s,
                  children: [
                    for (final fuel in FuelType.values)
                      ChoiceChip(
                        mouseCursor: WidgetStateMouseCursor.clickable,
                        label: Text(t.fuelType(fuel)),
                        selected: _draft.fuel == fuel,
                        // A second tap leaves the fuel unsaid.
                        onSelected: (on) =>
                            setState(() => _draft = _draft.copyWith(fuel: () => on ? fuel : null)),
                      ),
                  ],
                ),
                const SizedBox(height: Space.m),
                field(
                  'consumption',
                  t.vehicle.consumption,
                  t.vehicle.consumptionUnit,
                  _consumptionIcon,
                  inRange(Vehicle.consumptionRange, t.vehicle.consumptionUnit),
                ),
                const SizedBox(height: Space.s),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(t.vehicle.lpgHeating, style: theme.textTheme.bodyLarge),
                  subtitle: Text(t.vehicle.lpgHeatingHint),
                  value: _draft.lpgHeating,
                  onChanged: (on) => setState(() => _draft = _draft.copyWith(lpgHeating: on)),
                ),
                const SizedBox(height: Space.l),
                Text(
                  t.vehicle.navigationLater,
                  style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              color: scheme.surface,
              border: Border(top: BorderSide(color: scheme.outlineVariant)),
            ),
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(Space.xxl, Space.m, Space.xxl, Space.m),
                child: Row(
                  children: [
                    if (existing) ...[
                      Expanded(
                        child: OutlinedButton(onPressed: _clear, child: Text(t.vehicle.clear)),
                      ),
                      const SizedBox(width: Space.m),
                    ],
                    Expanded(
                      flex: 2,
                      child: FilledButton(onPressed: _save, child: Text(t.vehicle.save)),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TypeCard extends StatelessWidget {
  const new({
    required this.type,
    required this.towing,
    required this.selected,
    required this.onTap,
  });

  final VehicleType type;
  final Towing towing;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Semantics(
      selected: selected,
      button: true,
      inMutuallyExclusiveGroup: true,
      child: Material(
        color: selected ? scheme.primaryContainer : scheme.surfaceContainerLow,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(LunaTokens.radiusL),
          side: BorderSide(color: selected ? scheme.primary : Colors.transparent, width: 1.5),
        ),
        child: InkWell(
          mouseCursor: WidgetStateMouseCursor.clickable,
          customBorder: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(LunaTokens.radiusL),
          ),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(Space.s, Space.m, Space.s, Space.m),
            child: Column(
              children: [
                VehicleSilhouette(type, towing: towing, color: scheme.onSurface, width: 76),
                const SizedBox(height: Space.s),
                Text(
                  context.t.vehicleType(type),
                  textAlign: TextAlign.center,
                  style: theme.textTheme.labelLarge,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The icon of the consumption field.
const IconData _consumptionIcon = PhosphorRegular.gasPump;
