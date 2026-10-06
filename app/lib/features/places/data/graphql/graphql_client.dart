import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:logging/logging.dart';
import 'package:lunaway/features/places/data/graphql/operations.dart';

final _log = Logger('graphql');

/// A small GraphQL-over-HTTP client: one JSON POST per operation (the API
/// refuses batches and every other transport), typed results parsed by the
/// operation itself. No cache, no normalisation: drift is the offline store,
/// so the client only moves pages.
final class GraphQLClient {
  new({
    required this.endpoint,
    required http.Client httpClient,
    required this.userAgent,
    this.timeout = const Duration(seconds: 30),
    this.rateLimitRetries = 3,
    this.maxRateLimitWait = const Duration(seconds: 60),
    Future<void> Function(Duration wait)? sleep,
  }) : _http = httpClient,
       _sleep = sleep ?? Future<void>.delayed;

  final Uri endpoint;
  final String userAgent;
  final Duration timeout;

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
  Future<T> execute<T>(
    GraphQLOperation<T> operation, [
    Map<String, Object?> variables = const {},
    Map<String, String> headers = const {},
  ]) async {
    try {
      return await _execute(operation, operation.document, variables, headers);
    } on GraphQLResponseException catch (e) {
      final older = operation.older;
      if (older == null ||
          !older.usable(variables) ||
          !e.errors.any((error) => error.unknownInput)) {
        rethrow;
      }
      _log.info('${operation.name}: the API does not know all of it yet, sent in its older form');
      return await _execute(operation, older.document, older.variables(variables), headers);
    }
  }

  Future<T> _execute<T>(
    GraphQLOperation<T> operation,
    String document,
    Map<String, Object?> variables,
    Map<String, String> headers,
  ) async {
    final body = jsonEncode({
      'operationName': operation.name,
      'query': document,
      'variables': variables,
    });
    final sent = {
      ...headers,
      'content-type': 'application/json',
      'accept': 'application/graphql-response+json, application/json',
      // Browsers refuse a script-set User-Agent and log an error for it.
      if (!kIsWeb) 'user-agent': userAgent,
    };
    for (var attempt = 0; ; attempt++) {
      final response = await _post(sent, body);
      final decoded = _decode(response);
      final wait = _rateLimitWait(response, decoded);
      if (wait != null) {
        if (attempt >= rateLimitRetries || wait > maxRateLimitWait) {
          throw GraphQLRateLimitedException(wait);
        }
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

  Future<http.Response> _post(Map<String, String> headers, String body) async {
    try {
      return await _http.post(endpoint, headers: headers, body: body).timeout(timeout);
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
