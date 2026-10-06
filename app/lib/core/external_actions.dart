import 'dart:ui';

import 'package:logging/logging.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

part 'external_actions.g.dart';

final _log = Logger('external');

/// What the app hands to other apps: links and the share sheet. Behind an
/// interface so widget tests check the request without leaving the test.
abstract interface class ExternalActions {
  /// Opens [url] in the app that handles it; false when none could.
  Future<bool> openUrl(Uri url);

  Future<void> share(String text, {String? subject, Rect? origin});
}

final class PlatformExternalActions implements ExternalActions {
  const new();

  @override
  Future<bool> openUrl(Uri url) async {
    try {
      return await launchUrl(url, mode: LaunchMode.externalApplication);
    } on Object catch (e) {
      _log.info('could not open $url: $e');
      return false;
    }
  }

  @override
  Future<void> share(String text, {String? subject, Rect? origin}) => SharePlus.instance.share(
    ShareParams(text: text, subject: subject, sharePositionOrigin: origin),
  );
}

// keepAlive: stateless, wired once.
@Riverpod(keepAlive: true)
ExternalActions externalActions(Ref ref) => const PlatformExternalActions();
