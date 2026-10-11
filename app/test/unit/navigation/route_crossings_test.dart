import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:lunaway/core/geo/geo.dart';
import 'package:lunaway/features/navigation/domain/osrm_shape.dart';
import 'package:lunaway/features/navigation/domain/route_plan.dart';

/// A route north along a meridian, a point every 0.001° (about 111 m), as
/// Valhalla's OSRM answer gives it: a toll booth on the motorway, then the
/// border into Switzerland, then an exit by its number and its signs.
String _answer() {
  final line = [for (var i = 0; i <= 40; i++) LatLng(45.9 + i * 0.001, 6.12)];
  List<double> at(int i) => [line[i].lon, line[i].lat];
  final metre = line[0].distanceTo(line[1]);
  Map<String, Object?> step(
    int from,
    int to, {
    required String type,
    String? modifier,
    List<Map<String, Object?>> intersections = const [],
    Map<String, Object?> extra = const {},
    int admin = 0,
  }) => {
    'distance': (to - from) * metre,
    'duration': (to - from) * 4.0,
    'name': '',
    'maneuver': {'type': type, 'modifier': ?modifier, 'location': at(from)},
    'intersections': [
      {'location': at(from), 'admin_index': admin},
      ...intersections,
    ],
    ...extra,
  };
  return jsonEncode({
    'routes': [
      {
        'geometry': encodePolyline(line),
        'legs': [
          {
            'admins': [
              {'iso_3166_1': 'FR'},
              {'iso_3166_1': 'CH'},
            ],
            'steps': [
              step(
                0,
                10,
                type: 'depart',
                extra: {'ref': 'A 41; E 712'},
                intersections: [
                  {
                    'location': at(6),
                    'admin_index': 0,
                    'classes': ['toll', 'motorway'],
                    'toll_collection': {'type': 'toll_booth'},
                  },
                ],
              ),
              step(
                10,
                30,
                type: 'fork',
                modifier: 'slight left',
                intersections: [
                  {'location': at(18), 'admin_index': 0},
                  {'location': at(19), 'admin_index': 1},
                ],
              ),
              step(
                30,
                40,
                type: 'off ramp',
                modifier: 'slight right',
                admin: 1,
                extra: {'exits': '17', 'destinations': 'A 41: Genève, Chamonix', 'ref': 'A 41'},
              ),
              step(40, 40, type: 'arrive', modifier: 'right', admin: 1),
            ],
          },
        ],
      },
    ],
  });
}

void main() {
  final shape = readOsrmShapes(_answer()).single;

  test('a toll booth and a border are placed along the route, in driving order', () {
    final line = shape.line;
    double along(int i) {
      var m = 0.0;
      for (var k = 1; k <= i; k++) {
        m += line[k - 1].distanceTo(line[k]);
      }
      return m;
    }

    expect(shape.crossings, [
      RouteCrossing(kind: CrossingKind.tollBooth, alongM: along(6), position: line[6]),
      RouteCrossing(
        kind: CrossingKind.border,
        alongM: along(19),
        position: line[19],
        country: 'CH',
      ),
    ]);
  });

  test("a step keeps its road's number, its exit's and what the signs say", () {
    final exit = shape.steps[2];
    expect(exit.exitRef, '17');
    expect(exit.signs, 'A 41: Genève, Chamonix');
    expect(exit.roadRef, 'A 41');
    expect(shape.steps.first.roadRef, 'A 41; E 712');
    expect(shape.steps.first.motorway, isTrue);
    expect(shape.steps[1].motorway, isFalse);
    expect(shape.steps[1].exitRef, isNull);
  });

  test('an answer without admins nor booths passes nothing', () {
    final bare = jsonEncode({
      'routes': [
        {
          'geometry': encodePolyline(const [LatLng(45, 6), LatLng(45.01, 6)]),
          'legs': [
            {
              'steps': [
                {
                  'distance': 1100,
                  'maneuver': {
                    'type': 'depart',
                    'location': [6, 45],
                  },
                  'intersections': [
                    {
                      'location': [6, 45],
                    },
                  ],
                },
              ],
            },
          ],
        },
      ],
    });
    expect(readOsrmShapes(bare).single.crossings, isEmpty);
  });
}
