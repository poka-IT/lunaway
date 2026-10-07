import 'package:integration_test/integration_test_driver.dart';

/// Runs an integration test under `flutter drive` (profile builds, for
/// timings) and writes what it reports to
/// `build/integration_response_data.json`.
Future<void> main() => integrationDriver();
