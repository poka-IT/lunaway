import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:meta/meta.dart';
import 'package:pointycastle/api.dart'
    show
        KeyParameter,
        ParametersWithRandom,
        PrivateKeyParameter,
        PublicKeyParameter;
import 'package:pointycastle/digests/sha256.dart';
import 'package:pointycastle/ecc/api.dart';
import 'package:pointycastle/ecc/curves/secp256r1.dart';
import 'package:pointycastle/key_generators/api.dart'
    show ECKeyGeneratorParameters;
import 'package:pointycastle/key_generators/ec_key_generator.dart';
import 'package:pointycastle/macs/hmac.dart';
import 'package:pointycastle/random/fortuna_random.dart';
import 'package:pointycastle/signers/ecdsa_signer.dart';

/// ES256 (ECDSA on P-256 with SHA-256) as the Lunaway sign-in speaks it
/// (`schema/auth-vectors.json`): the public key as a JWK with 32-byte
/// coordinates in base64url without padding, the signature as the raw 64
/// bytes `r || s`. Pure Dart (pointycastle, the Bouncy Castle port), so the
/// same code signs on Android, iOS, macOS and Windows and runs in the tests;
/// the browser uses WebCrypto instead (`device_keys_web.dart`).
abstract final class P256 {
  static final ECDomainParameters domain = ECCurve_secp256r1();

  /// The text every sign-in message starts with.
  static const challengePrefix = 'lunaway-auth:v1:';

  /// A new private scalar, from the platform's secure random source.
  static BigInt generatePrivate([Random? random]) {
    final source = random ?? Random.secure();
    final seed = Uint8List.fromList([
      for (var i = 0; i < 32; i++) source.nextInt(256),
    ]);
    final fortuna = FortunaRandom()..seed(KeyParameter(seed));
    final generator = ECKeyGenerator()
      ..init(ParametersWithRandom(ECKeyGeneratorParameters(domain), fortuna));
    final pair = generator.generateKeyPair();
    return pair.privateKey.d!;
  }

  /// The public point of [d].
  static ECPoint publicOf(BigInt d) => (domain.G * d)!;

  /// The public key of [d] as the API takes it.
  static PublicJwk jwkOf(BigInt d) {
    final q = publicOf(d);
    return PublicJwk(
      x: b64url(unsigned(q.x!.toBigInteger()!, 32)),
      y: b64url(unsigned(q.y!.toBigInteger()!, 32)),
    );
  }

  /// The ES256 signature of [message] by [d], raw `r || s`. The message is
  /// hashed here (SHA-256): the caller passes the text, never its digest.
  /// The nonce is derived from the key and the message (RFC 6979), so no
  /// weak random source can leak the key.
  static Uint8List sign(BigInt d, Uint8List message) {
    final signer = ECDSASigner(SHA256Digest(), HMac(SHA256Digest(), 64))
      ..init(true, PrivateKeyParameter<ECPrivateKey>(ECPrivateKey(d, domain)));
    final sig = signer.generateSignature(message) as ECSignature;
    return Uint8List.fromList([...unsigned(sig.r, 32), ...unsigned(sig.s, 32)]);
  }

  /// Whether [signature] (raw `r || s`, or strict DER) is [jwk]'s signature
  /// of [message]. Used to check the app's own signatures against the
  /// shared vectors.
  static bool verify(PublicJwk jwk, Uint8List message, Uint8List signature) {
    final parsed = parseSignature(signature);
    if (parsed == null) return false;
    final ECPoint q;
    try {
      q = domain.curve.createPoint(_int(jwk.xBytes), _int(jwk.yBytes));
    } on Object {
      return false;
    }
    final verifier = ECDSASigner(SHA256Digest())
      ..init(false, PublicKeyParameter<ECPublicKey>(ECPublicKey(q, domain)));
    return verifier.verifySignature(message, parsed);
  }

  /// `r` and `s` of a raw (64 bytes) or strict DER signature; null for
  /// anything else.
  static ECSignature? parseSignature(Uint8List bytes) {
    if (bytes.length == 64) {
      return ECSignature(_int(bytes.sublist(0, 32)), _int(bytes.sublist(32)));
    }
    return _parseDer(bytes);
  }

  /// Strict DER: a SEQUENCE of two minimal positive INTEGERs, short
  /// lengths, nothing after it.
  static ECSignature? _parseDer(Uint8List b) {
    if (b.length < 8 || b[0] != 0x30 || b[1] != b.length - 2 || b[1] >= 0x80)
      return null;
    var i = 2;
    BigInt? integer() {
      if (i + 2 > b.length || b[i] != 0x02) return null;
      final len = b[i + 1];
      if (len == 0 || len >= 0x80 || i + 2 + len > b.length) return null;
      final value = b.sublist(i + 2, i + 2 + len);
      // Negative, or a leading zero that is not needed.
      if (value[0] & 0x80 != 0) return null;
      if (value[0] == 0 && (len == 1 || value[1] & 0x80 == 0)) return null;
      i += 2 + len;
      return _int(value);
    }

    final r = integer();
    final s = integer();
    if (r == null || s == null || i != b.length) return null;
    return ECSignature(r, s);
  }

  /// [value] as [length] big-endian bytes, leading zeros kept.
  static Uint8List unsigned(BigInt value, int length) {
    final out = Uint8List(length);
    var v = value;
    for (var i = length - 1; i >= 0; i--) {
      out[i] = (v & BigInt.from(0xff)).toInt();
      v = v >> 8;
    }
    return out;
  }

  static BigInt _int(List<int> bytes) {
    var v = BigInt.zero;
    for (final b in bytes) {
      v = (v << 8) | BigInt.from(b);
    }
    return v;
  }

  /// A scalar from its 32 big-endian bytes.
  static BigInt scalar(List<int> bytes) => _int(bytes);

  /// base64url without padding (RFC 7515).
  static String b64url(List<int> bytes) =>
      base64Url.encode(bytes).replaceAll('=', '');

  /// Decodes base64url, with or without padding; null for another alphabet
  /// or a malformed value.
  static Uint8List? fromB64url(String text) {
    if (!RegExp(r'^[A-Za-z0-9_-]*={0,2}$').hasMatch(text)) return null;
    try {
      return base64Url.decode(base64Url.normalize(text));
    } on FormatException {
      return null;
    }
  }
}

/// The public half of a device key, as a JWK.
@immutable
final class PublicJwk {
  const new({required this.x, required this.y});

  /// From the JWK of another implementation (WebCrypto's export).
  factory fromJson(Map<String, Object?> json) =>
      PublicJwk(x: json['x']! as String, y: json['y']! as String);

  final String x;
  final String y;

  Uint8List get xBytes => P256.fromB64url(x) ?? Uint8List(0);
  Uint8List get yBytes => P256.fromB64url(y) ?? Uint8List(0);

  /// The JWK the API takes: `kty`, `crv`, `x`, `y`, nothing else (never `d`).
  String toJson() => jsonEncode({'kty': 'EC', 'crv': 'P-256', 'x': x, 'y': y});

  /// The RFC 7638 thumbprint: the server's name for the key.
  String get thumbprint => P256.b64url(
    crypto.sha256
        .convert(utf8.encode('{"crv":"P-256","kty":"EC","x":"$x","y":"$y"}'))
        .bytes,
  );

  @override
  bool operator ==(Object other) =>
      other is PublicJwk && other.x == x && other.y == y;

  @override
  int get hashCode => Object.hash(x, y);
}
