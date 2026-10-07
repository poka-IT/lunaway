import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:lunaway/core/config/app_config.dart';

/// A photo the app refused or failed to download. The image widgets show
/// their error placeholder for it.
class ImageFetchException implements Exception {
  new(this.message);

  final String message;

  @override
  String toString() => 'ImageFetchException: $message';
}

/// A photo the API's proxy has not fetched from its source yet (its daily
/// budget is spent, the source did not answer, the server is busy): the
/// screen keeps its placeholder and asks again after [retryAfter], never
/// before.
final class PhotoNotYetException extends ImageFetchException {
  new(String url, this.retryAfter) : super('not fetched by the proxy yet: $url');

  final Duration retryAfter;
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
    this.proxyTimeout = const Duration(seconds: 45),
    this.maxBytes = 8 * 1024 * 1024,
    Future<void> Function(Duration wait)? sleep,
    DateTime Function()? clock,
  }) : _sleep = sleep ?? Future<void>.delayed,
       _clock = clock ?? DateTime.now;

  final http.Client _client;
  final AppConfig _config;
  final String userAgent;
  final Duration timeout;

  /// The wait for the external photos' proxy, which may download the
  /// partner's file before it answers (its own limit is 20 s, after up to
  /// 10 s for a free slot): leaving earlier would cancel a download the
  /// server's daily budget already paid for.
  final Duration proxyTimeout;
  final int maxBytes;
  final Future<void> Function(Duration wait) _sleep;
  final DateTime Function() _clock;

  /// When each external photo the proxy could not serve may be asked for
  /// again, as its `Retry-After` said: reopening a place does not ask
  /// before then.
  final _notBefore = <String, DateTime>{};

  /// Whether [url] is one the fetcher accepts.
  bool accepts(String url) {
    final uri = Uri.tryParse(url);
    return uri != null && (_config.isApiMedia(uri) || _config.isApiExternalPhoto(uri));
  }

  Future<Uint8List> fetch(String url) async {
    final uri = Uri.tryParse(url);
    if (uri != null && _config.isApiExternalPhoto(uri)) return await _fetchExternal(url, uri);
    if (uri == null || !_config.isApiMedia(uri)) {
      throw ImageFetchException('not a photo of the Lunaway API: $url');
    }
    var response = await _get(uri, timeout);
    // The proxy answers 404 with Retry-After while it fetches a photo it has
    // not seen yet: wait once, as told, then ask again. The screen keeps its
    // skeleton meanwhile.
    final retryAfter = retryDelay(response.statusCode, response.headers);
    if (retryAfter != null) {
      await response.stream.drain<void>();
      await _sleep(retryAfter);
      response = await _get(uri, timeout);
    }
    return await _body(response, url);
  }

  /// A photo of the external community source through the API's proxy:
  /// a redirect to the API's own copy once it has one, a refusal with
  /// `Retry-After` while it has not.
  Future<Uint8List> _fetchExternal(String url, Uri uri) async {
    final now = _clock();
    final until = _notBefore[url];
    if (until != null && now.isBefore(until)) {
      throw PhotoNotYetException(url, until.difference(now));
    }
    var response = await _get(uri, proxyTimeout, redirected: true);
    final wait = unavailableDelay(response.statusCode, response.headers);
    if (wait != null) {
      await response.stream.drain<void>();
      _remember(url, now.add(wait));
      throw PhotoNotYetException(url, wait);
    }
    if (_redirects.contains(response.statusCode)) {
      await response.stream.drain<void>();
      final location = response.headers['location'];
      final target = location == null ? null : uri.resolve(location);
      // Followed by hand, and only to the API's own copy: the target is
      // held to the same rule as any photo URL in the data.
      if (target == null || !_config.isApiMedia(target)) {
        throw ImageFetchException('$url redirects outside the API photos: $location');
      }
      response = await _get(target, timeout);
    }
    _notBefore.remove(url);
    return await _body(response, url);
  }

  void _remember(String url, DateTime until) {
    if (_notBefore.length >= 500) {
      final now = _clock();
      _notBefore.removeWhere((_, at) => !now.isBefore(at));
    }
    _notBefore[url] = until;
  }

  static const _redirects = {301, 302, 303, 307, 308};

  Future<Uint8List> _body(http.StreamedResponse response, String url) async {
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

  /// GETs [uri]. A redirect would lead away from the address checked: it
  /// fails like any answer other than 200, unless followed by hand to an
  /// address checked again. A browser's fetch hides the redirect from the
  /// page and fails the request outright when told not to follow, so a
  /// request that expects one ([redirected], the external photos' proxy)
  /// lets the browser follow it; there the page's CSP keeps it on our
  /// hosts.
  Future<http.StreamedResponse> _get(Uri uri, Duration limit, {bool redirected = false}) async {
    final request = http.Request('GET', uri)..followRedirects = kIsWeb && redirected;
    // Browsers refuse a script-set User-Agent and log an error for it.
    if (!kIsWeb) request.headers['user-agent'] = userAgent;
    try {
      return await _client.send(request).timeout(limit);
    } on TimeoutException {
      throw ImageFetchException('timeout after ${limit.inSeconds} s for $uri');
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

  /// How long the external photos' proxy asks not to be asked again: its
  /// 502 (the source failed), 503 (budget spent, server busy) or 429 (this
  /// client's budget), for its `Retry-After`, a minute without one; null
  /// for any other answer.
  @visibleForTesting
  static Duration? unavailableDelay(int status, Map<String, String> headers) {
    if (status != 502 && status != 503 && status != 429) return null;
    final seconds = int.tryParse(headers['retry-after']?.trim() ?? '');
    if (seconds == null || seconds < 1) return const Duration(minutes: 1);
    return Duration(seconds: seconds);
  }
}
