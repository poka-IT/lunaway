import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lunaway/core/config/app_config.dart';
import 'package:lunaway/shared/images/image_fetcher.dart';

const _config = AppConfig(apiBaseUrl: 'https://api.lunaway.net', demo: false, basemapUrl: '');

void main() {
  late List<http.BaseRequest> requests;

  ImageFetcher fetcher(
    Future<http.StreamedResponse> Function(http.BaseRequest r) answer, {
    int maxBytes = 1024,
    Duration timeout = const Duration(seconds: 2),
  }) => ImageFetcher(
    client: MockClient.streaming((r, _) {
      requests.add(r);
      return answer(r);
    }),
    config: _config,
    userAgent: 'Lunaway/9.9 (+https://lunaway.net)',
    maxBytes: maxBytes,
    timeout: timeout,
    sleep: (_) async {},
  );

  http.StreamedResponse ok(List<int> bytes, {int? length}) =>
      http.StreamedResponse(Stream.value(bytes), 200, contentLength: length);

  setUp(() => requests = []);

  test('fetches a photo of the API image proxy with the Lunaway User-Agent', () async {
    final f = fetcher((_) async => ok([1, 2, 3]));
    expect(await f.fetch('https://api.lunaway.net/media/abc/thumb'), Uint8List.fromList([1, 2, 3]));
    expect(requests.single.headers['user-agent'], 'Lunaway/9.9 (+https://lunaway.net)');
  });

  test('refuses every other address, without a request', () async {
    final f = fetcher((_) async => ok([1]));
    for (final url in [
      'https://evil.example/media/abc/thumb',
      'http://api.lunaway.net/media/abc/thumb',
      'https://api.lunaway.net:8443/media/abc/thumb',
      'https://api.lunaway.net/graphql',
      'https://api.lunaway.net/media/../graphql',
      'file:///etc/passwd',
      'asset:assets/x.png',
    ]) {
      expect(f.accepts(url), isFalse, reason: url);
      await expectLater(f.fetch(url), throwsA(isA<ImageFetchException>()), reason: url);
    }
    expect(requests, isEmpty);
  });

  test('a redirect is never followed, so it cannot lead to another host', () async {
    final f = fetcher(
      (_) async => http.StreamedResponse(
        const Stream.empty(),
        302,
        headers: {'location': 'https://evil.example/x.jpg'},
      ),
    );
    await expectLater(
      f.fetch('https://api.lunaway.net/media/abc/thumb'),
      throwsA(isA<ImageFetchException>()),
    );
    expect(requests.single.followRedirects, isFalse);
  });

  test('stops reading past the size cap, announced or not', () async {
    final big = fetcher((_) async => ok(List.filled(2000, 0)));
    await expectLater(
      big.fetch('https://api.lunaway.net/media/a/large'),
      throwsA(isA<ImageFetchException>()),
    );
    final announced = fetcher((_) async => ok([0], length: 5000));
    await expectLater(
      announced.fetch('https://api.lunaway.net/media/a/large'),
      throwsA(isA<ImageFetchException>()),
    );
  });

  test('gives up after its timeout', () async {
    final slow = fetcher(
      (_) => Completer<http.StreamedResponse>().future,
      timeout: const Duration(milliseconds: 50),
    );
    await expectLater(
      slow.fetch('https://api.lunaway.net/media/a/thumb'),
      throwsA(isA<ImageFetchException>()),
    );
  });

  test('a photo still being fetched by the proxy is asked again once, after the delay', () async {
    var calls = 0;
    final f = fetcher((_) async {
      calls++;
      return calls == 1
          ? http.StreamedResponse(const Stream.empty(), 404, headers: {'retry-after': '3'})
          : ok([7]);
    });
    expect(await f.fetch('https://api.lunaway.net/media/a/thumb'), [7]);
    expect(calls, 2);
    expect(ImageFetcher.retryDelay(404, {'retry-after': '600'}), const Duration(seconds: 30));
    expect(ImageFetcher.retryDelay(404, const {}), isNull);
    expect(ImageFetcher.retryDelay(503, {'retry-after': '3'}), isNull);
  });
}
