import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'package:lunaway/features/account/data/device_keys.dart';
import 'package:lunaway/features/account/data/p256.dart';
import 'package:lunaway/features/account/data/secret_store.dart';
import 'package:web/web.dart' as web;

/// The browser's device keys: WebCrypto makes the key non-extractable and
/// IndexedDB keeps the key object itself. No script, not even one running
/// on lunaway.net, can read the private half: it can only ask the browser
/// to sign while the page is open. Clearing the site's data forgets it.
DeviceKeys platformDeviceKeys(SecretStore secrets) => WebCryptoDeviceKeys();

final class WebCryptoDeviceKey implements DeviceKey {
  new(this._pair, this.publicJwk);

  final JSObject _pair;

  @override
  final PublicJwk publicJwk;

  @override
  Future<Uint8List> sign(Uint8List message) async {
    final private = _pair.getProperty<web.CryptoKey>('privateKey'.toJS);
    final signature = await web.window.crypto.subtle
        .sign(_algorithm({'name': 'ECDSA', 'hash': 'SHA-256'}), private, message.toJS)
        .toDart;
    // WebCrypto answers raw r || s, the form the API prefers.
    return (signature! as JSArrayBuffer).toDart.asUint8List();
  }
}

JSObject _algorithm(Map<String, String> fields) {
  final o = JSObject();
  for (final e in fields.entries) {
    o.setProperty(e.key.toJS, e.value.toJS);
  }
  return o;
}

final class WebCryptoDeviceKeys implements DeviceKeys {
  static const _database = 'lunaway_keys';
  static const _store = 'keys';
  static const _slot = 'device';

  @override
  Future<DeviceKey?> load() async {
    final db = await _open();
    try {
      final stored = await _request(
        db.transaction(_store.toJS, 'readonly').objectStore(_store).get(_slot.toJS),
      );
      if (stored == null || stored.isUndefinedOrNull) return null;
      return await _fromPair(stored as JSObject);
    } finally {
      db.close();
    }
  }

  @override
  Future<DeviceKey> generate() async {
    final pair = await web.window.crypto.subtle
        .generateKey(
          _algorithm({'name': 'ECDSA', 'namedCurve': 'P-256'}),
          // Not extractable: the private key can sign, never be read out.
          false,
          ['sign'.toJS, 'verify'.toJS].toJS,
        )
        .toDart;
    return await _fromPair(pair! as JSObject);
  }

  @override
  Future<void> save(DeviceKey key) async {
    final db = await _open();
    try {
      await _request(
        db
            .transaction(_store.toJS, 'readwrite')
            .objectStore(_store)
            .put((key as WebCryptoDeviceKey)._pair, _slot.toJS),
      );
    } finally {
      db.close();
    }
  }

  @override
  Future<void> delete() async {
    final db = await _open();
    try {
      await _request(
        db.transaction(_store.toJS, 'readwrite').objectStore(_store).delete(_slot.toJS),
      );
    } finally {
      db.close();
    }
  }

  static Future<WebCryptoDeviceKey> _fromPair(JSObject pair) async {
    final public = pair.getProperty<web.CryptoKey>('publicKey'.toJS);
    final jwk = await web.window.crypto.subtle.exportKey('jwk', public).toDart;
    final object = jwk! as JSObject;
    return WebCryptoDeviceKey(
      pair,
      PublicJwk(
        x: object.getProperty<JSString>('x'.toJS).toDart,
        y: object.getProperty<JSString>('y'.toJS).toDart,
      ),
    );
  }

  static Future<web.IDBDatabase> _open() {
    final done = Completer<web.IDBDatabase>();
    final request = web.window.indexedDB.open(_database, 1);
    request
      ..onupgradeneeded = ((web.Event _) {
        (request.result! as web.IDBDatabase).createObjectStore(_store);
      }).toJS
      ..onsuccess = ((web.Event _) => done.complete(request.result! as web.IDBDatabase)).toJS
      ..onerror = ((web.Event _) => done.completeError(
        StateError('IndexedDB: ${request.error?.message}'),
      )).toJS;
    return done.future;
  }

  static Future<JSAny?> _request(web.IDBRequest request) {
    final done = Completer<JSAny?>();
    request
      ..onsuccess = ((web.Event _) => done.complete(request.result)).toJS
      ..onerror = ((web.Event _) => done.completeError(
        StateError('IndexedDB: ${request.error?.message}'),
      )).toJS;
    return done.future;
  }
}
