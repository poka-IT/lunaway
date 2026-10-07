import 'package:integration_test/integration_test_driver.dart';

/// The host side of the integration tests run under `flutter drive`: in a
/// browser, with chromedriver on port 4444 (`fvm flutter drive -d
/// web-server --driver test_driver/integration_test.dart --target` and the
/// test's path), or on a phone in a profile build, for timings. What a test
/// reports goes to `build/integration_response_data.json`.
Future<void> main() => integrationDriver();
