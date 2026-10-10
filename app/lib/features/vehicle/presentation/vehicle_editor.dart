import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lunaway/features/navigation/application/navigation_providers.dart';
import 'package:lunaway/features/navigation/domain/route_settings.dart';
import 'package:lunaway/features/navigation/presentation/navigation_texts.dart';
import 'package:lunaway/features/profile/application/settings_controller.dart';
import 'package:lunaway/features/vehicle/application/vehicle_providers.dart';
import 'package:lunaway/features/vehicle/domain/vehicle.dart';
import 'package:lunaway/features/vehicle/presentation/vehicle_silhouette.dart';
import 'package:lunaway/i18n/strings.g.dart';
import 'package:lunaway/shared/labels.dart';
import 'package:lunaway/shared/messages.dart';
import 'package:lunaway/shared/text_measure.dart';
import 'package:lunaway/shared/theme/app_icons.dart';
import 'package:lunaway/shared/theme/motion.dart';
import 'package:lunaway/shared/theme/phosphor_glyphs.dart';
import 'package:lunaway/shared/theme/tokens.dart';
import 'package:lunaway/shared/widgets/app_form.dart';
import 'package:lunaway/shared/widgets/busy_button.dart';
import 'package:lunaway/shared/widgets/form_sheet.dart';
import 'package:lunaway/shared/widgets/segmented.dart';

/// Opens the vehicle editor; returns the saved vehicle, or null when the
/// user left without saving.
Future<Vehicle?> showVehicleEditor(BuildContext context) => showFormSheet<Vehicle>(
  context,
  builder: (context, scroll) => VehicleEditor(scrollController: scroll),
);

/// The user's vehicle: its type, what it tows and its size. Every dimension
/// is optional; picking a type fills in typical values to correct.
class VehicleEditor extends ConsumerStatefulWidget {
  const new({this.scrollController, super.key});

  final ScrollController? scrollController;

  @override
  ConsumerState<VehicleEditor> createState() => _VehicleEditorState();
}

/// A size of the vehicle: its controller's key, the decimals it is typed
/// with, and the values it accepts.
typedef _Size = ({String key, int digits, ({double min, double max}) range});

const _Size _height = (key: 'height', digits: 2, range: Vehicle.heightRange);
const _Size _width = (key: 'width', digits: 2, range: Vehicle.widthRange);
const _Size _length = (key: 'length', digits: 1, range: Vehicle.lengthRange);
const _Size _weight = (key: 'weight', digits: 1, range: Vehicle.weightRange);
const _Size _consumption = (key: 'consumption', digits: 1, range: Vehicle.consumptionRange);

class _VehicleEditorState extends ConsumerState<VehicleEditor> {
  late Vehicle _draft = ref.read(vehicleProvider).value ?? Vehicle.typical(VehicleType.campervan);
  late final Map<String, TextEditingController> _fields = {
    for (final (size, value) in [
      (_height, _draft.heightM),
      (_width, _draft.widthM),
      (_length, _draft.lengthM),
      (_weight, _draft.weightT),
      (_consumption, _draft.consumptionL100),
    ])
      size.key: TextEditingController(
        text: value == null ? '' : formatDecimal(context, value, digits: size.digits),
      ),
  };

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
      void retype(_Size size, double old, double next) {
        final field = _fields[size.key]!;
        final current = parseDecimal(field.text);
        if (current == null || (current - old).abs() < 0.001) {
          field.text = formatDecimal(context, next, digits: size.digits);
        }
      }

