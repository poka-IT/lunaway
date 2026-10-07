import 'package:lunaway/core/location/browser_location.dart';

/// Native builds have no browser; the provider never makes this one.
final class PlatformBrowserLocation implements BrowserLocation {
  const new();

  @override
  Future<BrowserFix> locate() async => const BrowserNoFix();
}
