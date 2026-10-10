import 'package:gql/ast.dart';
import 'package:gql/language.dart';

/// A small GraphQL validator: checks an operation against a schema in SDL
/// for what can drift between the app and the server. Every field exists on
/// its type, every argument exists and the required ones are given,
/// variables are declared, used, and typed compatibly with the arguments
/// they feed, and selections are present exactly on object types. It also
/// checks values: the variables a request sends ([checkVariables]) and the
/// data a response carries ([checkResponse]), so a stand-in server (the
/// demo) cannot drift from what the real one accepts and sends.
final class SchemaValidator {
  new(String sdl) {
    final doc = parseString(sdl);
    for (final d in doc.definitions) {
      if (d is TypeDefinitionNode) _types[d.name.value] = d;
      if (d is SchemaDefinitionNode) {
        for (final op in d.operationTypes) {
          _roots[op.operation] = op.type.name.value;
        }
      }
    }
    _roots.putIfAbsent(OperationType.query, () => 'Query');
  }

  final Map<String, TypeDefinitionNode> _types = {};
  final Map<OperationType, String> _roots = {};

  static const _builtInScalars = {'String', 'Int', 'Float', 'Boolean', 'ID'};

  /// Whether the schema declares [field] on the object or interface [type].
  bool hasField(String type, String field) => switch (_types[type]) {
    ObjectTypeDefinitionNode(:final fields) ||
    InterfaceTypeDefinitionNode(
      :final fields,
    ) => fields.any((f) => f.name.value == field),
    _ => false,
  };

  /// Problems found in [document]; empty when it is valid.
  List<String> validate(String document) {
    final doc = parseString(document);
    final errors = <String>[];
    final fragments = {
      for (final d in doc.definitions.whereType<FragmentDefinitionNode>())
        d.name.value: d,
    };
    for (final op in doc.definitions.whereType<OperationDefinitionNode>()) {
      final opName = op.name?.value ?? '<anonymous>';
      final root = _roots[op.type];
      if (root == null || !_types.containsKey(root)) {
        errors.add('$opName: the schema has no ${op.type.name} root');
        continue;
      }
      final declared = {
        for (final v in op.variableDefinitions) v.variable.name.value: v.type,
      };
      for (final e in declared.entries) {
        final named = _named(e.value);
        if (!_builtInScalars.contains(named) && !_types.containsKey(named)) {
          errors.add('$opName: variable \$${e.key} has unknown type $named');
        }
      }
      final used = <String>{};
      _selections(
        op.selectionSet,
        root,
        opName,
        declared,
        used,
        fragments,
        errors,
        {},
      );
      for (final v in declared.keys.where((v) => !used.contains(v))) {
        errors.add('$opName: variable \$$v is declared but never used');
      }
    }
    return errors;
  }

  void _selections(
    SelectionSetNode set,
    String typeName,
    String path,
    Map<String, TypeNode> declared,
    Set<String> used,
    Map<String, FragmentDefinitionNode> fragments,
    List<String> errors,
    Set<String> visiting,
  ) {
    final type = _types[typeName];
    final fields = switch (type) {
      ObjectTypeDefinitionNode(:final fields) => fields,
      InterfaceTypeDefinitionNode(:final fields) => fields,
      _ => const <FieldDefinitionNode>[],
    };
    for (final selection in set.selections) {
      switch (selection) {
        case FieldNode(:final name, :final arguments, selectionSet: final sub):
          final fieldName = name.value;
          if (fieldName == '__typename') continue;
          final def = fields
              .where((f) => f.name.value == fieldName)
              .firstOrNull;
          if (def == null) {
            errors.add('$path: $typeName has no field "$fieldName"');
            continue;
          }
          final here = '$path.$fieldName';
          for (final arg in arguments) {
            final argDef = def.args
                .where((a) => a.name.value == arg.name.value)
                .firstOrNull;
            if (argDef == null) {
              errors.add('$here: no argument "${arg.name.value}"');
              continue;
            }
            final value = arg.value;
            if (value is VariableNode) {
              final varName = value.name.value;
              used.add(varName);
              final varType = declared[varName];
              if (varType == null) {
                errors.add('$here: variable \$$varName is not declared');
              } else if (!_compatible(
                varType,
                argDef.type,
                hasDefault: argDef.defaultValue != null,
              )) {
                errors.add(
                  '$here: \$$varName is ${_print(varType)}, argument "${arg.name.value}" wants ${_print(argDef.type)}',
                );
              }
            }
          }
          for (final argDef in def.args) {
            final required =
                argDef.type.isNonNull && argDef.defaultValue == null;
            if (required &&
                !arguments.any((a) => a.name.value == argDef.name.value)) {
              errors.add(
                '$here: required argument "${argDef.name.value}" is missing',
              );
            }
          }
          final inner = _named(def.type);
          final composite =
              _types[inner] is ObjectTypeDefinitionNode ||
              _types[inner] is InterfaceTypeDefinitionNode;
          if (composite && sub == null)
            errors.add('$here: $inner needs a selection');
          if (!composite && sub != null) {
            errors.add('$here: $inner is a leaf and takes no selection');
          }
          if (composite && sub != null) {
            _selections(
              sub,
              inner,
              here,
              declared,
              used,
              fragments,
              errors,
              visiting,
            );
          }
        case FragmentSpreadNode(:final name):
          final fragment = fragments[name.value];
          if (fragment == null) {
            errors.add('$path: fragment ${name.value} is not defined');
            continue;
          }
          final on = fragment.typeCondition.on.name.value;
          if (on != typeName) {
            errors.add(
              '$path: fragment ${name.value} is on $on, used on $typeName',
            );
          }
          if (!visiting.add(name.value)) continue;
          _selections(
            fragment.selectionSet,
            on,
            '$path{${name.value}}',
            declared,
            used,
            fragments,
            errors,
            visiting,
          );
          visiting.remove(name.value);
        case InlineFragmentNode(:final typeCondition, selectionSet: final sub):
          _selections(
            sub,
            typeCondition?.on.name.value ?? typeName,
            path,
            declared,
            used,
            fragments,
            errors,
            visiting,
          );
      }
    }
  }

