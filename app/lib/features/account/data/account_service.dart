import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:logging/logging.dart';
import 'package:lunaway/features/account/data/account_operations.dart';
import 'package:lunaway/features/account/data/device_keys.dart';
import 'package:lunaway/features/account/data/p256.dart';
import 'package:lunaway/features/account/data/secret_store.dart';
import 'package:lunaway/features/account/domain/account.dart';
import 'package:lunaway/features/places/data/graphql/graphql_client.dart';
import 'package:lunaway/features/places/data/graphql/operations.dart';
import 'package:meta/meta.dart';

final _log = Logger('account');

/// The device has no account, and the caller did not allow one to be made:
/// browsing and reading never create an account.
final class NoAccountException implements Exception {
  const new();

  @override
  String toString() => 'NoAccountException';
}

/// The key of this device no longer opens the account it held (the device
/// was removed from another one, or the account was deleted on
/// lunaway.net): the device forgot it, and nothing was sent.
final class AccountLostException implements Exception {
  const new();

  @override
  String toString() => 'AccountLostException';
}

/// The server answered a sign-in challenge the app will not sign.
final class BadChallengeException implements Exception {
  const new(this.reason);

  final String reason;

  @override
  String toString() => 'BadChallengeException: $reason';
}

/// A session the server handed out.
@immutable
final class Session {
  const new({required this.token, required this.expiresAt, required this.openedAt});

  final String token;
  final DateTime expiresAt;

  /// When the signed sign-in that opened it happened, on this device's
  /// clock: the server asks for one younger than ten minutes before the
  /// actions that could lock the owner out.
  final DateTime openedAt;

  String toStored() => jsonEncode({
    'token': token,
    'expiresAt': expiresAt.toUtc().toIso8601String(),
    'openedAt': openedAt.toUtc().toIso8601String(),
  });

  static Session? fromStored(String? stored) {
    if (stored == null) return null;
    try {
      final m = jsonDecode(stored) as Map<String, dynamic>;
      return Session(
        token: m['token'] as String,
        expiresAt: DateTime.parse(m['expiresAt'] as String),
        openedAt: DateTime.parse(m['openedAt'] as String),
      );
    } on Object {
      return null;
    }
  }
}

/// What the device holds of its account.
@immutable
final class StoredAccount {
  const new({required this.account, this.recoveryCardAt});

  final Account account;

  /// When a recovery card was made or used on this device; null when the
  /// device never saw one (the server does not say whether a code exists).
  final DateTime? recoveryCardAt;
}

/// Something changed in the account the device holds.
sealed class AccountEvent {
  const new();
}

/// A sign-in or a read brought the account; [created] when this sign-in
/// made it (the first contribution of this device).
final class AccountSignedIn extends AccountEvent {
  const new(this.account, {required this.created});

  final Account account;
  final bool created;
}

/// The device holds no account any more (signed out, deleted); [lost] when
/// it went without the user asking here (removed from another device,
/// deleted elsewhere).
final class AccountGone extends AccountEvent {
  const new({this.lost = false});

  final bool lost;
}

/// The account without e-mail: a key made on the device signs a challenge
/// from the server, which hands out a session (`Authorization: Bearer`).
///
/// Nothing here runs at first launch: the key and the account are made the
/// first time a caller passes `create: true` (a contribution, the sync of
/// the favourites). A session the server refused is replaced by a new
/// signed sign-in, once, and the request sent again; the actions that need
/// a recent sign-in (`fresh`) sign in again first when the session is older
/// than [freshFor].
final class AccountService {
  new({
    required this.client,
    required this.keys,
    required this.secrets,
    required this.locale,
    this.clock = DateTime.now,
  });

  final GraphQLClient client;
  final DeviceKeys keys;
  final SecretStore secrets;

  /// The app's language (`fr` or `en`): the language of a new pseudonym.
  final String Function() locale;
  final DateTime Function() clock;

