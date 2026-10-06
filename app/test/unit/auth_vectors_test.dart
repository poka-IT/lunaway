import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:lunaway/features/account/data/device_keys.dart';
import 'package:lunaway/features/account/data/p256.dart';
import 'package:lunaway/features/account/data/secret_store.dart';

/// The app's signer against the vectors the server replays too
/// (`schema/auth-vectors.json`): a key, message or encoding the server
/// would read differently fails here first.
void main() {
  final vectors = jsonDecode(
    File('../schema/auth-vectors.json').readAsStringSync(),
  ) as Map<String, dynamic>;
  final keys = vectors['keys'] as Map<String, dynamic>;
  Map<String, dynamic> key(String name) => keys[name] as Map<String, dynamic>;
  BigInt privateOf(String name) =>
      P256.scalar(P256.fromB64url(key(name)['dBase64url'] as String)!);
  PublicJwk jwkOf(String name) => PublicJwk.fromJson(
    (key(name)['jwk'] as Map<String, dynamic>).cast<String, Object?>(),
  );
  Uint8List bytes(String text) => Uint8List.fromList(utf8.encode(text));

  test('the public key of each vector key is the JWK and thumbprint the server expects', () {
    for (final name in keys.keys) {
      final jwk = P256.jwkOf(privateOf(name));
      final expected = key(name)['jwk'] as Map<String, dynamic>;
      expect(jwk.x, expected['x'], reason: '$name x');
      expect(jwk.y, expected['y'], reason: '$name y');
      expect(
        jwk.thumbprint,
        key(name)['thumbprint'],
        reason: '$name thumbprint',
      );
      final sent = jsonDecode(jwk.toJson()) as Map<String, dynamic>;
      expect(sent, {
        'kty': 'EC',
        'crv': 'P-256',
        'x': expected['x'],
        'y': expected['y'],
      });
      expect(
        sent.containsKey('d'),
        isFalse,
        reason: 'the private key never leaves the device',
      );
    }
  });

  test('the message is the challenge prefix followed by the nonce, as the server builds it', () {
    expect(P256.challengePrefix, vectors['challengePrefix']);
    final nonces = vectors['nonces'] as Map<String, dynamic>;
    final messages = vectors['messages'] as Map<String, dynamic>;
    for (final name in nonces.keys) {
      expect('${P256.challengePrefix}${nonces[name]}', messages[name]);
    }
  });

  test('a signature of the app is 64 raw bytes, base64url without padding, and verifies', () {
    final message = bytes(
      (vectors['messages'] as Map<String, dynamic>)['nonce-1'] as String,
    );
    final signature = P256.sign(privateOf('key-1'), message);
    expect(signature, hasLength(64));
    final sent = P256.b64url(signature);
    expect(sent, isNot(contains('=')));
    expect(sent, matches(RegExp(r'^[A-Za-z0-9_-]+$')));
    expect(P256.verify(jwkOf('key-1'), message, signature), isTrue);
    expect(
      P256.verify(jwkOf('key-2'), message, signature),
      isFalse,
      reason: 'another key does not verify it',
    );
    // Deterministic (RFC 6979): the same key and message sign the same way.
    expect(P256.sign(privateOf('key-1'), message), signature);
  });

  test('the app signs the text itself, not its digest', () {
    final message = bytes(
      (vectors['messages'] as Map<String, dynamic>)['nonce-1'] as String,
    );
    final signature = P256.sign(privateOf('key-1'), message);
    final digestCase = (vectors['invalidSignatures'] as List<dynamic>)
        .cast<Map<String, dynamic>>()
        .firstWhere((c) => c['name'] == 'signed the digest');
    expect(P256.b64url(signature), isNot(digestCase['signature']));
  });

  for (final c
      in (vectors['validSignatures'] as List<dynamic>)
          .cast<Map<String, dynamic>>()) {
    test('accepts the valid vector "${c['name']}"', () {
      final signature = P256.fromB64url(c['signature'] as String);
      expect(signature, isNotNull);
      expect(
        P256.verify(
          jwkOf(c['key'] as String),
          bytes(c['message'] as String),
          signature!,
        ),
        isTrue,
      );
    });
  }

  for (final c
      in (vectors['invalidSignatures'] as List<dynamic>)
          .cast<Map<String, dynamic>>()) {
    test('refuses the invalid vector "${c['name']}": ${c['reason']}', () {
      final signature = P256.fromB64url(c['signature'] as String);
      final ok =
          signature != null &&
          signature.isNotEmpty &&
          P256.verify(
            jwkOf(c['key'] as String),
            bytes(c['message'] as String),
            signature,
          );
      expect(ok, isFalse);
    });
  }

  group('the key kept on the device', () {
    test('comes back from the store as the same key, and a damaged value is no key', () async {
      final secrets = MemorySecretStore();
      final keys = SoftwareDeviceKeys(secrets);
      expect(await keys.load(), isNull);
      final made = await keys.generate();
      expect(
        await keys.load(),
        isNull,
        reason: 'a generated key is not kept until saved',
      );
      await keys.save(made);
      final loaded = await keys.load();
      expect(loaded?.publicJwk, made.publicJwk);
      final message = bytes('lunaway-auth:v1:test');
      expect(
        P256.verify(made.publicJwk, message, await loaded!.sign(message)),
        isTrue,
      );

      secrets.values['device_key'] = secrets.values['device_key']!.replaceFirst(
        '"x":"',
        '"x":"A',
      );
      expect(await keys.load(), isNull);
      secrets.values['device_key'] = 'not json';
      expect(await keys.load(), isNull);
      await keys.delete();
      expect(secrets.values, isEmpty);
    });

    test('two keys made on the device differ', () async {
      final keys = SoftwareDeviceKeys(MemorySecretStore());
      final a = await keys.generate();
      final b = await keys.generate();
      expect(a.publicJwk, isNot(b.publicJwk));
      expect(a.publicJwk.xBytes, hasLength(32));
      expect(a.publicJwk.yBytes, hasLength(32));
    });
  });
}
