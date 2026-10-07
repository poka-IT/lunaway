import 'dart:async';

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
import 'package:lunaway/features/map/application/map_state.dart';
import 'package:lunaway/features/places/domain/place.dart';
import 'package:lunaway/features/places/domain/taxonomy.dart';
import 'package:lunaway/i18n/strings.g.dart';
import 'package:lunaway/shared/labels.dart';
import 'package:lunaway/shared/messages.dart';
import 'package:lunaway/shared/theme/app_icons.dart';
import 'package:lunaway/shared/theme/tokens.dart';
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
      ref.read(selectionProvider.notifier).select(PlaceSelection(twin.place.id, hint: twin.place));
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
  final _form = GlobalKey<FormState>();
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
  bool _kindMissing = false;

  bool get _editing => widget.place != null;

  String _number(double? v) =>
      v == null ? '' : NumberFormat('0.##', LocaleSettings.currentLocale.languageCode).format(v);

  static double? _parse(String text) {
    final cleaned = text.trim().replaceAll(',', '.').replaceAll(' ', '');
    return cleaned.isEmpty ? null : double.tryParse(cleaned);
  }

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

    double? num(String key) => _parse(_details[key]!.text);
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

  Future<void> _submit() async {
    final t = context.t;
    final kind = _kind;
    setState(() => _kindMissing = kind == null);
    if (!(_form.currentState?.validate() ?? false) || kind == null) return;
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
    Widget numberField(String key, String label, IconData icon, {bool integer = false}) => Padding(
      padding: const EdgeInsets.only(bottom: Space.m),
      child: TextFormField(
        controller: _details[key],
        keyboardType: integer
            ? TextInputType.number
            : const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(integer ? '[0-9]' : '[0-9.,]'))],
        decoration: InputDecoration(labelText: label, prefixIcon: Icon(icon)),
        validator: (v) =>
            v == null || v.trim().isEmpty || _parse(v) != null ? null : t.placeForm.invalidNumber,
      ),
    );

    return Form(
      key: _form,
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
        action: FilledButton(
          onPressed: _submit,
          child: Text(
            !_editing
                ? t.placeForm.submitAdd
                : direct
                ? t.placeForm.submitEdit
                : t.placeForm.submitPropose,
          ),
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
          Wrap(
            spacing: Space.s,
            runSpacing: Space.s,
            children: [
              for (final kind in PlaceKind.values)
                ChoiceChip(
                  avatar: Icon(AppIcons.kind(kind), size: 18),
                  label: Text(t.kind(kind)),
                  selected: _kind == kind,
                  onSelected: (_) => setState(() {
                    _kind = kind;
                    _kindMissing = false;
                  }),
                ),
            ],
          ),
          if (_kindMissing)
            Padding(
              padding: const EdgeInsets.only(top: Space.xs),
              child: Text(
                t.placeForm.kindRequired,
                style: theme.textTheme.bodySmall?.copyWith(color: scheme.error),
              ),
            ),
          heading(t.placeForm.name),
          TextFormField(
            controller: _name,
            textCapitalization: TextCapitalization.sentences,
            maxLength: ContributionLimits.placeNameMax,
            decoration: InputDecoration(
              labelText: t.placeForm.name,
              hintText: t.placeForm.nameHint,
            ),
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
          TextFormField(
            controller: _description,
            minLines: 2,
            maxLines: 6,
            maxLength: ContributionLimits.reviewMax,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              labelText: t.placeForm.description,
              hintText: t.placeForm.descriptionHint,
              alignLabelWithHint: true,
            ),
          ),
          const SizedBox(height: Space.s),
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: Text(t.placeForm.details, style: theme.textTheme.titleMedium),
            childrenPadding: const EdgeInsets.only(top: Space.s),
            children: [
              numberField('priceParking', t.placeForm.priceNight, AppIcons.pricePerNight),
              numberField('priceServices', t.placeForm.priceServices, AppIcons.priceServices),
              numberField('maxHeight', t.placeForm.maxHeight, AppIcons.height),
              numberField('capacity', t.placeForm.capacity, AppIcons.capacity, integer: true),
              Padding(
                padding: const EdgeInsets.only(bottom: Space.m),
                child: TextFormField(
                  controller: _details['website'],
                  keyboardType: TextInputType.url,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    labelText: t.placeForm.website,
                    prefixIcon: const Icon(AppIcons.website),
                  ),
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
              TextFormField(
                controller: _details['phone'],
                keyboardType: TextInputType.phone,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText: t.placeForm.phone,
                  prefixIcon: const Icon(AppIcons.call),
                ),
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
