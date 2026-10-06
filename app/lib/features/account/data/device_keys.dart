import 'dart:convert';
import 'dart:typed_data';

import 'package:lunaway/features/account/data/p256.dart';
import 'package:lunaway/features/account/data/secret_store.dart';

/// A device key: the account's credential on this device. Its private half
/// never leaves the device; the server keeps the public half.
abstract interface class DeviceKey {
  PublicJwk get publicJwk;

  /// The ES256 signature of [message], raw `r || s` (64 bytes).
  Future<Uint8List> sign(Uint8List message);
}

/// Makes, keeps and forgets the key of this device.
abstract interface class DeviceKeys {
  /// The kept key; null when this device has none.
  Future<DeviceKey?> load();

  /// A new key, not kept yet: a recovery tries it before it replaces the
  /// current one.
  Future<DeviceKey> generate();

  /// Keeps [key] as this device's key, in place of any other.
  Future<void> save(DeviceKey key);

  /// Forgets the key (sign out, account deleted).
  Future<void> delete();
}

/// A key computed in Dart and kept in the [SecretStore]: Android, iOS,
/// macOS and Windows.
final class SoftwareDeviceKey implements DeviceKey {
  new(this._d) : publicJwk = P256.jwkOf(_d);

  final BigInt _d;

  @override
  final PublicJwk publicJwk;

  @override
  Future<Uint8List> sign(Uint8List message) async => P256.sign(_d, message);

  String toStored() =>
      jsonEncode({'d': P256.b64url(P256.unsigned(_d, 32)), 'x': publicJwk.x, 'y': publicJwk.y});

  /// Null for a damaged value: the device then has no key.
  static SoftwareDeviceKey? fromStored(String stored) {
    try {
      final json = jsonDecode(stored) as Map<String, dynamic>;
      final d = P256.fromB64url(json['d'] as String);
      if (d == null || d.length != 32) return null;
      final key = SoftwareDeviceKey(P256.scalar(d));
      // The stored public half must be the private half's: anything else
      // is a damaged value.
      if (key.publicJwk.x != json['x'] || key.publicJwk.y != json['y']) return null;
      return key;
    } on Object {
      return null;
    }
  }
}

final class SoftwareDeviceKeys implements DeviceKeys {
  new(this._secrets);

  final SecretStore _secrets;

  static const _slot = 'device_key';

  @override
  Future<DeviceKey?> load() async {
    final stored = await _secrets.read(_slot);
    return stored == null ? null : SoftwareDeviceKey.fromStored(stored);
  }

  @override
  Future<DeviceKey> generate() async => SoftwareDeviceKey(P256.generatePrivate());

  @override
  Future<void> save(DeviceKey key) => _secrets.write(_slot, (key as SoftwareDeviceKey).toStored());

  @override
  Future<void> delete() => _secrets.delete(_slot);
}
