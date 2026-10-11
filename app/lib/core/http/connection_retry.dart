import 'package:http/http.dart' as http;
import 'package:logging/logging.dart';

final _log = Logger('http');

/// A request that changes nothing where it goes, which [ReconnectingClient]
/// may send twice: a GraphQL query, sent by POST. A GET or a HEAD needs no
/// mark.
final class ReadRequest extends http.Request implements http.Abortable {
  new(super.method, super.url, {this.abortTrigger});

  @override
  final Future<void>? abortTrigger;
}

/// Sends a read again once, at once, on a new connection, when its
/// connection closed or broke before any answer came.
///
/// The app keeps an idle connection 100 s (`app_http_client_io.dart`). A
/// mobile network, or a move from Wi-Fi to mobile data, can drop it without
/// the phone knowing; the next request sent on it then fails although the
/// server is fine. A read (a GET, a HEAD, a [ReadRequest]) goes again; a
/// write never does: a mutation has its idempotency key and its outbox,
/// which decide when it goes again. An answer, whatever its status, is
/// returned as it came.
///
/// The other idle connections are likely as dead as the one that failed:
/// the requests from then on go through a new set of connections ([open]).
/// The old set is closed once the requests it was sending have their
/// answer: dart:io's `close` cancels the connections still being opened,
/// which failed the other requests of a place's page on the emulator. Its
/// answers being read, a pack's download, go on to their end. The second
/// try goes within the first one's time: the caller's timeout covers both.
final class ReconnectingClient extends http.BaseClient {
  /// [open] makes a client with connections of its own, whose `close` lets
  /// the answers being read end; [closedEarly] says whether an error of
  /// its `send` is a connection that closed before any answer.
  new(this.open, {required this.closedEarly}) : _pool = open();

  final http.Client Function() open;
  final bool Function(Object error) closedEarly;

  http.Client _pool;
  bool _closed = false;

  /// How many requests each set of connections is sending.
  final _sending = <http.Client, int>{};

  /// The sets replaced, closed when their last request has its answer.
  final _replaced = <http.Client>{};

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    // As IOClient's: dart:io's closed client would throw a StateError no
    // caller catches.
    if (_closed) {
      throw http.ClientException('HTTP request failed. Client is already closed.', request.url);
    }
    final pool = _pool;
    try {
      return await _send(pool, request);
    } on Object catch (error) {
      if (_closed || !closedEarly(error)) rethrow;
      // Several requests can fail at once on the same dead connections:
      // the first one to come back replaces them.
      if (identical(pool, _pool)) {
        _pool = open();
        _retire(pool);
      }
      final again = _again(request);
      if (again == null) rethrow;
      // The host alone: a tile's or an image's address says where the user looks.
      final what = error is http.ClientException ? error.message : '$error';
      _log.info('${request.method} ${request.url.host}: $what, sent again on a new connection');
      return await _send(_pool, again);
    }
  }

  Future<http.StreamedResponse> _send(http.Client pool, http.BaseRequest request) async {
    _sending.update(pool, (n) => n + 1, ifAbsent: () => 1);
    try {
      return await pool.send(request);
    } finally {
      if (_sending.update(pool, (n) => n - 1) == 0) {
        _sending.remove(pool);
        if (_replaced.remove(pool)) pool.close();
      }
    }
  }

  void _retire(http.Client pool) {
    if (_sending.containsKey(pool)) {
      _replaced.add(pool);
    } else {
      pool.close();
    }
  }

  /// A copy of [sent] to send again, or null when it may not go twice: a
  /// write, or a body that was a stream and is spent.
  static http.BaseRequest? _again(http.BaseRequest sent) {
    final read = sent is ReadRequest || sent.method == 'GET' || sent.method == 'HEAD';
    if (!read || sent is! http.Request) return null;
    final trigger = switch (sent) {
      http.Abortable(:final abortTrigger) => abortTrigger,
      _ => null,
    };
    return ReadRequest(sent.method, sent.url, abortTrigger: trigger)
      ..headers.addAll(sent.headers)
      ..bodyBytes = sent.bodyBytes
      ..followRedirects = sent.followRedirects
      ..maxRedirects = sent.maxRedirects
      ..persistentConnection = sent.persistentConnection;
  }

  @override
  void close() {
    _closed = true;
    _pool.close();
  }
}
