import 'package:http/http.dart' as http;

/// A browser keeps its connections itself. Its failed fetch does not say
/// why it failed, so a closed connection cannot be told from a refusal.
http.Client appHttpClient() => http.Client();
