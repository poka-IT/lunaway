import 'package:lunaway/features/account/data/device_keys.dart';
import 'package:lunaway/features/account/data/secret_store.dart';

/// The device keys of Android, iOS, macOS and Windows: computed in Dart,
/// kept in the system's protected storage.
DeviceKeys platformDeviceKeys(SecretStore secrets) =>
    SoftwareDeviceKeys(secrets);