  /// The server asks for ten minutes; a little less leaves room for a slow
  /// network and a clock that drifts.
  static const freshFor = Duration(minutes: 8);

  static const _sessionSlot = 'session';
  static const _accountSlot = 'account';
  static const _recoverySlot = 'recovery_card';

  final _events = StreamController<AccountEvent>.broadcast();
  Session? _session;
  bool _loaded = false;
  Future<Session>? _signingIn;

  /// Counts the times the device forgot its account: a sign-in that began
  /// before keeps nothing of its answer.
  int _generation = 0;

  Stream<AccountEvent> get events => _events.stream;

  /// The account the device holds, read from its protected storage; null
  /// when it has no key (never contributed, signed out, a restored backup
  /// without its keys).
  Future<StoredAccount?> restore() async {
    final key = await keys.load();
    if (key == null) return null;
    final account = Account.fromJson(_decode(await secrets.read(_accountSlot)));
    if (account == null) return null;
    final card = DateTime.tryParse(await secrets.read(_recoverySlot) ?? '');
    return StoredAccount(account: account, recoveryCardAt: card);
  }

  /// Whether the device has a key, so a request can sign in without making
  /// an account.
  Future<bool> hasKey() async => await keys.load() != null;

  Future<Session?> _current() async {
    if (!_loaded) {
      _session = Session.fromStored(await secrets.read(_sessionSlot));
      _loaded = true;
    }
    return _session;
  }

  /// The `Authorization` of a public read: the session's when there is one.
  /// A read never signs in; a stale token is ignored by the server.
  Future<Map<String, String>> readHeaders() async {
    final session = await _current();
    return session == null ? const {} : _headers(session);
  }

  static Map<String, String> _headers(Session s) => {'authorization': 'Bearer ${s.token}'};

  /// Sends [operation] as the account. Without an account it makes one when
  /// [create] allows it, and throws [NoAccountException] otherwise.
  Future<T> run<T>(
    GraphQLOperation<T> operation, {
    Map<String, Object?> variables = const {},
    bool create = false,
    bool fresh = false,
  }) async {
    var session = await _current();
    if (session == null || (fresh && clock().difference(session.openedAt) > freshFor)) {
      session = await _signInOnce(create: create, replacing: session);
    }
    try {
      return await client.execute(operation, variables, _headers(session));
    } on GraphQLResponseException catch (e) {
      if (!e.hasCode(GraphQLError.unauthenticated)) rethrow;
      // An expired or revoked session, or one too old for this action: a
      // new signed sign-in, then the same request once more.
      session = await _signInOnce(create: create, replacing: session);
      return await client.execute(operation, variables, _headers(session));
    }
  }

  /// A session for a request made outside GraphQL (a photo upload), signing
  /// in when there is none.
  Future<Map<String, String>> sessionHeaders({bool create = false}) async {
    final session = await _current() ?? await _signInOnce(create: create, replacing: null);
    return _headers(session);
  }

  /// After a request outside GraphQL was refused for its session: a new
  /// signed sign-in, whose headers the caller sends again.
  Future<Map<String, String>> renewSession({bool create = false}) async =>
      _headers(await _signInOnce(create: create, replacing: await _current()));

  /// Signs in once for every caller that needs it now: two requests refused
  /// together share one new session.
  Future<Session> _signInOnce({required bool create, required Session? replacing}) async {
    final current = _session;
    if (current != null && replacing != null && current.token != replacing.token) {
      return current;
    }
    final running = _signingIn;
    if (running != null) {
      try {
        return await running;
      } on NoAccountException {
        // The sign-in under way was not allowed to make the account; this
        // caller is.
        if (!create) rethrow;
      }
    }
    return await (_signingIn ??= _signIn(create: create).whenComplete(() => _signingIn = null));
  }

