import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:lunaway/features/places/data/graphql/place_json.dart';
import 'package:lunaway/features/places/domain/place_content.dart';

/// The server refused an upload, or it did not complete.
final class UploadException implements Exception {
  const new(
    this.status,
    this.message, {
    this.code,
    this.requiredLevel,
    this.retryAfter,
  });

  /// The HTTP status; 0 when no answer came (offline, timeout).
  final int status;
  final String message;

  /// The error code of the API (`FORBIDDEN`, `INVALID_INPUT`...).
  final String? code;
  final int? requiredLevel;
  final Duration? retryAfter;

  /// Worth sending again later: no answer, a full server, a spent budget.
  bool get transient =>
      status == 0 || status == 429 || status == 408 || status >= 500;

  @override
  String toString() =>
      'UploadException($status${code == null ? '' : ' $code'}): $message';
}

/// Sends a photo to `POST /upload` as the API takes it: a multipart form
/// with `placeId` and `file`, the session in `Authorization`. The body is
/// handed to the socket a chunk at a time, so [upload]'s progress follows
/// what has left the device (the browser sends it whole: its progress jumps
/// to the end).
final class PhotoUploader {
  new({
    required this._client,
    required this.endpoint,
    required this.userAgent,
    this.timeout = const Duration(seconds: 120),
    this.chunk = 32 * 1024,
  });

  final http.Client _client;
  final Uri endpoint;
  final String userAgent;
  final Duration timeout;
  final int chunk;

  Future<Photo> upload({
    required String placeId,
    required Uint8List jpeg,
    required Map<String, String> headers,
    void Function(double sent)? onProgress,
  }) async {
    // Bytes, not one large integer: `1 << 32` is 0 once compiled to
    // JavaScript, and the browser build would refuse every photo.
    final random = Random.secure();
    final boundary =
        'lunaway-${[for (var i = 0; i < 16; i++) random.nextInt(256).toRadixString(16).padLeft(2, '0')].join()}';
    final head = utf8.encode(
      '--$boundary\r\n'
      'Content-Disposition: form-data; name="placeId"\r\n\r\n'
      '$placeId\r\n'
      '--$boundary\r\n'
      'Content-Disposition: form-data; name="file"; filename="photo.jpg"\r\n'
      'Content-Type: image/jpeg\r\n\r\n',
    );
    final tail = utf8.encode('\r\n--$boundary--\r\n');
    final total = head.length + jpeg.length + tail.length;
    final abort = Completer<void>();
    final request =
        _ProgressRequest(endpoint, [head, jpeg, tail], chunk, abort.future, (
            sent,
          ) {
            onProgress?.call(sent / total);
          })
          ..contentLength = total
          ..followRedirects = false
          ..headers.addAll({
            ...headers,
            'content-type': 'multipart/form-data; boundary=$boundary',
            'accept': 'application/json',
            // Browsers refuse a script-set User-Agent and log an error for it.
            if (!kIsWeb) 'user-agent': userAgent,
          });
    // The whole exchange is bounded, the connection included: a stalled
    // upload would otherwise hold the outbox. The request is aborted at the
    // limit; the timeout after it covers a client that cannot abort.
    final limit = Timer(timeout, () {
      if (!abort.isCompleted) abort.complete();
    });
    Future<http.Response> exchange() async =>
        await http.Response.fromStream(await _client.send(request));
    final http.Response response;
    try {
      response = await exchange().timeout(timeout + const Duration(seconds: 5));
    } on TimeoutException {
      throw UploadException(0, 'no answer after ${timeout.inSeconds} s');
    } on http.RequestAbortedException {
      throw UploadException(0, 'no answer after ${timeout.inSeconds} s');
    } on http.ClientException catch (e) {
      throw UploadException(0, e.message);
    } finally {
      limit.cancel();
    }
    final body = _json(response.bodyBytes);
    if (response.statusCode == 200) {
      final photo = body?['photo'];
      if (photo is Map<String, dynamic>) {
        final parsed = photosFromJson([photo]);
        if (parsed.isNotEmpty) return parsed.first;
      }
      throw const UploadException(200, 'the answer carries no photo');
    }
    final errors = body?['errors'];
    final first =
        errors is List &&
            errors.isNotEmpty &&
            errors.first is Map<String, dynamic>
        ? errors.first as Map<String, dynamic>
        : const <String, dynamic>{};
    final ext = first['extensions'] is Map<String, dynamic>
        ? first['extensions'] as Map<String, dynamic>
        : const <String, dynamic>{};
    final wait =
        (ext['retryAfterSeconds'] as num?)?.toInt() ??
        int.tryParse(response.headers['retry-after'] ?? '');
    throw UploadException(
      response.statusCode,
      '${first['message'] ?? 'HTTP ${response.statusCode}'}',
      code: ext['code'] as String?,
      requiredLevel: (ext['requiredLevel'] as num?)?.toInt(),
      retryAfter: wait == null ? null : Duration(seconds: max(1, wait)),
    );
  }

  static Map<String, dynamic>? _json(Uint8List bytes) {
    try {
      final decoded = jsonDecode(utf8.decode(bytes));
      return decoded is Map<String, dynamic> ? decoded : null;
    } on FormatException {
      return null;
    }
  }
}

/// A request whose body is produced a chunk at a time, as the connection
/// asks for it.
final class _ProgressRequest extends http.BaseRequest with http.Abortable {
  new(Uri url, this._parts, this._chunk, this.abortTrigger, this._onSent)
    : super('POST', url);

  @override
  final Future<void> abortTrigger;

  final List<List<int>> _parts;
  final int _chunk;
  final void Function(int sent) _onSent;

  @override
  http.ByteStream finalize() {
    super.finalize();
    return http.ByteStream(_body());
  }

  Stream<List<int>> _body() async* {
    var sent = 0;
    for (final part in _parts) {
      for (var i = 0; i < part.length; i += _chunk) {
        final end = min(i + _chunk, part.length);
        yield part.sublist(i, end);
        sent += end - i;
        _onSent(sent);
      }
    }
  }
}
