import 'package:flutter/painting.dart';
import 'package:lunaway/features/navigation/domain/maneuver.dart';
import 'package:lunaway/shared/theme/palette.dart';

/// Every maneuver pictogram the router's answers can call for, named: the
/// golden images and the review sheet (`tool/pictos/sheet_test.dart`) draw
/// this list.
const maneuverCatalogue = <(String, Maneuver)>[
  ('straight', Maneuver(type: 'turn', modifier: 'straight')),
  ('slight-left', Maneuver(type: 'turn', modifier: 'slight left')),
  ('left', Maneuver(type: 'turn', modifier: 'left')),
  ('sharp-left', Maneuver(type: 'turn', modifier: 'sharp left')),
  ('slight-right', Maneuver(type: 'turn', modifier: 'slight right')),
  ('right', Maneuver(type: 'turn', modifier: 'right')),
  ('sharp-right', Maneuver(type: 'turn', modifier: 'sharp right')),
  ('uturn', Maneuver(type: 'continue', modifier: 'uturn')),
  ('uturn-lht', Maneuver(type: 'continue', modifier: 'uturn', leftHandTraffic: true)),
  ('new-name', Maneuver(type: 'new name', modifier: 'straight')),
  ('keep-left', Maneuver(type: 'fork', modifier: 'slight left')),
  ('keep-right', Maneuver(type: 'fork', modifier: 'slight right')),
  ('fork-straight', Maneuver(type: 'fork', modifier: 'straight')),
  ('on-ramp-right', Maneuver(type: 'on ramp', modifier: 'slight right')),
  ('on-ramp-left', Maneuver(type: 'on ramp', modifier: 'slight left')),
  ('off-ramp-right', Maneuver(type: 'off ramp', modifier: 'slight right')),
  ('off-ramp-left', Maneuver(type: 'off ramp', modifier: 'slight left')),
  ('merge-left', Maneuver(type: 'merge', modifier: 'slight left')),
  ('merge-right', Maneuver(type: 'merge', modifier: 'slight right')),
  ('end-of-road-left', Maneuver(type: 'end of road', modifier: 'left')),
  ('end-of-road-right', Maneuver(type: 'end of road', modifier: 'right')),
  ('depart', Maneuver(type: 'depart')),
  ('arrive', Maneuver(type: 'arrive')),
  ('arrive-left', Maneuver(type: 'arrive', modifier: 'left')),
  ('arrive-right', Maneuver(type: 'arrive', modifier: 'right')),
  ('ferry', Maneuver(type: 'notification', modifier: 'straight', ferry: true)),
  ('roundabout-1st-right', Maneuver(type: 'roundabout', exitDegrees: 90, exitNumber: 1)),
  ('roundabout-2nd-ahead', Maneuver(type: 'roundabout', exitDegrees: 180, exitNumber: 2)),
  ('roundabout-3rd-left', Maneuver(type: 'roundabout', exitDegrees: 270, exitNumber: 3)),
  // Limoges, Place Maison-Dieu: the second exit, a little left of ahead.
  ('roundabout-212', Maneuver(type: 'roundabout', exitDegrees: 212, exitNumber: 2)),
  // Brive to Ussel: a fourth exit almost back the way the road came.
  ('roundabout-326', Maneuver(type: 'roundabout', exitDegrees: 326, exitNumber: 4)),
  ('roundabout-45', Maneuver(type: 'roundabout', exitDegrees: 45, exitNumber: 1)),
  ('roundabout-exit', Maneuver(type: 'exit roundabout', exitDegrees: 151, exitNumber: 2)),
  (
    'roundabout-lht-1st-left',
    Maneuver(type: 'roundabout', exitDegrees: 90, exitNumber: 1, leftHandTraffic: true),
  ),
  (
    'roundabout-lht-2nd-ahead',
    Maneuver(type: 'roundabout', exitDegrees: 180, exitNumber: 2, leftHandTraffic: true),
  ),
  (
    'roundabout-lht-3rd-right',
    Maneuver(type: 'roundabout', exitDegrees: 270, exitNumber: 3, leftHandTraffic: true),
  ),
];

/// The sizes the app draws them at, logical pixels: the banner, the
/// arrival card, the route's list of steps, the lanes, the "Then" line.
const maneuverSizes = [76.0, 44.0, 32.0, 30.0, 28.0];

/// Where they are drawn: the guidance banner in each theme (the dock's
/// navy by day, the floating surface at night) and the list of steps on
/// each theme's surface, as (name, background, colour).
const maneuverGrounds = <(String, Color, Color)>[
  ('banner-light', Palette.minuit, Palette.creme),
  ('banner-dark', Palette.minuit800, Palette.creme),
  ('list-light', Palette.creme100, Palette.sarcelleProfonde),
  ('list-dark', Palette.minuit900, Palette.sarcelle300),
];
