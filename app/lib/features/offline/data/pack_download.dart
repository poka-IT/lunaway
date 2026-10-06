import 'dart:async';

import 'package:http/http.dart' as http;
import 'package:meta/meta.dart';

/// Where the bytes of a download go: a file on the device, a list in tests.
abstract interface class PackSink {
  /// The bytes already there, from an earlier attempt.
  Future<int> length();

  /// Empties it: the file changed on the server, the download starts over.
  Future<void> truncate();

  Future<void> append(List<int> bytes);

  /// Writes what is buffered and releases the file.
  Future<void> close();
}

/// Why a download stopped.
enum PackDownloadFailure {
  /// No network, a timeout, a cut connection: resume later.
  network,

  /// The server answered something else than the pack (an error page, a
  /// size other than the manifest's).
  server,

  /// The bytes do not match the manifest's SHA-256: the copy is dropped.
  corrupt,

  /// No room left on the device.
  storage,
}

final class PackDownloadException implements Exception {
  const new(this.failure, this.message);

  final PackDownloadFailure failure;
  final String message;

  @override
  String toString() => 'PackDownloadException(${failure.name}): $message';
}

/// Lets the user pause a download: the next chunk sees it and stops.
final class PackDownloadToken {
  bool _cancelled = false;

  bool get cancelled => _cancelled;

  void cancel() => _cancelled = true;
}

/// The end of one attempt.
@immutable
final class PackDownloadResult {
  const new({required this.complete, required this.received, this.etag});

  /// Every byte is there; else the user paused it.
  final bool complete;
  final int received;

  /// The validator of the file on the server, kept for the next resume
  /// (`If-Range`).
  final String? etag;
}

/// Downloads one pack into a [PackSink], resuming where an earlier attempt
/// stopped (docs/deploy.md "Offline packs"): a pack's URL never changes
/// content, so `Range` with `If-Range` (the `ETag` of the first answer)
/// continues it; a 206 appends, a 200 means the file changed and starts
/// over. The size must end at the manifest's; the SHA-256 is checked by the
/// caller once the file is whole.
final class PackDownloader {
  new({
    required this.client,
    required this.userAgent,
    this.connectTimeout = const Duration(seconds: 30),
    this.idleTimeout = const Duration(seconds: 45),
  });

  final http.Client client;
  final String? userAgent;
  final Duration connectTimeout;

  /// A connection silent this long counts as cut: the download pauses
  /// itself, to resume.
  final Duration idleTimeout;

  Future<PackDownloadResult> download(
    Uri url, {
    required int size,
    required PackSink sink,
    required PackDownloadToken token,
    String? etag,
    void Function(int received)? onProgress,
  }) async {
    var have = await sink.length();
    if (have > size) {
      await sink.truncate();
      have = 0;
    }
    if (have == size) return PackDownloadResult(complete: true, received: have, etag: etag);
    final request = http.Request('GET', url)
      ..headers.addAll({
        'user-agent': ?userAgent,
        if (have > 0) 'range': 'bytes=$have-',
        if (have > 0 && etag != null) 'if-range': etag,
      });
    final http.StreamedResponse response;
    try {
      response = await client.send(request).timeout(connectTimeout);
    } on TimeoutException catch (e) {
      throw PackDownloadException(PackDownloadFailure.network, 'no answer: $e');
    } on http.ClientException catch (e) {
      throw PackDownloadException(PackDownloadFailure.network, e.message);
    }
    final newTag = response.headers['etag'] ?? etag;
    var received = have;
    switch (response.statusCode) {
      case 206:
        final start = _rangeStart(response.headers['content-range']);
        if (start != have) {
          // A range other than the one asked: start over rather than splice.
          await _drain(response);
          await sink.truncate();
          throw const PackDownloadException(PackDownloadFailure.server, 'unexpected range');
        }
      case 200:
        // The whole file: the first request, or the file changed since the
        // part was written. To a resume, only an answer of the pack's size
        // replaces the part: a captive portal's page would otherwise wipe
        // hundreds of megabytes already here.
        if (have > 0) {
          if (response.contentLength != size) {
            // Not read: an unasked-for body may never end.
            unawaited(response.stream.listen(null).cancel());
            throw const PackDownloadException(
              PackDownloadFailure.server,
              'a whole answer of another size to a resume',
            );
          }
          await sink.truncate();
        }
        received = 0;
      case 416 when have > 0:
        await _drain(response);
        await sink.truncate();
        throw const PackDownloadException(PackDownloadFailure.server, 'range refused');
      default:
        await _drain(response);
        throw PackDownloadException(PackDownloadFailure.server, 'HTTP ${response.statusCode}');
    }
    final done = Completer<void>();
    late StreamSubscription<List<int>> sub;
    Timer? idle;
    Object? failure;
    var writing = Future<void>.value();
    void armIdle() {
      idle?.cancel();
      idle = Timer(idleTimeout, () {
        failure = const PackDownloadException(PackDownloadFailure.network, 'connection silent');
        unawaited(sub.cancel());
        if (!done.isCompleted) done.complete();
      });
    }

    armIdle();
    sub = response.stream.listen(
      (chunk) {
        armIdle();
        if (received + chunk.length > size) {
          failure = const PackDownloadException(
            PackDownloadFailure.server,
            'longer than the manifest',
          );
          unawaited(sub.cancel());
          if (!done.isCompleted) done.complete();
          return;
        }
        received += chunk.length;
        // Writes in order; a pause stops the stream between two chunks.
        sub.pause();
        writing = writing
            .then((_) => sink.append(chunk))
            .then(
              (_) {
                onProgress?.call(received);
                if (token.cancelled) {
                  unawaited(sub.cancel());
                  if (!done.isCompleted) done.complete();
                } else {
                  sub.resume();
                }
              },
              onError: (Object e) {
                failure = e;
                unawaited(sub.cancel());
                if (!done.isCompleted) done.complete();
              },
            );
      },
      onError: (Object e) {
        failure = PackDownloadException(PackDownloadFailure.network, '$e');
        if (!done.isCompleted) done.complete();
      },
      onDone: () {
        if (!done.isCompleted) done.complete();
      },
      cancelOnError: true,
    );
    await done.future;
    idle?.cancel();
    try {
      await writing;
    } on Object catch (e) {
      failure ??= e;
    }
    await sink.close();
    if (failure case final f?) {
      if (f is PackDownloadException) throw f;
      throw PackDownloadException(
        _storage(f) ? PackDownloadFailure.storage : PackDownloadFailure.network,
        '$f',
      );
    }
    if (token.cancelled && received < size) {
      return PackDownloadResult(complete: false, received: received, etag: newTag);
    }
    if (received != size) {
      throw PackDownloadException(
        PackDownloadFailure.network,
        'stopped at $received of $size bytes',
      );
    }
    return PackDownloadResult(complete: true, received: received, etag: newTag);
  }

  static int? _rangeStart(String? contentRange) {
    final m = RegExp(r'bytes (\d+)-').firstMatch(contentRange ?? '');
    return m == null ? null : int.parse(m[1]!);
  }

  static Future<void> _drain(http.StreamedResponse response) async {
    try {
      await response.stream.drain<void>();
    } on Object {
      // The answer is refused anyway.
    }
  }

  /// A write that failed for want of room (ENOSPC, "No space left").
  static bool _storage(Object error) {
    final text = '$error'.toLowerCase();
    return text.contains('no space') || text.contains('errno = 28') || text.contains('disk full');
  }
}
