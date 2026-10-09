import 'package:flutter_test/flutter_test.dart';
import 'package:lunaway/shared/map/pin_painter.dart';

/// The outline of the map pins, the long-press marker and the photo marks:
/// the logo's drop, a circle with two arcs down to the tip that run into it
/// without a corner (brand/README.md, "Construction").
void main() {
  const eps = 1e-9;

  for (final (name, centre, radius, tip) in [
    ('a pin', const Offset(20, 17), 14.5, const Offset(20, 17 + 14.5 * 1.43)),
    (
      'its coloured head, its tip raised under the rim',
      const Offset(20, 17),
      12.5,
      const Offset(20, 17 + 14.5 * 1.43 - 3.2),
    ),
    ('the logo itself', const Offset(227, 227), 227.0, const Offset(227, 552)),
  ]) {
    test('$name: each side touches the circle on its tangent and ends at the tip', () {
      final (:right, :left, :side) = teardropSides(centre, radius, tip);
      expect(side, closeTo(radius * 640 / 227, eps));
      expect(
        (right - centre).distance,
        closeTo(radius, eps),
        reason: 'the shoulder is on the circle',
      );
      expect(
        (left - Offset(2 * centre.dx - right.dx, right.dy)).distance,
        lessThan(eps),
        reason: 'the drop is symmetric',
      );
      // Two circles that touch share the line of their centres: the side's
      // centre lies on the head's radius through the shoulder, inside, at
      // the difference of the radii; and the tip is on the side's circle.
      final across = (right - centre) / radius;
      final sideCentre = centre - across * (side - radius);
      expect((sideCentre - right).distance, closeTo(side, eps));
      expect((sideCentre - tip).distance, closeTo(side, 1e-6));
      expect(right.dy, greaterThan(centre.dy), reason: 'the shoulder is below the middle');
    });
  }

  test('the logo: shoulders where the master drawing has them', () {
    // brand/lunaway-mark.svg: a circle of 227 at (227, 227), arcs of 640
    // meeting at (227, 552).
    final (:right, left: _, side: _) = teardropSides(
      const Offset(227, 227),
      227,
      const Offset(227, 552),
    );
    expect(right.dx, closeTo(227 + 197.0, 0.5));
    expect(right.dy, closeTo(227 + 112.8, 0.5));
  });
}
