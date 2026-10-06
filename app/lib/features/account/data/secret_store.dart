import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:logging/logging.dart';

final _log = Logger('secrets');

/// Where the account's secrets live on this device: the device key, the
/// session token, and what the app remembers of the account. Never in the
/// databases, which the device backups carry.
abstract interface class SecretStore {
  Future<String?> read(String key);

  Future<void> write(String key, String value);

  Future<void> delete(String key);
}

/// The system's protected storage, through flutter_secure_storage:
///
/// - Android: values encrypted with a key held by the Android Keystore,
///   left out of the backups (the backup rules list the user database
///   only), and reset if that key is lost;
/// - iOS: the Keychain, readable after the first unlock, on this device
///   only (never copied to a new phone or to iCloud);
/// - macOS: the login keychain, which needs no signing entitlement;
/// - Windows: files encrypted with the user's DPAPI key;
/// - web: the site's local storage, encrypted with a key kept beside it,
///   which protects nothing from a script of the page. The web keeps its
///   device key elsewhere (WebCrypto, `device_keys_web.dart`); only the
///   session token and the account's name live here.
final class PlatformSecretStore implements SecretStore {
  const new();

  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(storageNamespace: 'lunaway_account'),
    iOptions: IOSOptions(
      accountName: 'lunaway_account',
      accessibility: KeychainAccessibility.first_unlock_this_device,
    ),
    mOptions: MacOsOptions(
      accountName: 'lunaway_account',
      accessibility: KeychainAccessibility.first_unlock_this_device,
      usesDataProtectionKeychain: false,
    ),
    webOptions: WebOptions(publicKey: 'lunaway_account'),
  );

  @override
  Future<String?> read(String key) async {
    try {
      return await _storage.read(key: key);
    } on Object catch (error, stack) {
      // An unreadable value (a keystore reset, a restored backup) is a value
      // this device does not have: the account can still come back with
      // its recovery code.
      _log.warning('could not read $key', error, stack);
      return null;
    }
  }

  @override
  Future<void> write(String key, String value) => _storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}

/// Secrets in memory: the tests, and a run whose storage failed.
final class MemorySecretStore implements SecretStore {
  new([Map<String, String>? values]) : values = values ?? {};

  @visibleForTesting
  final Map<String, String> values;

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;

  @override
  Future<void> delete(String key) async => values.remove(key);
}
