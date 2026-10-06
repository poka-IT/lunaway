import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:lunaway/core/config/app_config.dart';

/// A photo the app refused or failed to download. The image widgets show
/// their error placeholder for it.
final class ImageFetchException implements Exception {
  new(this.message);

  final String message;

  @override
  String toString() => 'ImageFetchException: $message';
}

/// Downloads photos from the API's image proxy, and nothing else: the app
/// talks only to its own hosts, and a URL in the data (a review, a source)
/// must never make it fetch a third-party address. Every request carries the
/// app's User-Agent, gives up after [timeout], and stops reading past
/// [maxBytes] so a wrong answer cannot fill the memory or the disk.
final class ImageFetcher {
  new({
    required this._client,
    required this._config,
    required this.userAgent,
    this.timeout = const Duration(seconds: 20),
    this.maxBytes = 8 * 1024 * 1024,
    Future<void> Function(Duration wait)? sleep,
  }) : _sleep = sleep ?? Future<void>.delayed;

  final http.Client _client;
  final AppConfig _config;
  final String userAgent;
  final Duration timeout;
  final int maxBytes;
  final Future<void> Function(Duration wait) _sleep;

  /// Whether [url] is one the fetcher accepts.
  bool accepts(String url) {
    final uri = Uri.tryParse(url);
    return uri != null && _config.isApiMedia(uri);
  }

  Future<Uint8List> fetch(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null || !_config.isApiMedia(uri)) {
      throw ImageFetchException('not a photo of the Lunaway API: $url');
    }
    var response = await _get(uri);
    // The proxy answers 404 with Retry-After while it fetches a photo it has
    // not seen yet: wait once, as told, then ask again. The screen keeps its
    // skeleton meanwhile.
    final retryAfter = retryDelay(response.statusCode, response.headers);
    if (retryAfter != null) {
      await response.stream.drain<void>();
      await _sleep(retryAfter);
      response = await _get(uri);
    }
    if (response.statusCode != 200) {
      await response.stream.drain<void>();
      throw ImageFetchException('HTTP ${response.statusCode} for $url');
    }
    final length = response.contentLength;
    if (length != null && length > maxBytes) {
      await response.stream.drain<void>();
      throw ImageFetchException('$url announces $length bytes, over $maxBytes');
    }
    final bytes = await _read(response.stream, url).timeout(timeout);
    if (bytes.isEmpty) throw ImageFetchException('empty body for $url');
    return bytes;
  }

  Future<http.StreamedResponse> _get(Uri uri) async {
    // A redirect would lead away from the address checked above: it fails
    // like any answer other than 200. Browsers follow redirects whatever the
    // request says; there the page's CSP keeps them on our hosts.
    final request = http.Request('GET', uri)..followRedirects = false;
    // Browsers refuse a script-set User-Agent and log an error for it.
    if (!kIsWeb) request.headers['user-agent'] = userAgent;
    try {
      return await _client.send(request).timeout(timeout);
    } on TimeoutException {
      throw ImageFetchException('timeout after ${timeout.inSeconds} s for $uri');
    } on http.ClientException catch (e) {
      throw ImageFetchException('${e.message} for $uri');
    }
  }

  Future<Uint8List> _read(Stream<List<int>> stream, String url) async {
    final builder = BytesBuilder(copy: false);
    await for (final chunk in stream) {
      builder.add(chunk);
      if (builder.length > maxBytes) {
        throw ImageFetchException('$url is over $maxBytes bytes');
      }
    }
    return builder.takeBytes();
  }

  /// The wait a 404 asks for, in whole seconds, capped at half a minute;
  /// null for any other answer.
  @visibleForTesting
  static Duration? retryDelay(int status, Map<String, String> headers) {
    if (status != 404) return null;
    final seconds = int.tryParse(headers['retry-after']?.trim() ?? '');
    if (seconds == null || seconds < 0) return null;
    return Duration(seconds: seconds > 30 ? 30 : seconds);
  }
}
