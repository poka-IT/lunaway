import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lunaway/core/geo/geo.dart';
import 'package:lunaway/features/map/domain/luna_map.dart';
import 'package:lunaway/features/map/domain/map_geojson.dart';
import 'package:lunaway/shared/theme/palette.dart';

import 'fakes.dart';

/// A stand-in map for golden images: a flat basemap in the colours of the
/// Aube and Minuit styles, the real pin images (`assets/map/pins/2x/`) where
/// the places are, and two clusters drawn as the map draws them, so the
/// layouts read as they do on a device.
final class GoldenMap extends FakeMap {
  new(this.bounds);

  final GeoBounds bounds;

  @override
  Widget build(BuildContext context, LunaMapProps props) {
    lastProps = props;
    return _GoldenMapView(map: this, props: props);
  }
}

class _GoldenMapView extends StatefulWidget {
  const new({required this.map, required this.props});

  final GoldenMap map;
  final LunaMapProps props;

  @override
  State<_GoldenMapView> createState() => _GoldenMapViewState();
}

class _GoldenMapViewState extends State<_GoldenMapView> {
  @override
  void initState() {
    super.initState();
    scheduleMicrotask(() {
      if (!mounted) return;
      widget.props.onMapReady(widget.map);
      widget.props.onViewportChanged(
        MapViewport(bounds: widget.map.bounds, center: widget.map.bounds.center, zoom: 11),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final dark = widget.props.dark;
    final b = widget.map.bounds;
    return LayoutBuilder(
      builder: (context, constraints) {
        Offset at(LatLng p) => Offset(
          (p.lon - b.west) / (b.east - b.west) * constraints.maxWidth,
          (b.north - p.lat) / (b.north - b.south) * constraints.maxHeight,
        );
        final selected = widget.props.selectedId;
        final places = [
          for (final p in widget.props.places)
            if (b.contains(p.position)) p,
        ]..sort((a, c) => (a.id == selected ? 1 : 0).compareTo(c.id == selected ? 1 : 0));
        return Stack(
          children: [
            Positioned.fill(
              child: CustomPaint(painter: _Basemap(dark: dark)),
            ),
            for (final (count, x, y) in const [(12, 0.18, 0.22), (48, 0.78, 0.3)])
              Positioned(
                left: constraints.maxWidth * x - 20,
                top: constraints.maxHeight * y - 20,
                child: _Cluster(count: count, dark: dark),
              ),
            for (final p in places)
              () {
                final isSelected = p.id == selected;
                // The sprites hold 2x pixels; the map shows them at 1x, the
                // tip on the place.
                final size = isSelected ? 52.0 : 40.0;
                final point = at(p.position);
                return Positioned(
                  left: point.dx - size / 2,
                  top: point.dy - size,
                  width: size,
                  height: size,
                  child: Image.asset(
                    'assets/map/pins/2x/${pinImageId(p.kind, p.overnight, selected: isSelected)}.png',
                    fit: BoxFit.contain,
                    alignment: Alignment.bottomCenter,
                  ),
                );
              }(),
          ],
        );
      },
    );
  }
}

/// A cluster as the map layer draws it: a disc sized by its count, the
/// count in the middle.
class _Cluster extends StatelessWidget {
  const new({required this.count, required this.dark});

  final int count;
  final bool dark;

  @override
  Widget build(BuildContext context) => Container(
    width: 40,
    height: 40,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: (dark ? Palette.creme : Palette.minuit).withValues(alpha: 0.94),
      border: Border.all(color: dark ? Palette.minuit : Palette.creme, width: 2.5),
    ),
    child: Text(
      '$count',
      style: TextStyle(
        fontFamily: 'Atkinson',
        fontWeight: FontWeight.w600,
        fontSize: 13,
        color: dark ? Palette.minuit : Palette.creme,
      ),
    ),
  );
}

class _Basemap extends CustomPainter {
  new({required this.dark});

  final bool dark;

  @override
  void paint(Canvas canvas, Size size) {
    // The land, water and road tones of the Aube and Minuit styles.
    final land = Paint()..color = dark ? const Color(0xFF0B2342) : const Color(0xFFF3EAD9);
    final water = Paint()..color = dark ? const Color(0xFF0E3A52) : const Color(0xFFAED8DA);
    final road = Paint()
      ..color = dark ? const Color(0xFF26446A) : const Color(0xFFFFFFFF)
      ..strokeWidth = 4
      ..style = PaintingStyle.stroke;
    canvas
      ..drawRect(Offset.zero & size, land)
      ..drawPath(
        Path()
          ..moveTo(0, size.height * 0.72)
          ..quadraticBezierTo(
            size.width * 0.3,
            size.height * 0.62,
            size.width * 0.55,
            size.height * 0.8,
          )
          ..quadraticBezierTo(size.width * 0.75, size.height * 0.95, size.width, size.height * 0.85)
          ..lineTo(size.width, size.height)
          ..lineTo(0, size.height)
          ..close(),
        water,
      )
      ..drawPath(
        Path()
          ..moveTo(size.width * 0.1, 0)
          ..quadraticBezierTo(
            size.width * 0.4,
            size.height * 0.4,
            size.width * 0.35,
            size.height * 0.65,
          ),
        road,
      )
      ..drawPath(
        Path()
          ..moveTo(0, size.height * 0.3)
          ..quadraticBezierTo(size.width * 0.5, size.height * 0.25, size.width, size.height * 0.45),
        road,
      );
  }

  @override
  bool shouldRepaint(_Basemap old) => old.dark != dark;
}
