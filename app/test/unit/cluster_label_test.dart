import 'package:flutter_test/flutter_test.dart';
import 'package:lunaway/shared/theme/map_look.dart';

/// Evaluates the part of the MapLibre expression language the cluster
/// label uses, with the engines' semantics: `round` takes halves away from
/// zero, `concat` writes integers without a decimal point.
Object _eval(
  Object expr,
  Map<String, num> properties, [
  Map<String, Object> vars = const {},
]) {
  if (expr is! List) return expr;
  final op = expr.first as String;
  Object arg(int i) => _eval(expr[i] as Object, properties, vars);
  num n(int i) => arg(i) as num;
  switch (op) {
    case 'get':
      return properties[expr[1]]!;
    case 'round':
      final v = n(1);
      return v < 0 ? -((-v) + 0.5).floor() : (v + 0.5).floor();
    case 'floor':
      return n(1).floor();
    case '/':
      return n(1) / n(2);
    case '*':
      return n(1) * n(2);
    case '-':
      return n(1) - n(2);
    case '<':
      return n(1) < n(2);
    case '>=':
      return n(1) >= n(2);
    case '==':
      return n(1) == n(2);
    case 'any':
      return [for (var i = 1; i < expr.length; i++) arg(i)]
          .any((v) => v == true);
    case 'concat':
      // Numbers become text as `to-string` writes them: integers without
      // a decimal point.
      return [
        for (var i = 1; i < expr.length; i++)
          switch (arg(i)) {
            final num v =>
              v == v.roundToDouble() ? v.round().toString() : v.toString(),
            final other => other,
          },
      ].join();
    case 'case':
      for (var i = 1; i + 1 < expr.length; i += 2) {
        if (arg(i) == true) return arg(i + 1);
      }
      return arg(expr.length - 1);
  }
  throw UnsupportedError(op);
}

void main() {
  test('the label uses no operator the iOS engine crashes on', () {
    final text = MapLook.clusterLabel('fr').toString();
    for (final op in ['to-string', 'let', 'var', '%']) {
      expect(text, isNot(contains('$op,')), reason: op);
    }
  });

  String label(String language, int count) =>
      _eval(MapLook.clusterLabel(language), {'point_count': count}) as String;

  test('counts under a thousand read as they are', () {
    expect(label('fr', 7), '7');
    expect(label('fr', 999), '999');
  });

  test('thousands follow the French way: a comma and a space before k', () {
    expect(label('fr', 1050), '1,1 k');
    expect(label('fr', 1130), '1,1 k');
    expect(label('fr', 2460), '2,5 k');
    expect(label('fr', 1000), '1 k');
    expect(label('fr', 1020), '1 k');
    expect(label('fr', 9940), '9,9 k');
    expect(label('fr', 9960), '10 k');
    expect(label('fr', 15256), '15 k');
  });

  test('and the English way in English', () {
    expect(label('en', 1130), '1.1k');
    expect(label('en', 2460), '2.5k');
    expect(label('en', 15256), '15k');
  });
}
