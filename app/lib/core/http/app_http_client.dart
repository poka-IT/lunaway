import 'package:http/http.dart' as http;
import 'package:lunaway/core/http/app_http_client_stub.dart'
    if (dart.library.io) 'package:lunaway/core/http/app_http_client_io.dart'
    as impl;

/// The app's HTTP client: the browser's own in a web page; on a device,
/// one that keeps an idle connection open long enough for the next
/// question of the same screen (`app_http_client_io.dart`).
http.Client appHttpClient() => impl.appHttpClient();