  Future<Session> _signIn({required bool create}) async {
    final generation = _generation;
    var key = await keys.load();
    if (key == null) {
      if (!create) throw const NoAccountException();
      key = await keys.generate();
      // Kept before the server hears of it: if the answer is lost, the next
      // sign-in with the same key finds the account instead of making a
      // second one.
      await keys.save(key);
    }
    final previous = Account.fromJson(_decode(await secrets.read(_accountSlot)));
    final (nonce, signature) = await _answer(key);
    // Only a device that holds no account and may make one lets the server
    // create it. Behind a key that held an account here, an unknown key
    // means the account is gone (removed from another device, deleted
    // elsewhere): the server answers NOT_FOUND and makes nothing, rather
    // than a fresh account nobody asked for. A key with no account kept is
    // this device's own first contribution, whose earlier sign-in may never
    // have reached the server: that one may make it.
    final SignInResult result;
    try {
      result = await client.execute(signInOperation, {
        'jwk': key.publicJwk.toJson(),
        'nonce': nonce,
        'signature': signature,
        'locale': locale(),
        'createIfUnknown': create && previous == null,
      });
    } on GraphQLResponseException catch (e) {
      // The server says UNKNOWN_KEY; a server before that reason said
      // NOT_FOUND alone for the same case. Any other reason is not a lost
      // account.
      final reason = e.withCode(GraphQLError.notFound)?.reason;
      if (reason != null && reason != GraphQLError.unknownKey) rethrow;
      if (!e.hasCode(GraphQLError.notFound)) rethrow;
      if (generation != _generation || previous == null) throw const NoAccountException();
      _log.warning('the device key no longer opens its account');
      await _forget(lost: true);
      throw const AccountLostException();
    }
    if (generation != _generation) {
      // Signed out or deleted while this sign-in ran: its session belongs
      // to an account the device no longer holds.
      throw const NoAccountException();
    }
    // An API older than `createIfUnknown` makes an account for any key it
    // does not know. Behind a key that held an account here, a new one
    // means the old one is gone: the account just made was not asked for,
    // it goes at once, and so does the key.
    if (previous != null && result.created && result.account.id != previous.id) {
      _log.warning('the device key no longer opens its account');
      try {
        await client.execute(deleteAccountOperation, const {}, {
          'authorization': 'Bearer ${result.token}',
        });
      } on Object catch (e) {
        _log.info('the account made by mistake was not deleted: $e');
      }
      await _forget(lost: true);
      throw const AccountLostException();
    }
    // An account other than the one kept, which the server did not create,
    // is the one the key opens: the account kept here was stale, and the
    // server's answer stands.
    await _keep(result);
    // A device that never saw this account greets it as new, even when a
    // lost answer made the server create it on an earlier attempt.
    _events.add(AccountSignedIn(result.account, created: result.created || previous == null));
    return _session!;
  }

  /// The nonce of a fresh challenge and the device key's signature of it.
  /// The app signs `lunaway-auth:v1:<nonce>` that it builds itself, never a
  /// text the server sends: no answer can make the key sign anything else.
  Future<(String, String)> _answer(DeviceKey key) async {
    final challenge = await client.execute(authChallengeOperation);
    final nonce = challenge.nonce;
    if (!RegExp(r'^[A-Za-z0-9_-]{43}$').hasMatch(nonce)) {
      throw const BadChallengeException('the nonce is not 32 bytes of base64url');
    }
    final message = '${P256.challengePrefix}$nonce';
    if (challenge.message != message) {
      throw const BadChallengeException('the message is not the prefix and the nonce');
    }
    final signature = await key.sign(Uint8List.fromList(utf8.encode(message)));
    return (nonce, P256.b64url(signature));
  }

  Future<void> _keep(SignInResult result) async {
    final session = Session(
      token: result.token,
      expiresAt: result.expiresAt,
      openedAt: clock().toUtc(),
    );
    await secrets.write(_sessionSlot, session.toStored());
    await secrets.write(_accountSlot, jsonEncode(result.account.toJson()));
    _session = session;
    _loaded = true;
  }

