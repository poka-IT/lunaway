import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:logging/logging.dart';
import 'package:lunaway/features/places/data/graphql/operations.dart';

final _log = Logger('graphql');

/// A small GraphQL-over-HTTP client: one JSON POST per operation (the API
/// refuses batches and every other transport), typed results parsed by the
/// operation itself. No cache, no normalisation: drift is the offline store,
/// so the client only moves pages.
///
/// With [persistedQueries], a request carries the SHA-256 of its document
/// instead of the document (Apollo's persisted queries, docs/region-packs.md):
/// the server runs the document it knows under that hash, or answers
/// `PERSISTED_QUERY_NOT_FOUND`, and the request goes again with its
/// document. An API that refuses a request without a document gets every
/// document whole for the rest of the run.
final class GraphQLClient {
  new({
    required this.endpoint,
    required http.Client httpClient,
    required this.userAgent,
    this.timeout = const Duration(seconds: 30),
    this.rateLimitRetries = 3,
    this.maxRateLimitWait = const Duration(seconds: 60),
    this.persistedQueries = false,
    Future<void> Function(Duration wait)? sleep,
  }) : _http = httpClient,
       _sleep = sleep ?? Future<void>.delayed;

  final Uri endpoint;
  final String userAgent;
  final Duration timeout;

  /// Sends the hash of a document before the document itself.
  final bool persistedQueries;

  /// The SHA-256 of each document sent, computed once.
  final Map<String, String> _hashes = {};

  /// The server refused a request without its document: an API without
  /// persisted queries, which gets every document whole from then on.
  bool _wholeDocuments = false;

  /// How many times a request the server rate-limited is sent again, after
  /// the wait it asks for, before the client gives up for now.
  final int rateLimitRetries;

  /// The longest wait the client accepts from the server before giving up
  /// for now; a longer one would leave the user staring at a spinner.
  final Duration maxRateLimitWait;
  final http.Client _http;
  final Future<void> Function(Duration wait) _sleep;

  /// Sends [operation]; [headers] add to the request's (a session's
  /// `Authorization`). An API older than the operation, which refuses an
  /// argument or an input field it does not know, gets its older form: a
  /// document the server did not validate ran nothing, so sending another
  /// one is safe.
  ///
  /// [abort], once complete, cancels the request in flight: a search the
  /// user typed past.
  Future<T> execute<T>(
    GraphQLOperation<T> operation, [
    Map<String, Object?> variables = const {},
    Map<String, String> headers = const {},
    Future<void>? abort,
  ]) async {
    try {
      return await _execute(operation, operation.document, variables, headers, abort);
    } on GraphQLResponseException catch (e, stack) {
      var refusal = e;
      var trace = stack;
      // Each refusal of an unknown field or argument tries the next older
      // form, until one passes or none is left.
      var next = operation.older;
      while (next != null && _callsFor(next, refusal, variables)) {
        final form = next;
        _log.info('${operation.name}: the API does not know all of it yet, sent in an older form');
        try {
          return await _execute(
            operation,
            form.document,
            form.variables(variables),
            headers,
            abort,
          );
        } on GraphQLResponseException catch (again, stack) {
          refusal = again;
          trace = stack;
          next = form.older;
        }
      }
      Error.throwWithStackTrace(refusal, trace);
    }
  }

  /// Whether [refusal] is one [form] answers: an argument, or a field
  /// when the form leaves fields out, that the API does not know.
  static bool _callsFor(
    OlderForm form,
    GraphQLResponseException refusal,
    Map<String, Object?> variables,
  ) =>
      form.usable(variables) &&
      refusal.errors.any(
        (error) => error.unknownInput || (form.withoutFields && error.unknownField),
      );

