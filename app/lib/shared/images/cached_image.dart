import 'dart:convert';
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:lunaway/shared/images/image_file_cache_web.dart'
    if (dart.library.io) 'package:lunaway/shared/images/image_file_cache.dart';

/// A photo from the Lunaway image proxy, kept on disk once fetched. URLs
/// starting with `asset:` are read from the app bundle (the demo photos).
@immutable
final class CachedImage extends ImageProvider<CachedImage> {
  const new(this.url, {this.headers = const {}});

  final String url;
  final Map<String, String> headers;

  @override
  Future<CachedImage> obtainKey(ImageConfiguration configuration) => SynchronousFuture(this);

  @override
  ImageStreamCompleter loadImage(CachedImage key, ImageDecoderCallback decode) =>
      MultiFrameImageStreamCompleter(codec: _load(decode), scale: 1, debugLabel: url);

  Future<ui.Codec> _load(ImageDecoderCallback decode) async {
    final bytes = await _bytes();
    return await decode(await ui.ImmutableBuffer.fromUint8List(bytes));
  }

  Future<Uint8List> _bytes() async {
    if (url.startsWith('asset:')) {
      return (await rootBundle.load(url.substring('asset:'.length))).buffer.asUint8List();
    }
    final key = sha1.convert(utf8.encode(url)).toString();
    final cached = await readCachedImage(key);
    if (cached != null) return cached;
    var response = await http.get(Uri.parse(url), headers: headers);
    // The proxy answers 404 with Retry-After while it fetches a photo it has
    // not seen yet: wait once, as told, then ask again. The screen keeps its
    // skeleton meanwhile.
    final retryAfter = retryDelay(response);
    if (retryAfter != null) {
      await Future<void>.delayed(retryAfter);
      response = await http.get(Uri.parse(url), headers: headers);
    }
    if (response.statusCode != 200 || response.bodyBytes.isEmpty) {
      throw NetworkImageLoadException(statusCode: response.statusCode, uri: Uri.parse(url));
    }
    await writeCachedImage(key, response.bodyBytes);
    return response.bodyBytes;
  }

  /// The wait a 404 asks for, in whole seconds, capped at half a minute;
  /// null for any other answer.
  @visibleForTesting
  static Duration? retryDelay(http.Response response) {
    if (response.statusCode != 404) return null;
    final seconds = int.tryParse(response.headers['retry-after']?.trim() ?? '');
    if (seconds == null || seconds < 0) return null;
    return Duration(seconds: seconds > 30 ? 30 : seconds);
  }

  @override
  bool operator ==(Object other) => other is CachedImage && other.url == url;

  @override
  int get hashCode => url.hashCode;
}
