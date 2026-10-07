import 'package:integration_test/integration_test_driver.dart';

/// The host side of the integration tests run in a browser, with
/// chromedriver on port 4444: `fvm flutter drive -d web-server --driver
/// test_driver/integration_test.dart --target` and the test's path.
Future<void> main() => integrationDriver();
