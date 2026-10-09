import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lunaway/features/navigation/application/guidance_camera.dart';
import 'package:lunaway/features/navigation/application/navigation_providers.dart';
import 'package:lunaway/features/navigation/domain/guidance_marks.dart';
import 'package:lunaway/features/navigation/domain/guidance_places.dart';
import 'package:lunaway/features/navigation/presentation/rich_mark_art.dart';
import 'package:lunaway/features/places/domain/place_filter.dart';
import 'package:lunaway/features/places/domain/taxonomy.dart';
import 'package:lunaway/features/poi/domain/poi.dart';
import 'package:lunaway/features/poi/presentation/poi_labels.dart';
import 'package:lunaway/features/poi/presentation/poi_look.dart';
import 'package:lunaway/i18n/strings.g.dart';
import 'package:lunaway/shared/labels.dart';
import 'package:lunaway/shared/map/pin_painter.dart';
import 'package:lunaway/shared/theme/app_icons.dart';
import 'package:lunaway/shared/theme/palette.dart';
import 'package:lunaway/shared/theme/tokens.dart';
import 'package:lunaway/shared/widgets/modal_sheet.dart';
import 'package:lunaway/shared/widgets/night_badge.dart';

/// The guidance's places sheet: which places and services the map shows,
/// and how. One tap on a ready-made choice covers what a driver looks for
/// on the way; "Personnaliser" opens every category of the main map's
/// filters; the display picks photos, pictograms or small pins. The choice
/// is kept for the next guidances. The map stays where it is while the
/// sheet is open.
Future<void> showGuidancePlacesSheet(BuildContext context) async {
  final container = ProviderScope.containerOf(context, listen: false);
  final release = container.read(guidanceCameraProvider.notifier).hold();
  try {
    await showSheet<void>(
      context,
      // A phone on its side, large text or the categories open: the sheet
      // scrolls rather than hide its last choices.
      isScrollControlled: true,
      builder: (_) => const GuidancePlacesSheet(),
    );
  } finally {
    release();
  }
}

/// The body of the sheet, public for the tests.
class GuidancePlacesSheet extends ConsumerStatefulWidget {
  const new({super.key});

  @override
  ConsumerState<GuidancePlacesSheet> createState() => _GuidancePlacesSheetState();
}

