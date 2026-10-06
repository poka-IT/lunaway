import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:logging/logging.dart';
import 'package:lunaway/core/geo/geo.dart';
import 'package:lunaway/core/navigation_apps.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

part 'external_actions.g.dart';

final _log = Logger('external');

/// A web page link from the data (a website, a source page), or null when
/// it is not one: only http and https with a host. A bare domain gets
/// https. Never throws on a malformed value.
Uri? webLink(String? raw) {
  final text = raw?.trim();
  if (text == null || text.isEmpty) return null;
  final candidate = text.contains('://') ? text : 'https://$text';
  final uri = Uri.tryParse(candidate);
  if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https') || uri.host.isEmpty) {
    return null;
  }
  return uri;
}

/// The phone numbers in a phone field: sources separate several numbers by
/// semicolons. Spaces, dots and dashes go; a leading + stays. Empty parts
/// and parts without a digit are dropped.
List<String> phoneNumbers(String? raw) => [
  for (final part in (raw ?? '').split(';'))
    if (part.trim() case final p when RegExp(r'\d').hasMatch(p))
      (p.startsWith('+') ? '+' : '') + p.replaceAll(RegExp(r'[^\d]'), ''),
];

/// What the app hands to other apps: web pages, calls, directions and the
/// share sheet. Each method builds its link itself or checks it: a value
/// from the data can never make the app open a file, a custom scheme or a
/// protocol handler (on Windows, `ShellExecute` would run it).
abstract interface class ExternalActions {
  /// Opens a web page; refuses anything but http and https with a host.
  Future<bool> openUrl(Uri url);

  /// Starts a call to [number].
  Future<bool> dial(String number);

  /// Hands a car route to [to] to [app], from [from] when known.
  Future<bool> navigate(NavigationApp app, LatLng to, {LatLng? from, String? label});

  /// Whether [app] is installed, as far as the platform can tell.
  Future<bool> canNavigateWith(NavigationApp app);

  Future<void> share(String text, {String? subject, Rect? origin});
}

final class PlatformExternalActions implements ExternalActions {
  const new();

  static bool isWebPage(Uri url) =>
      (url.scheme == 'http' || url.scheme == 'https') && url.host.isNotEmpty;

  @override
  Future<bool> openUrl(Uri url) async {
    if (!isWebPage(url)) {
      _log.warning('refused to open a non-web link: ${url.scheme}');
      return false;
    }
    return await _launch(url);
  }

  @override
  Future<bool> dial(String number) async {
    final digits = phoneNumbers(number).firstOrNull;
    if (digits == null) return false;
    return await _launch(Uri(scheme: 'tel', path: digits));
  }

  @override
  Future<bool> navigate(NavigationApp app, LatLng to, {LatLng? from, String? label}) => _launch(
    app.routeTo(to, platform: defaultTargetPlatform, web: kIsWeb, from: from, label: label),
  );

  @override
  Future<bool> canNavigateWith(NavigationApp app) async {
    final check = app.installCheck(platform: defaultTargetPlatform, web: kIsWeb);
    if (check == null) return true;
    try {
      return await canLaunchUrl(check);
    } on Object {
      return false;
    }
  }

  Future<bool> _launch(Uri url) async {
    try {
      return await launchUrl(url, mode: LaunchMode.externalApplication);
    } on Object catch (e) {
      _log.info('could not open a ${url.scheme} link: $e');
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
