import 'package:http/http.dart' as http;

/// A browser keeps its connections itself.
http.Client appHttpClient() => http.Client();