  Future<T> _execute<T>(
    GraphQLOperation<T> operation,
    String document,
    Map<String, Object?> variables,
    Map<String, String> headers, [
    Future<void>? abort,
  ]) async {
    final hash = persistedQueries && !_wholeDocuments
        ? _hashes.putIfAbsent(document, () => sha256.convert(utf8.encode(document)).toString())
        : null;
    // The hash alone first; the document goes with it once the server asks.
    var withDocument = hash == null;
    // Decided for this request alone: another one finding the server
    // without persisted queries must not strip this one of both forms.
    var whole = hash == null;
    String body() => jsonEncode({
      'operationName': operation.name,
      if (withDocument) 'query': document,
      'variables': variables,
      if (!whole)
        'extensions': {
          'persistedQuery': {'version': 1, 'sha256Hash': hash},
        },
    });
    final sent = {
      ...headers,
      'content-type': 'application/json',
      'accept': 'application/graphql-response+json, application/json',
      // Browsers refuse a script-set User-Agent and log an error for it.
      if (!kIsWeb) 'user-agent': userAgent,
    };
    for (var limited = 0; ;) {
      final response = await _post(sent, body(), abort);
      final decoded = _decode(response);
      if (!withDocument) {
        if (_hashUnknown(decoded)) {
          withDocument = true;
          continue;
        }
        if (_documentRequired(response, decoded)) {
          _log.info('the API does not take persisted queries: documents go whole');
          _wholeDocuments = true;
          whole = true;
          withDocument = true;
          continue;
        }
      }
      final wait = _rateLimitWait(response, decoded);
      if (wait != null) {
        if (limited >= rateLimitRetries || wait > maxRateLimitWait) {
          throw GraphQLRateLimitedException(wait);
        }
        limited++;
        _log.info('${operation.name}: rate limited, trying again in ${wait.inSeconds} s');
        await _sleep(wait);
        continue;
      }
      if (decoded == null) {
        throw GraphQLNetworkException('HTTP ${response.statusCode}, body is not JSON', null);
      }
      final errors = decoded['errors'];
      if (errors is List && errors.isNotEmpty) {
        final parsed = [for (final e in errors) GraphQLError.fromJson(e)];
        _log.warning('${operation.name}: ${parsed.join('; ')}');
        throw GraphQLResponseException(parsed);
      }
      final data = decoded['data'];
      if (response.statusCode != 200 || data is! Map<String, dynamic>) {
        throw GraphQLNetworkException('HTTP ${response.statusCode} without data', null);
      }
      return operation.parse(data);
    }
  }

  /// The server does not know the hash: it restarted, or never kept the
  /// document. The same request with its document runs and teaches it.
  static bool _hashUnknown(Map<String, dynamic>? decoded) {
    final errors = decoded?['errors'];
    return errors is List &&
        errors.map(GraphQLError.fromJson).any((e) => e.code == GraphQLError.persistedQueryNotFound);
  }

  /// An API without persisted queries refuses a body without `query`
  /// (HTTP 400, `INVALID_INPUT`, read on production on 2026-10-06).
  static bool _documentRequired(http.Response response, Map<String, dynamic>? decoded) {
    final errors = decoded?['errors'];
    return response.statusCode == 400 &&
        decoded?['data'] == null &&
        errors is List &&
        errors
            .map(GraphQLError.fromJson)
            .any((e) => e.code == GraphQLError.invalidInput && e.message.contains('`query`'));
  }

  Future<http.Response> _post(Map<String, String> headers, String body, Future<void>? abort) async {
    try {
      if (abort == null) {
        return await _http.post(endpoint, headers: headers, body: body).timeout(timeout);
      }
      final request = http.AbortableRequest('POST', endpoint, abortTrigger: abort)
        ..headers.addAll(headers)
        ..body = body;
      Future<http.Response> sent() async =>
          await http.Response.fromStream(await _http.send(request));
      return await sent().timeout(timeout);
    } on TimeoutException catch (e) {
      throw GraphQLNetworkException('timeout after ${timeout.inSeconds} s', e);
    } on http.ClientException catch (e) {
      throw GraphQLNetworkException(e.message, e);
    }
  }

  /// The JSON object of the body, or null when the body is something else
  /// (a proxy's error page).
  static Map<String, dynamic>? _decode(http.Response response) {
    try {
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      return decoded is Map<String, dynamic> ? decoded : null;
    } on FormatException {
      return null;
    }
  }

  /// How long the server asks to wait, when it refused the request for its
  /// rate: `extensions.retryAfterSeconds` of a `RATE_LIMITED` error, else
  /// the `Retry-After` header of a 429 or 503.
  static Duration? _rateLimitWait(http.Response response, Map<String, dynamic>? decoded) {
    final errors = decoded?['errors'];
    final limited = errors is List
        ? errors
              .map(GraphQLError.fromJson)
              .where((e) => e.code == GraphQLError.rateLimited)
              .firstOrNull
        : null;
    final header = int.tryParse(response.headers['retry-after'] ?? '');
    if (limited == null &&
        !((response.statusCode == 429 || response.statusCode == 503) && header != null)) {
      return null;
    }
    final seconds = limited?.retryAfterSeconds ?? header ?? 1;
    return Duration(seconds: seconds < 1 ? 1 : seconds);
  }
}