  /// Custom scalars and how a value of each is written on the wire. A
  /// scalar the schema adds without a rule here is reported, so the check
  /// never passes a value it does not understand.
  static final Map<String, bool Function(Object)> _scalars = {
    'UUID': (v) =>
        v is String &&
        RegExp(
          r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
        ).hasMatch(v),
    'DateTime': (v) =>
        v is String && v.contains('T') && DateTime.tryParse(v) != null,
    'NaiveDate': (v) =>
        v is String && RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(v),
  };

  /// Problems in [variables], the values a request sends with [document]:
  /// each must have its declared type, as the server parses it.
  List<String> checkVariables(String document, Map<String, Object?> variables) {
    final errors = <String>[];
    for (final op in parseString(
      document,
    ).definitions.whereType<OperationDefinitionNode>()) {
      for (final v in op.variableDefinitions) {
        final name = v.variable.name.value;
        _input(v.type, variables[name], '\$$name', errors);
      }
    }
    return errors;
  }

  void _input(TypeNode type, Object? value, String path, List<String> errors) {
    if (value == null) {
      if (type.isNonNull) errors.add('$path: null for ${_print(type)}');
      return;
    }
    switch (type) {
      case ListTypeNode(type: final item):
        if (value is! List) {
          errors.add('$path: not a list');
          return;
        }
        for (var i = 0; i < value.length; i++) {
          _input(item, value[i], '$path[$i]', errors);
        }
      case NamedTypeNode(:final name):
        switch (_types[name.value]) {
          case InputObjectTypeDefinitionNode(:final fields):
            if (value is! Map) {
              errors.add('$path: not an object');
              return;
            }
            for (final key in value.keys.where(
              (k) => !fields.any((f) => f.name.value == k),
            )) {
              errors.add('$path: ${name.value} has no field "$key"');
            }
            for (final f in fields) {
              // A field left out takes its default, as the server reads it.
              if (f.defaultValue != null && !value.containsKey(f.name.value))
                continue;
              _input(
                f.type,
                value[f.name.value],
                '$path.${f.name.value}',
                errors,
              );
            }
          default:
            _leaf(name.value, value, path, errors);
        }
      default:
        errors.add('$path: unexpected type');
    }
  }

  /// Problems in [data], the `data` of a response to [document]: a selected
  /// field missing, a value of the wrong shape, an enum value the schema
  /// does not list, a null where the schema promises a value.
  List<String> checkResponse(String document, Map<String, dynamic> data) {
    final doc = parseString(document);
    final fragments = {
      for (final d in doc.definitions.whereType<FragmentDefinitionNode>())
        d.name.value: d,
    };
    final errors = <String>[];
    for (final op in doc.definitions.whereType<OperationDefinitionNode>()) {
      final root = _roots[op.type];
      if (root == null) continue;
      _object(
        op.selectionSet,
        root,
        data,
        op.name?.value ?? '<anonymous>',
        fragments,
        errors,
      );
    }
    return errors;
  }