class _GuidancePlacesSheetState extends ConsumerState<GuidancePlacesSheet> {
  /// The categories shown; null until the first build decides (open when
  /// the choice is one the user made).
  bool? _custom;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final choice =
        ref.watch(routeSettingsControllerProvider).value?.guidancePlaces ?? const GuidancePlaces();
    void set(GuidancePlaces next) =>
        unawaited(ref.read(routeSettingsControllerProvider.notifier).setGuidancePlaces(next));
    void select(GuidanceSelection s) => set(choice.copyWith(selection: s));
    final preset = choice.preset;
    final custom = _custom ??= preset == null;
    final s = choice.selection;
    Widget heading(String text) => Padding(
      padding: const EdgeInsets.only(top: Space.l, bottom: Space.xs),
      child: Semantics(header: true, child: Text(text, style: theme.textTheme.titleSmall)),
    );
    Widget chips(List<Widget> children) =>
        Wrap(spacing: Space.s, runSpacing: Space.s, children: children);
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(Space.l, 0, Space.l, Space.l),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(
              header: true,
              child: Text(t.navigation.guidance.places.title, style: theme.textTheme.titleLarge),
            ),
            const SizedBox(height: Space.m),
            chips([
              for (final p in GuidancePreset.values)
                ChoiceChip(
                  avatar: Icon(_presetIcon(p), size: 20),
                  label: Text(_presetLabel(t, p)),
                  selected: preset == p,
                  showCheckmark: false,
                  mouseCursor: WidgetStateMouseCursor.clickable,
                  onSelected: (_) => select(p.selection),
                ),
            ]),
            const SizedBox(height: Space.xs),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: Semantics(
                expanded: custom,
                child: TextButton.icon(
                  onPressed: () => setState(() => _custom = !custom),
                  icon: AnimatedRotation(
                    turns: custom ? 0.5 : 0,
                    duration: const Duration(milliseconds: 160),
                    child: const Icon(AppIcons.chevronDown),
                  ),
                  label: Text(t.navigation.guidance.places.customize),
                ),
              ),
            ),
            if (custom) ...[
              heading(t.filters.night),
              chips([
                for (final o in OvernightStatus.values)
                  _Toggle(
                    leading: NightBadge(o, size: 20),
                    label: t.overnightShort(o),
                    selected: s.overnight.contains(o),
                    onTap: () => select(s.toggleOvernight(o)),
                  ),
              ]),
              heading(t.filters.families),
              chips([
                for (final f in KindFamily.values)
                  _Toggle(
                    leading: Icon(AppIcons.family(f), size: 20),
                    label: t.family(f),
                    selected: s.families.contains(f),
                    onTap: () => select(s.toggleFamily(f)),
                  ),
              ]),
              heading(t.filters.amenities),
              chips([
                for (final a in Amenity.offered)
                  _Toggle(
                    leading: Icon(AppIcons.amenity(a), size: 20),
                    label: t.amenity(a),
                    selected: s.amenities.contains(a),
                    onTap: () => select(s.toggleAmenity(a)),
                  ),
              ]),
              heading(t.poi.searchSection),
              chips([
                for (final c in GuidanceSelection.pointCategories)
                  _Toggle(
                    leading: Icon(PoiLook.category(c), size: 20),
                    label: t.poiCategory(c),
                    selected: s.points.contains(c),
                    onTap: () => select(s.togglePoints(c)),
                  ),
              ]),
              heading(t.poi.category.vending),
              chips([
                for (final k in PoiKind.vendingChoices)
                  _Toggle(
                    leading: Icon(PoiLook.kind(k), size: 20),
                    label: t.poiVendingSells(k),
                    selected: s.vending.contains(k),
                    onTap: () => select(s.toggleVending(k)),
                  ),
              ]),
              heading(t.filters.rating),
              chips([
                for (final step in minRatingSteps)
                  _Toggle(
                    leading: const Icon(AppIcons.star, size: 20),
                    label: t.filters.ratingAtLeast(rating: t.ratingStep(step)),
                    selected: s.minRating == step,
                    onTap: () => select(s.toggleMinRating(step)),
                  ),
              ]),
            ],
            heading(t.navigation.guidance.places.look),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final (i, look) in GuidanceLook.values.indexed) ...[
                  if (i > 0) const SizedBox(width: Space.s),
                  Expanded(
                    child: _LookTile(
                      look: look,
                      selected: choice.look == look,
                      onTap: () => set(choice.copyWith(look: look)),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: Space.s),
            Text(
              _lookHint(t, choice.look),
              style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

IconData _presetIcon(GuidancePreset p) => switch (p) {
  .sleep => AppIcons.pricePerNight,
  .fill => AppIcons.fuel,
  .groceries => PoiLook.category(PoiCategory.groceries),
  .all => AppIcons.map,
  .none => AppIcons.muted,
};

String _presetLabel(Translations t, GuidancePreset p) => switch (p) {
  .sleep => t.navigation.guidance.places.sleep,
  .fill => t.navigation.guidance.places.fill,
  .groceries => t.navigation.guidance.places.groceries,
  .all => t.navigation.guidance.places.all,
  .none => t.navigation.guidance.places.none,
};

String _lookLabel(Translations t, GuidanceLook look) => switch (look) {
  .photos => t.navigation.guidance.places.photos,
  .pictograms => t.navigation.guidance.places.pictograms,
  .dots => t.navigation.guidance.places.dots,
};

String _lookHint(Translations t, GuidanceLook look) => switch (look) {
  .photos => t.navigation.guidance.places.photosHint,
  .pictograms => t.navigation.guidance.places.pictogramsHint,
  .dots => t.navigation.guidance.places.dotsHint,
};

/// A category: on, the map shows its places or points.
class _Toggle extends StatelessWidget {
  const new({
    required this.leading,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final Widget leading;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => FilterChip(
    avatar: leading,
    label: Text(label),
    selected: selected,
    showCheckmark: false,
    mouseCursor: WidgetStateMouseCursor.clickable,
    onSelected: (_) => onTap(),
  );
}

/// One way of drawing the places, with a small picture of it.
class _LookTile extends StatelessWidget {
  const new({required this.look, required this.selected, required this.onTap});

  final GuidanceLook look;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(LunaTokens.radiusM),
      side: BorderSide(
        color: selected ? scheme.primary : scheme.outlineVariant,
        width: selected ? 2 : 1,
      ),
    );
    return Semantics(
      button: true,
      selected: selected,
      inMutuallyExclusiveGroup: true,
      excludeSemantics: true,
      label: _lookLabel(context.t, look),
      child: Material(
        color: selected ? scheme.secondaryContainer : scheme.surfaceContainerLow,
        shape: shape,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          mouseCursor: WidgetStateMouseCursor.clickable,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(Space.xs, Space.s, Space.xs, Space.s),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  height: 60,
                  width: double.infinity,
                  child: CustomPaint(painter: _LookPreview(look, context.t)),
                ),
                const SizedBox(height: Space.xs),
                Text(
                  _lookLabel(context.t, look),
                  textAlign: TextAlign.center,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: selected ? scheme.onSecondaryContainer : scheme.onSurface,
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

/// A small picture of a look: a photo mark, an illustrated mark with its
/// label, or three small pins, drawn by the map's own painters.
class _LookPreview extends CustomPainter {
  new(this.look, this.t);

  final GuidanceLook look;
  final Translations t;

  @override
  void paint(Canvas canvas, Size size) {
    switch (look) {
      case GuidanceLook.photos:
        _mark(
          canvas,
          size,
          const RichGeometry(44),
          PhotoFace(_scene),
          PlaceKind.motorhomeArea,
          OvernightStatus.allowed,
        );
      case GuidanceLook.pictograms:
        final label = t.euros(12);
        _mark(
          canvas,
          size,
          RichGeometry(48, labelWidth: richLabelWidth(label), capsule: true),
          IllustratedFace(label: label),
          PlaceKind.campsite,
          OvernightStatus.allowed,
        );
      case GuidanceLook.dots:
        const scale = 0.72;
        final pin = const PinGeometry(selected: false).canvas;
        for (final (i, (kind, night)) in [
          (PlaceKind.parking, OvernightStatus.tolerated),
          (PlaceKind.campsite, OvernightStatus.allowed),
          (PlaceKind.serviceArea, OvernightStatus.dayOnly),
        ].indexed) {
          final x = size.width / 2 + (i - 1) * size.width * 0.28;
          final y = size.height * (i == 1 ? 0.62 : 0.86);
          canvas
            ..save()
            ..translate(x - pin.width * scale / 2, y - pin.height * scale)
            ..scale(scale);
          paintPin(canvas, kind: kind, overnight: night, selected: false);
          canvas.restore();
        }
    }
  }

  void _mark(
    Canvas canvas,
    Size size,
    RichGeometry g,
    RichFace face,
    PlaceKind kind,
    OvernightStatus night,
  ) {
    final mark = richMarkCanvas(g);
    final scale = (size.height / mark.height).clamp(0.0, 1.0);
    canvas
      ..save()
      ..translate((size.width - mark.width * scale) / 2, size.height - mark.height * scale)
      ..scale(scale);
    paintRichMark(canvas, g: g, face: face, kind: kind, night: night);
    canvas.restore();
  }

  /// A landscape in the brand's colours, standing for a place's photo.
  static final ui.Image _scene = () {
    const side = 96.0;
    final recorder = ui.PictureRecorder();
    Canvas(recorder)
      ..drawRect(
        const Rect.fromLTWH(0, 0, side, side),
        Paint()
          ..shader = ui.Gradient.linear(Offset.zero, const Offset(0, side), [
            Palette.sarcelle200,
            Palette.creme,
          ]),
      )
      ..drawCircle(
        const Offset(side * 0.72, side * 0.3),
        side * 0.1,
        Paint()..color = Palette.lanterne,
      )
      ..drawPath(
        Path()
          ..moveTo(0, side * 0.62)
          ..quadraticBezierTo(side * 0.35, side * 0.42, side * 0.7, side * 0.6)
          ..quadraticBezierTo(side * 0.85, side * 0.66, side, side * 0.56)
          ..lineTo(side, side)
          ..lineTo(0, side)
          ..close(),
        Paint()..color = Palette.sarcelle,
      )
      ..drawPath(
        Path()
          ..moveTo(0, side * 0.8)
          ..quadraticBezierTo(side * 0.5, side * 0.66, side, side * 0.82)
          ..lineTo(side, side)
          ..lineTo(0, side)
          ..close(),
        Paint()..color = Palette.sarcelle800,
      )
      ..drawRect(
        const Rect.fromLTWH(side * 0.36, side * 0.72, side * 0.3, side * 0.12),
        Paint()..color = Palette.creme,
      );
    return recorder.endRecording().toImageSync(side.toInt(), side.toInt());
  }();

  @override
  bool shouldRepaint(_LookPreview old) => old.look != look || old.t != t;
}