/// One error of a GraphQL response, with the code the API puts in
/// `extensions.code` so the client can act on it.
@immutable
final class GraphQLError {
  const new(
    this.message, {
    this.code,
    this.retryAfterSeconds,
    this.reason,
    this.requiredLevel,
    this.level,
    this.existingId,
  });

  factory fromJson(Object? json) {
    if (json is! Map<String, dynamic>) return GraphQLError('$json');
    final extensions = json['extensions'];
    final ext = extensions is Map<String, dynamic> ? extensions : const <String, dynamic>{};
    return GraphQLError(
      '${json['message']}',
      code: ext['code'] as String?,
      retryAfterSeconds: (ext['retryAfterSeconds'] as num?)?.toInt(),
      reason: ext['reason'] as String?,
      requiredLevel: (ext['requiredLevel'] as num?)?.toInt(),
      level: (ext['level'] as num?)?.toInt(),
      existingId: ext['existingId'] as String?,
    );
  }

  /// The request asks too much or is malformed: fix it, do not resend it.
  static const invalidInput = 'INVALID_INPUT';

  /// Wait `retryAfterSeconds`, then send again.
  static const rateLimited = 'RATE_LIMITED';

  /// The sync cursor belongs to another copy of the change feed: drop it and
  /// sync from scratch.
  static const resync = 'RESYNC';

  /// The server does not know the hash of a persisted query: send the
  /// document with it.
  static const persistedQueryNotFound = 'PERSISTED_QUERY_NOT_FOUND';

  /// The server failed; try again later.
  static const internal = 'INTERNAL';

  /// A service behind the API is down; the request was fine, try it again
  /// later.
  static const unavailable = 'UNAVAILABLE';

  /// No session, or one the server no longer knows: sign in again. With
  /// [reason] [freshSignIn], the action needs a session opened by a signed
  /// sign-in in the last ten minutes.
  static const unauthenticated = 'UNAUTHENTICATED';
  static const freshSignIn = 'FRESH_SIGN_IN';

  /// The account may not do this: its level is below [requiredLevel], or
  /// it is banned.
  static const forbidden = 'FORBIDDEN';

  /// What was asked for does not exist, or is not the caller's.
  static const notFound = 'NOT_FOUND';

  /// [reason] of a [notFound] sign-in that may not create: the server knows
  /// no account behind the key.
  static const unknownKey = 'UNKNOWN_KEY';

  final String message;
  final String? code;
  final int? retryAfterSeconds;
  final String? reason;
  final int? requiredLevel;
  final int? level;

  /// With [invalidInput]: what the request would duplicate (a vending
  /// machine of the same kind within 25 m), to act on that one instead.
  final String? existingId;

  /// The server does not know an argument or an input field of the request
  /// (async-graphql's validation messages): an API older than the app.
  bool get unknownInput =>
      code == invalidInput &&
      (message.startsWith('Unknown argument ') || message.contains(', unknown field '));

  /// The server does not know a field the request selects: an API older
  /// than the app, or one without a whole operation. The document was
  /// refused before it ran.
  bool get unknownField => code == invalidInput && message.startsWith('Unknown field ');

  @override
  String toString() => code == null ? message : '$code: $message';
}

/// The request did not complete: offline, timeout, server down, not JSON.
/// Worth retrying later.
base class GraphQLNetworkException implements Exception {
  new(this.message, this.cause);

  final String message;
  final Object? cause;

  @override
  String toString() => 'GraphQLNetworkException: $message';
}

/// The server kept refusing the request for its rate, or asked for a wait
/// longer than the client accepts: like being offline, worth retrying later.
final class GraphQLRateLimitedException extends GraphQLNetworkException {
  new(this.wait) : super('rate limited, retry after ${wait.inSeconds} s', null);

  final Duration wait;
}

/// The server answered with GraphQL errors: retrying the same request will
/// not help, except where a code says what to do instead ([transient],
/// `RESYNC`).
final class GraphQLResponseException implements Exception {
  new(this.errors);

  final List<GraphQLError> errors;

  List<String> get messages => [for (final e in errors) e.message];

  bool hasCode(String code) => errors.any((e) => e.code == code);

  /// The first error with [code], if any.
  GraphQLError? withCode(String code) => errors.where((e) => e.code == code).firstOrNull;

  /// Every error says the server failed or a service behind it is down: the
  /// same request is worth sending again later.
  bool get transient =>
      errors.isNotEmpty &&
      errors.every((e) => e.code == GraphQLError.internal || e.code == GraphQLError.unavailable);

  @override
  String toString() => 'GraphQLResponseException: ${errors.join('; ')}';
}
