import 'dart:async';

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:lunaway/core/geo/coordinate_format.dart';
import 'package:lunaway/core/geo/geo.dart';
import 'package:lunaway/features/account/application/account_providers.dart';
import 'package:lunaway/features/account/domain/account.dart';
import 'package:lunaway/features/community/application/community_providers.dart';
import 'package:lunaway/features/community/data/photo_prepare.dart';
import 'package:lunaway/features/community/domain/community.dart';
import 'package:lunaway/features/community/domain/contribution.dart';
import 'package:lunaway/features/community/presentation/contribute.dart';
import 'package:lunaway/features/community/presentation/photo_flow.dart';
import 'package:lunaway/features/community/presentation/place_placement.dart';
import 'package:lunaway/features/map/application/map_flow.dart';
import 'package:lunaway/features/map/application/map_state.dart';
import 'package:lunaway/features/places/domain/place.dart';
import 'package:lunaway/features/places/domain/taxonomy.dart';
import 'package:lunaway/i18n/strings.g.dart';
import 'package:lunaway/shared/labels.dart';
import 'package:lunaway/shared/messages.dart';
import 'package:lunaway/shared/theme/app_icons.dart';
import 'package:lunaway/shared/theme/tokens.dart';
import 'package:lunaway/shared/widgets/app_form.dart';
import 'package:lunaway/shared/widgets/form_sheet.dart';
import 'package:lunaway/shared/widgets/night_badge.dart';

/// Adds a place near [position]: the level first (2), then the spot set to
/// the metre under a crosshair, then, when a place already stands within
/// [duplicateRadiusM], whether it is the same one, and the form.
Future<void> startAddPlace(BuildContext context, WidgetRef ref, LatLng position) async {
  final t = context.t;
  if (!await passesGate(context, ref, level: TrustLevels.addPlace, title: t.gate.addPlace)) {
    return;
  }
  if (!context.mounted) return;
  final placement = await pickPlacement(context, position);
  if (placement == null || !context.mounted) return;
  final spot = placement.position;
  final local = await localPlacesAround(ref, spot);
  if (!context.mounted) return;
  final twin = nearestPlace([...placement.around, ...local], spot);
  if (twin != null) {
    final same = await askSamePlace(context, twin.place, twin.metres);
    if (same == null || !context.mounted) return;
    if (same) {
      ref.read(mapFlowProvider.notifier).select(PlaceSelection(twin.place.id, hint: twin.place));
      unawaited(ref.read(mapControllerProvider)?.moveTo(twin.place.position));
      return;
    }
  }
  await showFormSheet<void>(
    context,
    builder: (context, scroll) => PlaceForm(position: spot, scrollController: scroll),
  );
}

/// Edits [place]: applied at once from level 3, a proposal for a moderator
/// from level 1, closed below.
Future<void> startEditPlace(BuildContext context, WidgetRef ref, Place place) async {
  final t = context.t;
  if (!await passesGate(context, ref, level: TrustLevels.proposeEdit, title: t.gate.edit)) {
    return;
  }
  if (!context.mounted) return;
  await showFormSheet<void>(
    context,
    builder: (context, scroll) =>
        PlaceForm(position: place.position, place: place, scrollController: scroll),
  );
}

/// The form of a new place, or of an edit when [place] is given: what it
/// is, its name, the night, its services, and, folded, the details. A new
/// place may take a photo, sent once the server has placed it.
class PlaceForm extends ConsumerStatefulWidget {
  const new({required this.position, this.place, this.scrollController, super.key});

  final LatLng position;
  final Place? place;
  final ScrollController? scrollController;

  @override
  ConsumerState<PlaceForm> createState() => _PlaceFormState();
}

