// The MapLibre expressions of the app's layers, evaluated in Dart so a
// test can check what a filter keeps without an engine.

/// Evaluates the part of the MapLibre expression language the places'
/// filters use, with the engines' semantics: `get` of a missing property is
/// null, `==` of values of different types is false, `>=` on a null fails
/// the feature (an error in a filter keeps nothing), `match` compares its
/// input with each label or list of labels.
Object? evalStyleExpression(Object? expr, Map<String, Object> properties) {
  if (expr is! List) return expr;
  final op = expr.first as String;
  Object? arg(int i) => evalStyleExpression(expr[i], properties);
  num n(int i) => switch (arg(i)) {
    final num v => v,
    _ => throw const _Fails(),
  };
  switch (op) {
    case 'get':
      return properties[expr[1]];
    case 'has':
      return properties.containsKey(expr[1]);
    case '!':
      return arg(1) != true;
    // Both stop at the first argument that decides, as the engines do.
    case 'all':
      for (var i = 1; i < expr.length; i++) {
        if (arg(i) != true) return false;
      }
      return true;
    case 'any':
      for (var i = 1; i < expr.length; i++) {
        if (arg(i) == true) return true;
      }
      return false;
    case 'coalesce':
      for (var i = 1; i < expr.length; i++) {
        final v = arg(i);
        if (v != null) return v;
      }
      return null;
    case 'match':
      final input = arg(1);
      for (var i = 2; i + 1 < expr.length; i += 2) {
        final label = expr[i];
        if (label is List ? label.contains(input) : label == input) return arg(i + 1);
      }
      return arg(expr.length - 1);
    case '==':
      final a = arg(1);
      final b = arg(2);
      return (a.runtimeType == b.runtimeType || (a is num && b is num)) && a == b;
    case '>=':
      return n(1) >= n(2);
    case '/':
      return n(1) / n(2);
    case '*':
      return n(1) * n(2);
    case '-':
      return n(1) - n(2);
    case 'floor':
      return n(1).floor();
  }
  throw UnsupportedError(op);
}

class _Fails implements Exception {
  const new();
}

/// Whether [filter] keeps a feature of [properties]; a filter that fails
/// keeps nothing, as on the engines.
bool styleFilterKeeps(List<Object> filter, Map<String, Object> properties) {
  try {
    return evalStyleExpression(filter, properties) == true;
  } on _Fails {
    return false;
  }
}