  void _object(
    SelectionSetNode set,
    String typeName,
    Map<String, dynamic> value,
    String path,
    Map<String, FragmentDefinitionNode> fragments,
    List<String> errors,
  ) {
    final fields = switch (_types[typeName]) {
      ObjectTypeDefinitionNode(:final fields) => fields,
      InterfaceTypeDefinitionNode(:final fields) => fields,
      _ => const <FieldDefinitionNode>[],
    };
    for (final selection in set.selections) {
      switch (selection) {
        case FieldNode(:final name, :final alias, selectionSet: final sub):
          if (name.value == '__typename') continue;
          final def = fields
              .where((f) => f.name.value == name.value)
              .firstOrNull;
          // An unknown field is validate()'s finding; nothing to compare.
          if (def == null) continue;
          final key = alias?.value ?? name.value;
          if (!value.containsKey(key)) {
            errors.add('$path.$key: missing');
            continue;
          }
          _output(def.type, value[key], sub, '$path.$key', fragments, errors);
        case FragmentSpreadNode(:final name):
          final fragment = fragments[name.value];
          if (fragment == null) continue;
          _object(
            fragment.selectionSet,
            fragment.typeCondition.on.name.value,
            value,
            path,
            fragments,
            errors,
          );
        case InlineFragmentNode(:final typeCondition, selectionSet: final sub):
          _object(
            sub,
            typeCondition?.on.name.value ?? typeName,
            value,
            path,
            fragments,
            errors,
          );
      }
    }
  }

  void _output(
    TypeNode type,
    Object? value,
    SelectionSetNode? sub,
    String path,
    Map<String, FragmentDefinitionNode> fragments,
    List<String> errors,
  ) {
    if (value == null) {
      if (type.isNonNull) errors.add('$path: null for ${_print(type)}');
      return;
    }
    switch (type) {
      case ListTypeNode(type: final item):
        if (value is! List) {
          errors.add('$path: not a list');
          return;
        }
        for (var i = 0; i < value.length; i++) {
          _output(item, value[i], sub, '$path[$i]', fragments, errors);
        }
      case NamedTypeNode(:final name):
        switch (_types[name.value]) {
          case ObjectTypeDefinitionNode() || InterfaceTypeDefinitionNode():
            if (value is! Map<String, dynamic> || sub == null) {
              errors.add('$path: not an object');
              return;
            }
            _object(sub, name.value, value, path, fragments, errors);
          default:
            _leaf(name.value, value, path, errors);
        }
      default:
        errors.add('$path: unexpected type');
    }
  }

  void _leaf(String type, Object value, String path, List<String> errors) {
    final ok = switch (_types[type]) {
      EnumTypeDefinitionNode(:final values) => values.any(
        (v) => v.name.value == value,
      ),
      _ => switch (type) {
        'Int' => value is int,
        'Float' => value is num,
        'Boolean' => value is bool,
        'String' || 'ID' => value is String,
        _ => _scalars[type]?.call(value),
      },
    };
    if (ok == null) {
      errors.add(
        '$path: no rule for the scalar $type, add one to the validator',
      );
    } else if (!ok) {
      errors.add('$path: $value is not a $type');
    }
  }

  /// A variable of [variable] type may feed an argument of [argument] type:
  /// same named type, at least as strict on nulls, same list nesting.
  static bool _compatible(
    TypeNode variable,
    TypeNode argument, {
    required bool hasDefault,
  }) {
    if (argument.isNonNull && !variable.isNonNull && !hasDefault) return false;
    return switch ((variable, argument)) {
      (final NamedTypeNode v, final NamedTypeNode a) =>
        v.name.value == a.name.value,
      (final ListTypeNode v, final ListTypeNode a) => _compatible(
        v.type,
        a.type,
        hasDefault: false,
      ),
      _ => false,
    };
  }

  static String _named(TypeNode t) => switch (t) {
    NamedTypeNode(:final name) => name.value,
    ListTypeNode(:final type) => _named(type),
    _ => '?',
  };

  static String _print(TypeNode t) => switch (t) {
    NamedTypeNode(:final name, :final isNonNull) =>
      '${name.value}${isNonNull ? '!' : ''}',
    ListTypeNode(:final type, :final isNonNull) =>
      '[${_print(type)}]${isNonNull ? '!' : ''}',
    _ => '?',
  };
}
