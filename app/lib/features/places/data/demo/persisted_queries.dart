import 'dart:convert';

import 'package:crypto/crypto.dart';

/// The server's side of Apollo's persisted queries (docs/region-packs.md),
/// for the in-process stand-ins of the API: the demo server and the tests'
/// fake API answer a request that names its document by its SHA-256 the
/// way the API does, so the client's handling runs against them too.
final class PersistedQueryStore {
  final Map<String, String> _documents = {};

  /// How many requests named a document by its hash alone and found it.
  int hits = 0;

  /// The document [body] runs: its `query`, kept under its hash when the
  /// body names one; null when the body names only a hash this store does
  /// not know (answer [notFound]). Throws a [FormatException] when the
  /// `query` sent does not hash to the hash named (the API refuses it).
  String? documentOf(Map<String, dynamic> body) {
    final query = body['query'];
    final extensions = body['extensions'];
    final persisted = extensions is Map<String, dynamic> ? extensions['persistedQuery'] : null;
    final hash = persisted is Map<String, dynamic> ? persisted['sha256Hash'] : null;
    if (hash is! String) return query is String ? query : '';
    if (query is String) {
      if (sha256.convert(utf8.encode(query)).toString() != hash) {
        throw const FormatException('the query does not hash to sha256Hash');
      }
      _documents[hash] = query;
      return query;
    }
    final known = _documents[hash];
    if (known != null) hits++;
    return known;
  }

  /// Forgets every document, as the API does on a restart.
  void clear() => _documents.clear();

  /// The answer to a hash the store does not know.
  static Map<String, Object?> get notFound => {
    'data': null,
    'errors': [
      {
        'message': 'PersistedQueryNotFound',
        'extensions': {'code': 'PERSISTED_QUERY_NOT_FOUND'},
      },
    ],
  };

  /// The answer to a query that does not hash to the hash named.
  static Map<String, Object?> get mismatch => {
    'data': null,
    'errors': [
      {
        'message': 'the query does not hash to sha256Hash',
        'extensions': {'code': 'INVALID_INPUT'},
      },
    ],
  };
}
