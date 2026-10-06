import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lunaway/features/places/data/graphql/operations.dart';

import 'graphql_validator.dart';

/// Fields the app already reads that the server has not exported yet: the
/// community content of the contract (descriptions, ratings, links, photos,
/// reviews), served by the demo fixture until then. An operation may miss
/// these and nothing else; once the schema declares one, the test asks for
/// its removal here, so the list only shrinks.
const pendingServerFields = {
  ('Place', 'descriptions'),
  ('Place', 'ratings'),
  ('Place', 'externalLinks'),
  ('Place', 'photos'),
  ('Place', 'reviews'),
};

final _missingField = RegExp(r'(\w+) has no field "(\w+)"$');

/// Every operation the app sends must be valid against the schema the
/// server exports (`schema/lunaway.graphql`): when either side changes, this
/// test names the field that drifted.
void main() {
  final schema = File('../schema/lunaway.graphql').readAsStringSync();
  final validator = SchemaValidator(schema);

  test('the app sends at least the sync operation', () {
    expect(allOperations.map((o) => o.name), contains('Changes'));
  });

  for (final op in allOperations) {
    test('${op.name} is valid against schema/lunaway.graphql', () {
      final all = validator.validate(op.document);
      bool pending(String e) => switch (_missingField.firstMatch(e)) {
        final m? => pendingServerFields.contains((m[1], m[2])),
        null => false,
      };
      // A variable used only under a pending field reads as unused.
      final waiting = all.any(pending);
      final errors = all.where(
        (e) => !pending(e) && !(waiting && e.endsWith('is declared but never used')),
      );
      expect(errors, isEmpty);
    });
  }

  test('no field stays pending once the schema has it', () {
    final landed = [
      for (final (type, field) in pendingServerFields)
        if (validator.hasField(type, field)) '$type.$field',
    ];
    expect(landed, isEmpty, reason: 'remove them from pendingServerFields');
  });

  group('the validator itself', () {
    final v = SchemaValidator('''
      schema { query: Root }
      type Root { thing(id: ID!, n: Int = 3): Thing things(first: Int): [Thing!]! version: String! }
      type Thing { id: ID! name: String child: Thing }
    ''');

    test('accepts a valid operation', () {
      expect(
        v.validate(r'query Q($id: ID!) { version thing(id: $id) { id name child { id } } }'),
        isEmpty,
      );
    });

    test('names an unknown field', () {
      expect(v.validate('query Q { version colour }'), ['Q: Root has no field "colour"']);
    });

    test('names a missing required argument and an unknown one', () {
      expect(v.validate('query Q { thing(nope: 1) { id } }'), [
        'Q.thing: no argument "nope"',
        'Q.thing: required argument "id" is missing',
      ]);
    });

    test('refuses a nullable variable for a required argument', () {
      expect(v.validate(r'query Q($id: ID) { thing(id: $id) { id } }'), [
        r'Q.thing: $id is ID, argument "id" wants ID!',
      ]);
    });

    test('refuses a missing selection, a selection on a leaf, an unused variable', () {
      expect(v.validate(r'query Q($n: Int) { things version { x } }'), [
        'Q.things: Thing needs a selection',
        'Q.version: String is a leaf and takes no selection',
        r'Q: variable $n is declared but never used',
      ]);
    });

    test('checks fragments against their type', () {
      expect(v.validate('query Q { things { ...F } } fragment F on Thing { id size }'), [
        'Q.things{F}: Thing has no field "size"',
      ]);
    });
  });
}
