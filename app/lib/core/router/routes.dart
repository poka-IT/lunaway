/// Paths of the top-level destinations, in the order the navigation shows them,
/// and of the pages under them.
abstract final class AppRoutes {
  static const map = '/map';
  static const favorites = '/favorites';
  static const profile = '/profile';

  /// The account's pages, under the profile.
  static const recoveryCard = '/profile/recovery-card';
  static const recover = '/profile/recover';
  static const contributions = '/profile/contributions';
  static const muted = '/profile/muted';
  static const devices = '/profile/devices';
  static const deleteAccount = '/profile/delete-account';

  /// The offline maps, under the profile.
  static const offlineMaps = '/profile/offline-maps';
}