  /// Signs in now (making the account when [create]) and returns it.
  Future<Account> ensureAccount({bool create = true}) async {
    await _current() ?? await _signInOnce(create: create, replacing: null);
    return (await refresh()).account;
  }

  /// The account as the server sees it now, kept on the device.
  Future<({Account account, List<Author> muted})> refresh() async {
    final read = await run(myAccountOperation);
    await secrets.write(_accountSlot, jsonEncode(read.account.toJson()));
    _events.add(AccountSignedIn(read.account, created: false));
    return read;
  }

  Future<Account> rename(String pseudonym) async {
    final account = await run(updateProfileOperation, variables: {'pseudonym': pseudonym});
    await secrets.write(_accountSlot, jsonEncode(account.toJson()));
    _events.add(AccountSignedIn(account, created: false));
    return account;
  }

  /// A new recovery code, replacing any earlier one. It is shown once; the
  /// device keeps only the date, to say a card exists.
  Future<String> createRecoveryCode() async {
    final code = await run(createRecoveryCodeOperation, fresh: true);
    // The earlier card stopped working: until the new one is kept, the
    // device holds none.
    await secrets.delete(_recoverySlot);
    return code;
  }

  /// The user has the card in hand: from now on the device says a card
  /// exists. Written only then, so a card closed before it was kept is not
  /// counted.
  Future<void> recoveryCardKept() =>
      secrets.write(_recoverySlot, clock().toUtc().toIso8601String());

  /// Attaches a new key of this device to the account of [code] and signs
  /// in with it; with [revokeOthers], every other device of the account is
  /// detached (a lost or stolen phone).
  Future<Account> recover(String code, {required bool revokeOthers}) async {
    // A sign-in already under way, with the key being replaced, keeps
    // nothing of its answer.
    _generation++;
    final key = await keys.generate();
    final (nonce, signature) = await _answer(key);
    final result = await client.execute(recoverAccountOperation, {
      'code': code,
      'jwk': key.publicJwk.toJson(),
      'nonce': nonce,
      'signature': signature,
      'revokeOtherDevices': revokeOthers,
    });
    await keys.save(key);
    await _keep(result);
    await secrets.write(_recoverySlot, clock().toUtc().toIso8601String());
    _events.add(AccountSignedIn(result.account, created: false));
    return result.account;
  }

  Future<List<Device>> devices() => run(myDevicesOperation);

  Future<void> revokeDevice(String id) =>
      run(revokeDeviceOperation, variables: {'id': id}, fresh: true);

  Future<int> signOutElsewhere() => run(signOutElsewhereOperation, fresh: true);

  /// Ends the session and forgets the key: without its recovery code, the
  /// account cannot come back to this device.
  Future<void> signOut() async {
    final session = await _current();
    if (session != null) {
      try {
        await client.execute(signOutOperation, const {}, _headers(session));
      } on Object catch (e) {
        // Offline or already expired: the token is forgotten below and
        // expires on the server by itself.
        _log.info('sign out not confirmed by the server: $e');
      }
    }
    await _forget();
  }

  /// Deletes the account on the server, then everything the device held of
  /// it.
  Future<void> deleteAccount() async {
    await run(deleteAccountOperation, fresh: true);
    await _forget();
  }

  Future<void> _forget({bool lost = false}) async {
    _generation++;
    await keys.delete();
    await secrets.delete(_sessionSlot);
    await secrets.delete(_accountSlot);
    await secrets.delete(_recoverySlot);
    _session = null;
    _loaded = true;
    _events.add(AccountGone(lost: lost));
  }

  Future<void> dispose() => _events.close();

  static Object? _decode(String? stored) {
    if (stored == null) return null;
    try {
      return jsonDecode(stored);
    } on FormatException {
      return null;
    }
  }
}
