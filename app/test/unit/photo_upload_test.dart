import 'dart:async';
import 'dart:typed_data';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:lunaway/features/community/data/photo_upload.dart';

/// A server that takes the connection and never answers.
final class _Silent extends http.BaseClient {
  http.BaseRequest? request;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    this.request = request;
    return Completer<http.StreamedResponse>().future;
  }
}

void main() {
  test('an upload that gets no answer is aborted at its limit and fails as offline', () {
    fakeAsync((async) {
      final client = _Silent();
      final uploader = PhotoUploader(
        client: client,
        endpoint: Uri.parse('https://api.lunaway.net/upload'),
        userAgent: 'test',
      );
      Object? failure;
      unawaited(
        uploader
            .upload(placeId: 'p1', jpeg: Uint8List(1000), headers: const {})
            .then<void>((_) {}, onError: (Object e) => failure = e),
      );
      var aborted = false;
      async.flushMicrotasks();
      unawaited(
        (client.request! as http.Abortable).abortTrigger!.then(
          (_) => aborted = true,
        ),
      );

      async.elapse(const Duration(seconds: 119));
      expect(aborted, isFalse);
      expect(failure, isNull);

      async.elapse(const Duration(seconds: 2));
      expect(aborted, isTrue, reason: 'the request is cut at the limit');

      // A client that cannot abort is still bounded, a little later.
      async.elapse(const Duration(seconds: 5));
      expect(
        failure,
        isA<UploadException>().having((e) => e.status, 'status', 0),
      );
    });
  });
}
