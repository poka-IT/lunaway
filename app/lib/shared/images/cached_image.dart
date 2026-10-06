import 'dart:convert';
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:lunaway/shared/images/image_fetcher.dart';
import 'package:lunaway/shared/images/image_file_cache_web.dart'
    if (dart.library.io) 'package:lunaway/shared/images/image_file_cache.dart';

/// A photo from the Lunaway image proxy, kept on disk once fetched. The
/// [fetcher] refuses any URL that is not a photo of the API.
@immutable
final class CachedImage extends ImageProvider<CachedImage> {
  const new(this.url, {required this.fetcher});

  final String url;
  final ImageFetcher fetcher;

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
    // Checked before the cache too: a cached file never vouches for a URL
    // the fetcher would refuse today.
    if (!fetcher.accepts(url)) throw ImageFetchException('refused: $url');
    final key = sha1.convert(utf8.encode(url)).toString();
    final cached = await readCachedImage(key);
    if (cached != null) return cached;
    final bytes = await fetcher.fetch(url);
    await writeCachedImage(key, bytes);
    return bytes;
  }

  // The fetcher is a service, not part of the identity: the same URL is the
  // same image whoever downloads it.
  @override
  bool operator ==(Object other) => other is CachedImage && other.url == url;

  @override
  int get hashCode => url.hashCode;
}