class _PlaceFormState extends ConsumerState<PlaceForm> {
  late PlaceKind? _kind = widget.place?.kind;
  late OvernightStatus _night = widget.place?.overnight ?? OvernightStatus.unknown;
  late Set<Service> _services = {...?widget.place?.services};
  late final _name = TextEditingController(text: widget.place?.name ?? '');
  late final _description = TextEditingController();
  late final Map<String, TextEditingController> _details = {
    'priceParking': TextEditingController(text: _number(widget.place?.priceParkingEur)),
    'priceServices': TextEditingController(text: _number(widget.place?.priceServicesEur)),
    'maxHeight': TextEditingController(text: _number(widget.place?.maxHeightM)),
    'capacity': TextEditingController(text: widget.place?.capacity?.toString() ?? ''),
    'website': TextEditingController(text: widget.place?.website ?? ''),
    'phone': TextEditingController(text: widget.place?.phone ?? ''),
  };
  PreparedPhoto? _photo;

  bool get _editing => widget.place != null;

  /// The heights a barrier or a clearance of a place may state: the same
  /// as a low clearance reported on the road.
  static const ({double min, double max}) maxHeightRange = (min: 1.5, max: 6.0);

  String _number(double? v) =>
      v == null ? '' : NumberFormat('0.##', LocaleSettings.currentLocale.languageCode).format(v);

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    for (final c in _details.values) {
      c.dispose();
    }
    super.dispose();
  }

  /// What the form states, as the API's input: everything for a new place,
  /// only what changed for an edit.
  PlaceDetails _details0() {
    final place = widget.place;
    String? text(String key) {
      final v = _details[key]!.text.trim();
      return v.isEmpty ? null : v;
    }

    double? num(String key) => parseDecimal(_details[key]!.text);
    final name = _name.text.trim().isEmpty ? null : _name.text.trim();
    final description = _description.text.trim().isEmpty ? null : _description.text.trim();
    final capacity = int.tryParse(_details['capacity']!.text.trim());
    if (place == null) {
      return PlaceDetails(
        name: name,
        overnight: _night,
        services: _services,
        description: description,
        descriptionLang: LocaleSettings.currentLocale.languageCode,
        priceParkingEur: num('priceParking'),
        priceServicesEur: num('priceServices'),
        maxHeightM: num('maxHeight'),
        capacity: capacity,
        website: text('website'),
        phone: text('phone'),
      );
    }
    T? changed<T>(T? value, T? before) => value != null && value != before ? value : null;
    // A field the place had that the form now leaves empty is cleared: the
    // community stops stating it.
    final clear = {
      if (place.priceParkingEur != null && num('priceParking') == null) PlaceField.priceParking,
      if (place.priceServicesEur != null && num('priceServices') == null) PlaceField.priceServices,
      if (place.maxHeightM != null && num('maxHeight') == null) PlaceField.maxHeight,
      if (place.capacity != null && capacity == null) PlaceField.capacity,
      if (place.website != null && text('website') == null) PlaceField.website,
      if (place.phone != null && text('phone') == null) PlaceField.phone,
    };
    return PlaceDetails(
      name: changed(name, place.name),
      kind: changed(_kind, place.kind),
      overnight: changed(_night, place.overnight),
      services: const SetEquality<Service>().equals(_services, place.services) ? null : _services,
      description: description,
      descriptionLang: LocaleSettings.currentLocale.languageCode,
      priceParkingEur: changed(num('priceParking'), place.priceParkingEur),
      priceServicesEur: changed(num('priceServices'), place.priceServicesEur),
      maxHeightM: changed(num('maxHeight'), place.maxHeightM),
      capacity: changed(capacity, place.capacity),
      website: changed(text('website'), place.website),
      phone: changed(text('phone'), place.phone),
      clear: clear,
    );
  }

  /// Sends the place (the form has checked every field): the sheet closes
  /// at once and the outbox says what became of it.
  Future<void> _submit() async {
    final t = context.t;
    final kind = _kind;
    if (kind == null) return;
    final details = _details0();
    final navigator = Navigator.of(context);
    if (_editing && details.isEmpty) {
      showMessage(ScaffoldMessenger.maybeOf(context), t.placeForm.nothingChanged);
      navigator.pop();
      return;
    }
    final level = ref.read(trustLevelProvider);
    final files = ref.read(pendingFilesProvider);
    final photo = _photo;
    final place = widget.place;
    // The message of the result shows from the app once the form is gone.
    final root = navigator.context;
    navigator.pop();
    final fileId = photo == null ? null : await files.put(photo.jpeg);
    if (!root.mounted) return;
    if (place == null) {
      await submitContribution(
        root,
        ContributionKind.addPlace,
        fileId: fileId,
        sentText: t.placeForm.added,
        payload: {
          'input': {
            'kind': kind.wire,
            'lat': widget.position.lat,
            'lon': widget.position.lon,
            'details': details.toInput(),
          },
        },
      );
    } else {
      await submitContribution(
        root,
        ContributionKind.editPlace,
        placeId: place.id,
        sentText: level >= TrustLevels.editDirectly ? t.placeForm.added : t.placeForm.proposed,
        payload: {'placeId': place.id, 'patch': details.toInput()},
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final level = ref.watch(trustLevelProvider);
    final direct = level >= TrustLevels.editDirectly;
    final contact =
        _details['website']!.text.trim().isNotEmpty || _details['phone']!.text.trim().isNotEmpty;
    Widget heading(String text) => Padding(
      padding: const EdgeInsets.only(top: Space.xl, bottom: Space.s),
      child: Semantics(header: true, child: Text(text, style: theme.textTheme.titleMedium)),
    );
    Widget numberField(
      String key,
      String label,
      IconData icon, {
      FieldKind kind = FieldKind.decimal,
      FormFieldValidator<String>? validator,
    }) => Padding(
      padding: const EdgeInsets.only(bottom: Space.m),
      child: LunaTextField(
        controller: _details[key]!,
        label: label,
        kind: kind,
        icon: icon,
        validator: validator,
      ),
    );

    return LunaForm(
      onSubmit: _submit,
      child: FormSheetFrame(
        title: !_editing
            ? t.placeForm.addTitle
            : direct
            ? t.placeForm.editTitle
            : t.placeForm.proposeTitle,
        scrollController: widget.scrollController,
        footnote: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!_editing) Text(t.placeForm.toVerify),
            if (_editing) Text(direct ? t.placeForm.direct : t.placeForm.proposal),
            if (contact && !direct) Text(t.placeForm.moderated),
            Text(t.placeForm.licence),
          ],
        ),
        action: SubmitButton(
          label: !_editing
              ? t.placeForm.submitAdd
              : direct
              ? t.placeForm.submitEdit
              : t.placeForm.submitPropose,
        ),
        children: [
          Container(
            padding: const EdgeInsets.all(Space.m),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(LunaTokens.radiusL),
            ),
            child: Row(
              children: [
                const Icon(AppIcons.point, color: LunaTokens.selection),
                const SizedBox(width: Space.m),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(t.placeForm.position, style: theme.textTheme.labelMedium),
                      Text(
                        CoordinateFormat.decimal.format(widget.position),
                        style: theme.textTheme.bodyLarge,
                      ),
                      if (!_editing)
                        Text(
                          t.contribute.addPlaceHint,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          heading(t.placeForm.kind),
          LunaFormField<PlaceKind>(
            label: t.placeForm.kind,
            value: _kind,
            validator: (kind) => kind == null ? t.placeForm.kindRequired : null,
            builder: (context) => Wrap(
              spacing: Space.s,
              runSpacing: Space.s,
              children: [
                for (final kind in PlaceKind.values)
                  ChoiceChip(
                    mouseCursor: WidgetStateMouseCursor.clickable,
                    avatar: Icon(AppIcons.kind(kind), size: 18),
                    label: Text(t.kind(kind)),
                    selected: _kind == kind,
                    onSelected: (_) => setState(() => _kind = kind),
                  ),
              ],
            ),
          ),
          heading(t.placeForm.name),
          LunaTextField(
            controller: _name,
            label: t.placeForm.name,
            hint: t.placeForm.nameHint,
            maxLength: ContributionLimits.placeNameMax,
            validator: (v) {
              final length = (v ?? '').trim().runes.length;
              // A new place needs a name; an edit may leave it as it is.
              if (_editing && length == 0) return null;
              return length < ContributionLimits.placeNameMin ? t.placeForm.nameInvalid : null;
            },
          ),
          heading(t.placeForm.night),
          Wrap(
            spacing: Space.s,
            runSpacing: Space.s,
            children: [
              for (final status in OvernightStatus.values)
                ChoiceChip(
                  mouseCursor: WidgetStateMouseCursor.clickable,
                  avatar: NightBadge(status),
                  label: Text(t.overnightShort(status)),
                  selected: _night == status,
                  onSelected: (_) => setState(() => _night = status),
                ),
            ],
          ),
          heading(t.placeForm.services),
          Wrap(
            spacing: Space.s,
            runSpacing: Space.s,
            children: [
              for (final s in Service.values)
                FilterChip(
                  mouseCursor: WidgetStateMouseCursor.clickable,
                  avatar: Icon(AppIcons.service(s), size: 18),
                  label: Text(t.service(s)),
                  selected: _services.contains(s),
                  onSelected: (on) => setState(
                    () => _services = on ? {..._services, s} : ({..._services}..remove(s)),
                  ),
                ),
            ],
          ),
          if (!_editing) ...[
            heading(t.placeForm.photo),
            _PhotoField(
              photo: _photo,
              onPick: () async {
                final photo = await pickPhoto(context, ref);
                if (photo != null && mounted) setState(() => _photo = photo);
              },
              onRemove: () => setState(() => _photo = null),
            ),
          ],
          heading(t.placeForm.description),
          LunaTextField(
            controller: _description,
            label: t.placeForm.description,
            hint: t.placeForm.descriptionHint,
            kind: FieldKind.multiline,
            minLines: 2,
            maxLength: ContributionLimits.reviewMax,
          ),
          const SizedBox(height: Space.s),
          FoldedFields(
            title: Text(t.placeForm.details, style: theme.textTheme.titleMedium),
            children: [
              numberField(
                'priceParking',
                t.placeForm.priceNight,
                AppIcons.pricePerNight,
                validator: decimalCheck(context),
              ),
              numberField(
                'priceServices',
                t.placeForm.priceServices,
                AppIcons.priceServices,
                validator: decimalCheck(context),
              ),
              numberField(
                'maxHeight',
                t.placeForm.maxHeight,
                AppIcons.height,
                validator: decimalCheck(context, range: maxHeightRange, unit: 'm'),
              ),
              numberField(
                'capacity',
                t.placeForm.capacity,
                AppIcons.capacity,
                kind: FieldKind.integer,
              ),
              Padding(
                padding: const EdgeInsets.only(bottom: Space.m),
                child: LunaTextField(
                  controller: _details['website']!,
                  label: t.placeForm.website,
                  kind: FieldKind.url,
                  icon: AppIcons.website,
                  onChanged: (_) => setState(() {}),
                  validator: (v) {
                    final text = (v ?? '').trim();
                    if (text.isEmpty) return null;
                    final uri = Uri.tryParse(text);
                    return uri != null &&
                            (uri.scheme == 'http' || uri.scheme == 'https') &&
                            uri.host.isNotEmpty
                        ? null
                        : t.placeForm.invalidWebsite;
                  },
                ),
              ),
              LunaTextField(
                controller: _details['phone']!,
                label: t.placeForm.phone,
                kind: FieldKind.phone,
                icon: AppIcons.call,
                textInputAction: TextInputAction.done,
                onChanged: (_) => setState(() {}),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PhotoField extends StatelessWidget {
  const new({required this.photo, required this.onPick, required this.onRemove});

  final PreparedPhoto? photo;
  final VoidCallback onPick;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final theme = Theme.of(context);
    final picked = photo;
    if (picked == null) {
      return OutlinedButton.icon(
        onPressed: onPick,
        icon: const Icon(AppIcons.addPhoto),
        label: Text(t.contribute.addPhoto),
        style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(56)),
      );
    }
    return Row(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(LunaTokens.radiusM),
          child: Image.memory(
            picked.jpeg,
            width: 96,
            height: 72,
            fit: BoxFit.cover,
            excludeFromSemantics: true,
          ),
        ),
        const SizedBox(width: Space.m),
        Expanded(child: Text(t.placeForm.photoReady, style: theme.textTheme.bodyLarge)),
        IconButton(
          tooltip: t.placeForm.removePhoto,
          icon: const Icon(AppIcons.delete),
          onPressed: onRemove,
        ),
      ],
    );
  }
}