      retype(_height, previous.heightM, type.heightM);
      retype(_width, previous.widthM, type.widthM);
      retype(_length, previous.lengthM, type.lengthM);
      retype(_weight, previous.weightT, type.weightT);
    });
  }

  double? _value(_Size size) => parseDecimal(_fields[size.key]!.text);

  /// Stores the vehicle; the form has checked every size. A failure leaves
  /// the sheet open with what was typed, and a way to try again.
  Future<void> _save() async {
    final vehicle = _draft.copyWith(
      heightM: () => _value(_height),
      widthM: () => _value(_width),
      lengthM: () => _value(_length),
      weightT: () => _value(_weight),
      consumptionL100: () => _value(_consumption),
    );
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.maybeOf(context);
    final saved = context.t.vehicle.saved;
    await ref.read(vehicleRepositoryProvider).save(vehicle);
    await ref.read(settingsProvider.notifier).vehicleDescribed(vehicle);
    Haptics.confirm();
    navigator.pop(vehicle);
    showMessage(messenger, saved);
  }

  Future<void> _clear() async {
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.maybeOf(context);
    final failed = context.t.common.saveFailed;
    try {
      await ref.read(vehicleRepositoryProvider).clear();
      await ref.read(settingsProvider.notifier).vehicleForgotten();
    } on Object {
      showMessage(messenger, failed);
      return;
    }
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
    Widget heading(String text, [String? hint]) => Padding(
      padding: const EdgeInsets.only(top: Space.xl, bottom: Space.m),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(header: true, child: Text(text, style: theme.textTheme.titleLarge)),
          if (hint != null) ...[
            const SizedBox(height: Space.xs),
            Text(hint, style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant)),
          ],
        ],
      ),
    );
    Widget field(_Size size, String label, String unit, IconData icon) => Padding(
      padding: const EdgeInsets.only(bottom: Space.m),
      child: LunaTextField(
        controller: _fields[size.key]!,
        label: label,
        kind: FieldKind.decimal,
        unit: unit,
        icon: icon,
        validator: decimalCheck(context, range: size.range, unit: unit, digits: size.digits),
      ),
    );

    return LunaForm(
      onSubmit: _save,
      child: FormSheetFrame(
        title: t.vehicle.title,
        subtitle: t.vehicle.why,
        scrollController: widget.scrollController,
        footnote: Text(t.vehicle.navigationLater),
        action: SubmitButton(
          label: t.vehicle.save,
          secondary: existing
              ? BusyButton(onPressed: _clear, look: BusyLook.outlined, label: Text(t.vehicle.clear))
              : null,
        ),
        children: [
          heading(t.vehicle.type),
          _TypeGrid(selected: _draft.type, towing: _draft.towing, onPick: _pickType),
          heading(t.vehicle.towingTitle),
          LunaSegmented<Towing>(
            segments: [for (final w in Towing.values) Segment(value: w, label: t.towing(w))],
            selected: _draft.towing,
            onChanged: (w) => setState(() => _draft = _draft.copyWith(towing: w)),
          ),
          heading(t.vehicle.size, t.vehicle.sizeHint),
          field(_height, t.vehicle.height, 'm', AppIcons.height),
          field(_width, t.vehicle.width, 'm', AppIcons.width),
          field(_length, t.vehicle.length, 'm', AppIcons.length),
          field(_weight, t.vehicle.weight, 't', AppIcons.weight),
          heading(t.vehicle.cruiseTitle, t.vehicle.cruiseHint),
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
            onChanged: (kmh) => setState(() => _draft = _draft.copyWith(cruiseSpeedKph: () => kmh)),
            mouseCursor: WidgetStateMouseCursor.clickable,
            dropdownMenuItemMouseCursor: WidgetStateMouseCursor.clickable,
          ),
          heading(t.vehicle.fuelTitle, t.vehicle.fuelHint),
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
            _consumption,
            t.vehicle.consumption,
            t.vehicle.consumptionUnit,
            PhosphorRegular.gasPump,
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(t.vehicle.lpgHeating, style: theme.textTheme.bodyLarge),
            subtitle: Text(t.vehicle.lpgHeatingHint),
            value: _draft.lpgHeating,
            onChanged: (on) => setState(() => _draft = _draft.copyWith(lpgHeating: on)),
          ),
        ],
      ),
    );
  }
}

/// The types side by side, as many to a row as their names allow at the
/// reader's text size, each row as tall as its tallest card.
class _TypeGrid extends StatelessWidget {
  const new({required this.selected, required this.towing, required this.onPick});

  final VehicleType selected;
  final Towing towing;
  final ValueChanged<VehicleType> onPick;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final theme = Theme.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        // Columns by the room the labels need, measured at the reader's
        // text size: fewer, wider cards rather than "Kastenwagen" or
        // "Teilintegriert" cut in two, in any language and on any width.
        final label = widestWord(
          [for (final type in VehicleType.values) t.vehicleType(type)],
          theme.textTheme.labelLarge,
          MediaQuery.textScalerOf(context),
        );
        final card = math.max(label, _TypeCard.silhouetteWidth) + _TypeCard.inset * 2;
        double width(int columns) => (constraints.maxWidth - Space.s * (columns - 1)) / columns;
        final columns = [6, 3, 2].firstWhere((c) => width(c) >= card, orElse: () => 1);
        const types = VehicleType.values;
        return Column(
          children: [
            for (var row = 0; row < types.length; row += columns) ...[
              if (row > 0) const SizedBox(height: Space.s),
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var i = row; i < row + columns; i++) ...[
                      if (i > row) const SizedBox(width: Space.s),
                      Expanded(
                        child: i < types.length
                            ? _TypeCard(
                                type: types[i],
                                towing: towing,
                                selected: selected == types[i],
                                onTap: () => onPick(types[i]),
                              )
                            : const SizedBox.shrink(),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ],
        );
      },
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

  /// The room on either side of the label.
  static const double inset = Space.s;

  /// The width the drawing of the vehicle takes.
  static const double silhouetteWidth = 76;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    // What a car covers, said under its name: the word alone reads as a
    // small car only.
    final hint = type == VehicleType.car ? t.vehicle.carHint : null;
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
            padding: const EdgeInsets.fromLTRB(inset, Space.m, inset, Space.m),
            child: Column(
              children: [
                VehicleSilhouette(
                  type,
                  towing: towing,
                  color: selected ? scheme.onPrimaryContainer : scheme.onSurface,
                  width: silhouetteWidth,
                ),
                const SizedBox(height: Space.s),
                Text(
                  t.vehicleType(type),
                  textAlign: TextAlign.center,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: selected ? scheme.onPrimaryContainer : scheme.onSurface,
                  ),
                ),
                if (hint != null)
                  Text(
                    hint,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: selected ? scheme.onPrimaryContainer : scheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
