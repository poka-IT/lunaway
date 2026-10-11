import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:lunaway/core/http/connection_retry.dart';

/// How long an idle connection to a host stays open. dart:io closes one
/// after 15 s: 20 s spent on a place's card, the preview's first request
/// then paid a new connection (name lookup, TCP and TLS), 0.8 to 2.4 s on
/// the emulator against 0.09 s on the open one
/// (`plan/research/125-calcul-itineraire.md`). Under the 2 minutes the
/// API's Caddy keeps one (`infra/caddy/Caddyfile`), so the app does not
/// send on a connection the server has just closed. One a mobile network
/// dropped meanwhile costs a read its second try ([ReconnectingClient]).
const connectionIdle = Duration(seconds: 100);

/// The dart:io client under [appHttpClient].
HttpClient deviceHttpClient() => HttpClient()..idleTimeout = connectionIdle;

http.Client appHttpClient() =>
    ReconnectingClient(_Connections.new, closedEarly: closedBeforeAnswer);

/// One dart:io client and its connections.
final class _Connections extends http.BaseClient {
  final HttpClient _io = deviceHttpClient();
  late final IOClient _client = IOClient(_io);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) => _client.send(request);

  /// Closes the idle connections now and the others once their answer is
  /// read: a pack downloading when another request finds a dead connection
  /// goes on.
  @override
  void close() => _io.close();
}

/// Whether [error], from [IOClient.send], is a connection that closed or
/// broke before any answer: reset, closed, broken pipe, aborted, timed
/// out. A refused connection, a failed name lookup, a TLS failure or a
/// request its caller cancelled are not.
bool closedBeforeAnswer(Object error) {
  // IOClient's socket failures implement SocketException.
  if (error is SocketException) {
    final code = error.osError?.errorCode;
    return code != null && _brokenCodes.contains(code);
  }
  if (error is! http.ClientException || error is http.RequestAbortedException) return false;
  // dart:io reports a failure of the connection it was reading as an
  // HttpException, which IOClient turns into a ClientException: only its
  // message is left, the system's words for the socket's error.
  return _closedMessages.any(error.message.startsWith);
}

/// The system's error codes for a connection reset, closed, broken or
/// timed out.
final Set<int> _brokenCodes = Platform.isWindows
    // WSAECONNABORTED, WSAECONNRESET, WSAENOTCONN, WSAESHUTDOWN, WSAETIMEDOUT
    ? const {10053, 10054, 10057, 10058, 10060}
    : Platform.isMacOS || Platform.isIOS
    // EPIPE, ECONNABORTED, ECONNRESET, ENOTCONN, ETIMEDOUT
    ? const {32, 53, 54, 57, 60}
    // Linux and Android: EPIPE, ECONNABORTED, ECONNRESET, ENOTCONN, ETIMEDOUT
    : const {32, 103, 104, 107, 110};

/// How dart:io words a connection that ended before the answer, its own
/// messages then the system's, in English as Android, iOS and macOS give
/// them. A Windows in another language may word them in its own; such a
/// failure then does not go again.
const _closedMessages = [
  'Connection closed before full header was received',
  'Connection closed before response was received',
  'Socket closed before request was sent',
  'Read failed',
  'Write failed',
  'Connection reset by peer',
  'Broken pipe',
  'Software caused connection abort',
  'Connection timed out',
  'Operation timed out',
  'Socket is not connected',
  'Transport endpoint is not connected',
  'An existing connection was forcibly closed',
  'An established connection was aborted',
];
