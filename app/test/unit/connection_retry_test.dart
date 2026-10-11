import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:lunaway/core/http/app_http_client_io.dart';
import 'package:lunaway/core/http/connection_retry.dart';
import 'package:lunaway/features/places/data/graphql/graphql_client.dart';
import 'package:lunaway/features/places/data/graphql/operations.dart';

typedef _Answer = ({int status, String body});

const _Answer _ok = (status: 200, body: '{"data":{"ok":true}}');

final _query = GraphQLOperation<Map<String, dynamic>>(
  name: 'Place',
  document: 'query Place { place(id: "p") { id } }',
  parse: (data) => data,
);

final _mutation = GraphQLOperation<Map<String, dynamic>>(
  name: 'AddNote',
  document: 'mutation AddNote { addNote(text: "x") { id } }',
  parse: (data) => data,
);

/// A server on the loopback. A connection it is told to drop closes
/// without a word at the next request it carries, as one a mobile network
/// forgot while the app kept it open.
final class _Server {
  new _(this._http);

  static Future<_Server> start() async {
    final server = _Server._(await HttpServer.bind(InternetAddress.loopbackIPv4, 0));
    server._http.listen(server._handle);
    return server;
  }

  final HttpServer _http;

  /// The requests received, with the client's port: one per connection.
  final requests =
      <({String method, String path, int connection, Map<String, String> headers, String body})>[];
  final _idle = <int>{};

  /// The connections to drop, and whether each is reset.
  final _dropped = <int, bool>{};

  /// What the server answers; null when [answer] wrote the response itself.
  Future<_Answer?> Function(HttpRequest request) answer = (_) async => _ok;

  Uri url(String path) => Uri.parse('http://127.0.0.1:${_http.port}$path');

  Set<int> get connections => {for (final r in requests) r.connection};

  /// Every connection idle now closes at its next request, or is reset.
  void dropIdle({bool reset = false}) => _dropped.addAll({for (final c in _idle) c: reset});

  Future<void> _handle(HttpRequest request) async {
    final connection = request.connectionInfo!.remotePort;
    _idle.remove(connection);
    final headers = <String, String>{};
    request.headers.forEach((name, values) => headers[name] = values.join(','));
    requests.add((
      method: request.method,
      path: request.uri.path,
      connection: connection,
      headers: headers,
      body: await utf8.decoder.bind(request).join(),
    ));
    if (_dropped.remove(connection) case final reset?) {
      final socket = await request.response.detachSocket(writeHeaders: false);
      if (reset) {
        // Lingering zero seconds, the close sends a reset.
        socket.setRawOption(
          RawSocketOption(
            RawSocketOption.levelSocket,
            Platform.isLinux ? 13 : 0x80, // SO_LINGER
            Uint8List.fromList([1, 0, 0, 0, 0, 0, 0, 0]),
          ),
        );
      }
      socket.destroy();
      return;
    }
    if (await answer(request) case (:final status, :final body)) {
      request.response
        ..statusCode = status
        ..headers.contentType = ContentType.json
        ..write(body);
      await request.response.close();
    }
    _idle.add(connection);
  }

  Future<void> close() => _http.close(force: true);
}

void main() {
  late _Server server;
  late http.Client client;

  setUp(() async {
    server = await _Server.start();
    client = appHttpClient();
  });

  tearDown(() async {
    client.close();
    await server.close();
  });

  GraphQLClient graphql() =>
      GraphQLClient(endpoint: server.url('/graphql'), httpClient: client, userAgent: 'test');

  /// One request answered, its connection kept, then dropped by the
  /// network.
  Future<int> keptThenDropped({bool reset = false}) async {
    await client.get(server.url('/health'));
    server.dropIdle(reset: reset);
    return server.requests.single.connection;
  }

  test('a GraphQL read whose kept connection closed goes again, the same, on a new one', () async {
    final kept = await keptThenDropped();
    final answer = await graphql().execute(
      _query,
      const {'id': 'p'},
      const {'authorization': 'Bearer session'},
    );
    expect(answer, {'ok': true});
    final reads = server.requests.where((r) => r.path == '/graphql').toList();
    expect(reads, hasLength(2));
    expect(reads.first.connection, kept);
    expect(reads.last.connection, isNot(kept));
    expect(reads.last.body, reads.first.body);
    expect(jsonDecode(reads.last.body), containsPair('variables', {'id': 'p'}));
    for (final name in ['authorization', 'content-type', 'user-agent', 'accept']) {
      expect(reads.last.headers[name], reads.first.headers[name], reason: name);
      expect(reads.last.headers[name], isNotNull, reason: name);
    }
  });

  test('a GET of a tile, an image or a pack goes again the same way', () async {
    final kept = await keptThenDropped();
    final response = await client.get(server.url('/tiles/planet.json'));
    expect(response.statusCode, 200);
    final gets = server.requests.where((r) => r.path == '/tiles/planet.json').toList();
    expect(gets.map((r) => r.connection), [kept, isNot(kept)]);
  });

  test('a GET goes again with its range and without the redirect it refused', () async {
    // A pack's resume asks for a range; a photo's GET refuses a redirect
    // to an address not checked.
    server.answer = (request) async {
      if (request.uri.path != '/pack') return _ok;
      request.response
        ..statusCode = 302
        ..headers.set('location', '/elsewhere');
      await request.response.close();
      return null;
    };
    await keptThenDropped();
    final asked = http.Request('GET', server.url('/pack'))
      ..followRedirects = false
      ..headers['range'] = 'bytes=10-';
    final response = await client.send(asked);
    expect(response.statusCode, 302);
    final packs = server.requests.where((r) => r.path == '/pack');
    expect(packs.map((r) => r.headers['range']), ['bytes=10-', 'bytes=10-']);
    expect(server.requests.map((r) => r.path), isNot(contains('/elsewhere')));
  });

  test('a GET its caller cancels during the second try ends there', () async {
    final second = Completer<void>();
    server.answer = (request) async {
      if (request.uri.path != '/search') return _ok;
      second.complete();
      await Completer<void>().future;
      return _ok;
    };
    await keptThenDropped();
    final abort = Completer<void>();
    final call = client.send(
      http.AbortableRequest('GET', server.url('/search'), abortTrigger: abort.future),
    );
    await second.future;
    abort.complete();
    await expectLater(
      call.timeout(const Duration(seconds: 5)),
      throwsA(isA<http.RequestAbortedException>()),
    );
  });

  test('a read whose kept connection was reset goes again too', () async {
    final kept = await keptThenDropped(reset: true);
    expect(await graphql().execute(_query), {'ok': true});
    final reads = server.requests.where((r) => r.path == '/graphql');
    expect(reads.map((r) => r.connection), [kept, isNot(kept)]);
  });

  test('a mutation whose connection closed does not go again', () async {
    await keptThenDropped();
    await expectLater(graphql().execute(_mutation), throwsA(isA<GraphQLNetworkException>()));
    expect(server.requests.where((r) => r.path == '/graphql'), hasLength(1));
  });

  test('a document whose kind the app cannot read counts as a write', () {
    bool read(String document) =>
        GraphQLOperation<Object?>(name: 'X', document: document, parse: (d) => d).read;
    expect(read('query A { a }'), isTrue);
    expect(read('{ a }'), isTrue);
    expect(read('mutation A { a }'), isFalse);
    expect(read('fragment F on T { a } mutation M { ...F }'), isFalse);
  });

  test('a closed client refuses a request as the platform client does', () async {
    client.close();
    await expectLater(client.get(server.url('/health')), throwsA(isA<http.ClientException>()));
  });

  test('an answer, even a 500, is not sent again', () async {
    server.answer = (_) async => (status: 500, body: '<html>500</html>');
    await expectLater(graphql().execute(_query), throwsA(isA<GraphQLNetworkException>()));
    expect((await client.get(server.url('/img/1'))).statusCode, 500);
    expect(server.requests.map((r) => r.path), ['/graphql', '/img/1']);
  });

  test('the second try never takes another connection the network dropped', () async {
    // Two connections kept: a naive second try would take the other one.
    final both = Completer<void>();
    server.answer = (_) async {
      if (server.requests.length == 2) both.complete();
      await both.future;
      return _ok;
    };
    await Future.wait([client.get(server.url('/a')), client.get(server.url('/b'))]);
    final kept = server.connections;
    expect(kept, hasLength(2));
    server
      ..answer = ((_) async => _ok)
      ..dropIdle();
    expect((await client.get(server.url('/c'))).statusCode, 200);
    expect(server.requests.last.connection, isNot(isIn(kept)));
  });

  test('a download under way goes on when another request finds a dead connection', () async {
    final rest = Completer<void>();
    server.answer = (request) async {
      if (request.uri.path != '/pack') return _ok;
      request.response
        ..statusCode = 200
        ..write('first half,');
      await request.response.flush();
      await rest.future;
      request.response.write('second half');
      await request.response.close();
      return null;
    };
    final pack = await client.send(http.Request('GET', server.url('/pack')));
    final body = pack.stream.transform(utf8.decoder).join();
    await client.get(server.url('/health'));
    server.dropIdle();
    expect((await client.get(server.url('/tiles/planet.json'))).statusCode, 200);
    rest.complete();
    expect(await body, 'first half,second half');
  });

  test('the second try leaves at once and ends when the first one would have', () {
    fakeAsync((async) {
      final asked = <Duration>[];
      var opened = 0;
      final reconnecting = ReconnectingClient(
        () => _Connections(async, asked, dead: opened++ == 0),
        closedEarly: (e) => e is _Closed,
      );
      final graphql = GraphQLClient(
        endpoint: Uri.parse('http://127.0.0.1:1/graphql'),
        httpClient: reconnecting,
        userAgent: 'test',
        timeout: const Duration(seconds: 20),
      );
      Object? failure;
      unawaited(graphql.execute(_query).then<void>((_) {}, onError: (Object e) => failure = e));
      async.elapse(const Duration(seconds: 19));
      expect(asked, [Duration.zero, const Duration(seconds: 15)]);
      expect(failure, isNull);
      async.elapse(const Duration(seconds: 1));
      expect(
        failure,
        isA<GraphQLNetworkException>().having((e) => e.message, 'message', contains('timeout')),
      );
      async.elapse(const Duration(minutes: 1));
      expect(asked, hasLength(2));
    });
  });

  test(
    'the connections replaced close once the requests they were sending have an answer',
    () async {
      final sets = <_Held>[];
      final reconnecting = ReconnectingClient(() {
        final set = _Held();
        sets.add(set);
        return set;
      }, closedEarly: (e) => e is _Closed);
      // A place's page: one request still opening its connection when
      // another finds its own dead.
      final opening = reconnecting.get(Uri.parse('http://api.test/a'));
      final dead = reconnecting.get(Uri.parse('http://api.test/b'));
      sets.single.waiting[1].completeError(_Closed());
      await Future<void>.delayed(Duration.zero);
      expect(sets, hasLength(2), reason: 'the next requests go through new connections');
      expect(sets.first.closed, isFalse, reason: 'closing it would cancel the first request');
      sets.last.waiting.single.complete(_Held.answer());
      sets.first.waiting.first.complete(_Held.answer());
      expect((await opening).statusCode, 200);
      expect((await dead).statusCode, 200);
      expect(sets.first.closed, isTrue);
      expect(sets.last.closed, isFalse);
    },
  );

  group('a connection that closed before the answer', () {
    test('is told by its system code or by the words dart:io passes on', () {
      final darwin = Platform.isMacOS || Platform.isIOS;
      for (final error in [
        http.ClientException('Connection closed before full header was received'),
        // A socket's error while dart:io reads the answer keeps only its words.
        http.ClientException('Connection reset by peer'),
        const SocketException('Write failed', osError: OSError('Broken pipe', 32)),
        SocketException('Read failed', osError: OSError('', darwin ? 54 : 104)),
        SocketException('Connection failed', osError: OSError('', darwin ? 60 : 110)),
      ]) {
        expect(closedBeforeAnswer(error), isTrue, reason: '$error');
      }
    });

    test('is not a refused connection, a failed lookup, TLS or a cancelled request', () async {
      final free = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final port = free.port;
      await free.close();
      Object? refused;
      try {
        await client.get(Uri.parse('http://127.0.0.1:$port/'));
      } on Object catch (e) {
        refused = e;
      }
      for (final error in [
        refused,
        const SocketException(
          "Failed host lookup: 'api.lunaway.net'",
          osError: OSError('nodename nor servname provided, or not known', 8),
        ),
        const HandshakeException('CERTIFICATE_VERIFY_FAILED'),
        http.RequestAbortedException(),
      ]) {
        expect(error, isNotNull);
        expect(closedBeforeAnswer(error!), isFalse, reason: '$error');
      }
    });
  });
}

final class _Closed implements Exception;

/// A set of connections: a dead one fails 15 s after it is asked, a live
/// one never answers.
final class _Connections extends http.BaseClient {
  new(this._async, this._asked, {required this.dead});

  final FakeAsync _async;
  final List<Duration> _asked;
  final bool dead;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    _asked.add(_async.elapsed);
    if (!dead) await Completer<void>().future;
    await Future<void>.delayed(const Duration(seconds: 15));
    throw _Closed();
  }
}

/// A set of connections whose answers the test gives by hand. Its `close`
/// cancels the requests still waiting, as dart:io's cancels the
/// connections it is still opening.
final class _Held extends http.BaseClient {
  final waiting = <Completer<http.StreamedResponse>>[];
  bool closed = false;

  static http.StreamedResponse answer() => http.StreamedResponse(const Stream.empty(), 200);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    final answer = Completer<http.StreamedResponse>();
    waiting.add(answer);
    return answer.future;
  }

  @override
  void close() {
    closed = true;
    for (final w in waiting.where((w) => !w.isCompleted)) {
      w.completeError(http.ClientException('Connection attempt cancelled'));
    }
  }
}
