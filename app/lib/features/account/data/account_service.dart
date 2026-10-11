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

/// The device changed accounts while a request was under way (another
/// account adopted, the account left or forgotten): the request is not
/// sent again under the account the device holds now, and its answer is
/// not kept.
final class AccountChangedException extends NoAccountException {
  const new();

  @override
  String toString() => 'AccountChangedException';
}

/// The merge was sent and its answer did not come (the network dropped, a
/// timeout, a server error): the server may have made it. Asked again, it
/// answers the same either way ([AccountService.mergeLanded]). With
/// [onDevice], the server made it and the device's storage refused to keep
/// it.
final class MergeUnsettledException implements Exception {
  const new(this.cause, {this.onDevice = false});

  final Object cause;
  final bool onDevice;

  @override
  String toString() => 'MergeUnsettledException(${cause.runtimeType})';
}

/// The key of this device no longer opens the account it held (the device
/// was removed from another one, the account was deleted on lunaway.net,
/// or merged into another account from another device): the device forgot
/// it, and nothing was sent.
final class AccountLostException implements Exception {
  const new({this.mergedInto});

  /// The pseudonym of the account it was merged into, whose recovery card
  /// brings that account here; null when it is simply gone.
  final String? mergedInto;

  @override
  String toString() => 'AccountLostException';
}

/// The device's account was merged into the account opened beside it, and
/// the answer of the merge has not reached the device yet: a request made
/// meanwhile waits, as offline, until the merge is asked again
/// ([AccountService.mergeOnServer]) or given up.
final class AccountMergingException extends GraphQLNetworkException {
  new() : super('the account is being merged into another', null);
}

/// An account opened on this device by its recovery card while the device
/// holds another one: signed in with a new key that the device keeps only
/// once the user chooses to merge, to replace, or gives up.
@immutable
final class ImportedAccount {
  const new({required this.key, required this.session, required this.account});

  /// The new key of this device for the imported account, not kept yet.
  final DeviceKey key;
  final Session session;
  final Account account;

  ImportedAccount withSession(Session session) =>
      ImportedAccount(key: key, session: session, account: account);
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

  /// When the recovery card was made, as last read from the server or kept
  /// when a card was made or used on this device; null when none is known.
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
/// deleted elsewhere), [mergedInto] the pseudonym of the account it was
/// merged into from another device.
final class AccountGone extends AccountEvent {
  const new({this.lost = false, this.mergedInto});

  final bool lost;
  final String? mergedInto;
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

  /// The account this device held before it learnt that account went into
  /// another (`from`, its id; `into` and `intoId`, the pseudonym and the id
  /// of the account it went into): its waiting contributions wait for that
  /// account to come here.
  static const _mergedSlot = 'merged_from';

  /// The account this device's went into, while no account has come to the
  /// device since; null otherwise.
  Future<({String from, String into, String? intoId})?> mergedFrom() async {
    final m = _decode(await secrets.read(_mergedSlot));
    if (m is! Map<String, dynamic>) return null;
    final from = m['from'];
    final into = m['into'];
    if (from is! String || into is! String) return null;
    final intoId = m['intoId'];
    return (from: from, into: into, intoId: intoId is String ? intoId : null);
  }

  /// An account came to the device: the account its own went into, whose
  /// contributions then leave under it, or another one, for which they
  /// never leave.
  Future<void> forgetMergedFrom() => secrets.delete(_mergedSlot);

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
  }) => send(
    (headers) => client.execute(operation, variables, headers),
    refused: (e) => e is GraphQLResponseException && e.hasCode(GraphQLError.unauthenticated),
    create: create,
    fresh: fresh,
  );

  /// Sends a request as the account, [request] given the session's headers
  /// (a GraphQL operation, a photo upload), signing in first when there is
  /// no session, or none recent enough for a [fresh] action. A session the
  /// server [refused] (expired, revoked, too old) is replaced by a new
  /// signed sign-in, then the request goes once more; never under another
  /// account than the one it began with: when the device changed accounts
  /// meanwhile, [AccountChangedException].
  Future<T> send<T>(
    Future<T> Function(Map<String, String> headers) request, {
    required bool Function(Object error) refused,
    bool create = false,
    bool fresh = false,
  }) async {
    final generation = _generation;
    var session = await _current();
    // Read while the device changed accounts: a session of either.
    if (generation != _generation) throw const AccountChangedException();
    if (session == null || (fresh && clock().difference(session.openedAt) > freshFor)) {
      session = await _renew(generation, create: create, replacing: session);
    }
    try {
      return await request(_headers(session));
    } on Object catch (e) {
      if (!refused(e)) rethrow;
      session = await _renew(generation, create: create, replacing: session);
      return await request(_headers(session));
    }
  }

  /// A new session of the account the device held at [generation].
  Future<Session> _renew(
    int generation, {
    required bool create,
    required Session? replacing,
  }) async {
    if (generation == _generation) {
      final session = await _signInOnce(create: create, replacing: replacing);
      if (generation == _generation) return session;
    }
    throw const AccountChangedException();
  }

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
    // The key kept was detached from its account for another to take its
    // place: it opens nothing, and the device is about to switch.
    if (_left) throw const AccountChangedException();
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
      // Merged into another account: the server names it, so the device
      // can say where its account went.
      final error = e.withCode(GraphQLError.notFound);
      final mergedInto = error?.mergedInto;
      final mergedIntoId = error?.mergedIntoId;
      // Merged from this device into the account opened beside it, the
      // answer lost on its way: the key stays, so the merge asked again
      // proves the account and finishes.
      if (mergedIntoId != null && mergedIntoId == _pending?.account.id) {
        throw AccountMergingException();
      }
      _log.warning(
        mergedInto == null
            ? 'the device key no longer opens its account'
            : 'the account of the device key was merged into another',
      );
      if (mergedInto != null) {
        // Its waiting contributions now belong to that account: they wait
        // for it to come to this device (`mergedFrom`).
        await secrets.write(
          _mergedSlot,
          jsonEncode({'from': previous.id, 'into': mergedInto, 'intoId': ?mergedIntoId}),
        );
      }
      await _forget(lost: true, mergedInto: mergedInto);
      throw AccountLostException(mergedInto: mergedInto);
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

  /// The account as the server sees it now, kept on the device, with the
  /// date of its recovery card when the server gave it: that date then
  /// replaces the device's, which only knew the cards made or used here.
  /// [ServerRecoveryCode] is null when the API is older than the date, or
  /// when this device made or used a card while the read was under way
  /// (the answer predates that card).
  Future<({Account account, List<Author> muted, ServerRecoveryCode? recoveryCode})>
  refresh() async {
    final cards = _cardWrites;
    final generation = _generation;
    final read = await run(myAccountOperation);
    // The answer of the account the device left meanwhile is not kept over
    // the one it holds now.
    if (generation != _generation) throw const AccountChangedException();
    await secrets.write(_accountSlot, jsonEncode(read.account.toJson()));
    var card = read.recoveryCode;
    if (card != null && cards == _cardWrites) {
      final at = card.createdAt;
      if (at == null) {
        await secrets.delete(_recoverySlot);
      } else {
        await secrets.write(_recoverySlot, at.toUtc().toIso8601String());
      }
    } else {
      card = null;
    }
    _events.add(AccountSignedIn(read.account, created: false));
    return (account: read.account, muted: read.muted, recoveryCode: card);
  }

  /// Counts the cards this device made or used, so a read of the account
  /// sent before one of them does not bring back the date of the card it
  /// replaced.
  int _cardWrites = 0;

  Future<Account> rename(String pseudonym) async {
    final generation = _generation;
    final account = await run(updateProfileOperation, variables: {'pseudonym': pseudonym});
    if (generation != _generation) throw const AccountChangedException();
    await secrets.write(_accountSlot, jsonEncode(account.toJson()));
    _events.add(AccountSignedIn(account, created: false));
    return account;
  }

  /// A new recovery code, shown once, and the date the device remembers it
  /// by (never the code). From this moment the server holds the new code's
  /// hash only, and the earlier card stops working: the date is written at
  /// once, so the profile says a card exists however the user leaves its
  /// page.
  Future<(String, DateTime)> createRecoveryCode() async {
    final code = await run(createRecoveryCodeOperation, fresh: true);
    _cardWrites++;
    final at = clock();
    try {
      await secrets.write(_recoverySlot, at.toUtc().toIso8601String());
    } on Object catch (e) {
      // The old card is already dead: the new code is shown whatever the
      // storage says, the date is what is lost.
      _log.warning('the date of the recovery card was not kept: $e');
    }
    return (code, at);
  }

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
    _cardWrites++;
    await keys.save(key);
    _left = false;
    await _keep(result);
    await secrets.write(_recoverySlot, clock().toUtc().toIso8601String());
    _events.add(AccountSignedIn(result.account, created: false));
    return result.account;
  }

  /// Opens the account of [code] beside the one the device holds: a new key
  /// is attached to it and signs in, kept in memory only, and the device's
  /// own account stays as it is until the user chooses ([mergeOnServer],
  /// [leaveForReplace], [cancelImport]).
  Future<ImportedAccount> importAccount(String code) async {
    final key = await keys.generate();
    final (nonce, signature) = await _answer(key);
    final result = await client.execute(recoverAccountOperation, {
      'code': code,
      'jwk': key.publicJwk.toJson(),
      'nonce': nonce,
      'signature': signature,
      'revokeOtherDevices': false,
    });
    final imported = ImportedAccount(
      key: key,
      session: Session(token: result.token, expiresAt: result.expiresAt, openedAt: clock().toUtc()),
      account: result.account,
    );
    _pending = imported;
    return imported;
  }

  /// The account opened beside the device's, until the user's choice ends.
  ImportedAccount? _pending;

  /// Whether [imported] has a home on the server; false for an API that
  /// knows no home.
  Future<bool> importedHasHome(ImportedAccount imported) async {
    try {
      return await client.execute(accountHasHomeOperation, const {}, _headers(imported.session));
    } on GraphQLResponseException catch (e) {
      if (e.errors.any((x) => x.unknownField)) return false;
      rethrow;
    }
  }

  /// The text both keys sign to merge the account of [absorbed] into the
  /// account of [into] (`lunaway-merge:v1:`, the API's `merge_message`).
  @visibleForTesting
  static String mergeMessage(String nonce, PublicJwk absorbed, PublicJwk into) =>
      '$mergePrefix$nonce:${absorbed.thumbprint}:${into.thumbprint}';

  static const mergePrefix = 'lunaway-merge:v1:';

  /// Merges the account of this device into [imported] on the server: both
  /// keys sign, the imported account's session must be recent (a signed
  /// sign-in is made again when it is not). Nothing changes on the device:
  /// [adopt] keeps the imported account once the caller has moved what it
  /// holds. [MergeUnsettledException] when the merge was sent and its answer
  /// did not come; asked again, the server answers the same. Any other
  /// failure leaves the merge not made.
  Future<(ImportedAccount, MergeResult)> mergeOnServer(ImportedAccount imported) async {
    final current = await keys.load();
    if (current == null) throw const NoAccountException();
    var target = imported;
    if (clock().difference(target.session.openedAt) > freshFor) {
      target = target.withSession(await _openSession(target.key));
    }
    Future<MergeResult> attempt(ImportedAccount target) async {
      final challenge = await client.execute(authChallengeOperation);
      final nonce = challenge.nonce;
      if (!RegExp(r'^[A-Za-z0-9_-]{43}$').hasMatch(nonce)) {
        throw const BadChallengeException('the nonce is not 32 bytes of base64url');
      }
      final message = Uint8List.fromList(
        utf8.encode(mergeMessage(nonce, current.publicJwk, target.key.publicJwk)),
      );
      final variables = {
        'jwk': current.publicJwk.toJson(),
        'nonce': nonce,
        'absorbedSignature': P256.b64url(await current.sign(message)),
        'signature': P256.b64url(await target.key.sign(message)),
      };
      try {
        return await client.execute(mergeAccountOperation, variables, _headers(target.session));
      } on GraphQLRateLimitedException {
        // Refused before it ran.
        rethrow;
      } on GraphQLResponseException catch (e) {
        // A server error may come after the merge was written.
        if (e.transient) throw MergeUnsettledException(e);
        rethrow;
      } on Object catch (e) {
        throw MergeUnsettledException(e);
      }
    }

    try {
      return (target, await attempt(target));
    } on GraphQLResponseException catch (e) {
      if (!e.hasCode(GraphQLError.unauthenticated)) rethrow;
      // A session too old for a merge, or ended meanwhile: a new signed
      // sign-in of the imported account, then the merge once more.
      target = target.withSession(await _openSession(target.key));
      return (target, await attempt(target));
    }
  }

  /// A session of the account [key] opens, signed now; nothing kept.
  Future<Session> _openSession(DeviceKey key) async {
    final (nonce, signature) = await _answer(key);
    final result = await client.execute(signInOperation, {
      'jwk': key.publicJwk.toJson(),
      'nonce': nonce,
      'signature': signature,
      'locale': locale(),
      'createIfUnknown': false,
    });
    return Session(token: result.token, expiresAt: result.expiresAt, openedAt: clock().toUtc());
  }

  /// Keeps [imported] as this device's account, in place of the one it held
  /// ([account] the imported account as the server last described it). The
  /// key of the account left is forgotten here; a sign-in under way keeps
  /// nothing of its answer.
  Future<void> adopt(ImportedAccount imported, Account account) async {
    _generation++;
    await keys.save(imported.key);
    final session = imported.session;
    await secrets.write(_sessionSlot, session.toStored());
    await secrets.write(_accountSlot, jsonEncode(account.toJson()));
    // The imported account's card was just used here.
    _cardWrites++;
    await secrets.write(_recoverySlot, clock().toUtc().toIso8601String());
    _session = session;
    _loaded = true;
    // Again once the account is written: a sign-in that began during the
    // writes read the key of the account left, and keeps nothing.
    _generation++;
    _pending = null;
    _left = false;
    _events.add(AccountSignedIn(account, created: false));
  }

  /// Whether the device's account went into [imported] already, a merge
  /// whose answer was lost: the device's key signs in, and either opens its
  /// account (not merged), or the server names the account it went into,
  /// or knows the key no more (gone another way: not merged into
  /// [imported]). Throws when the server does not answer: still unknown.
  Future<bool> mergeLanded(ImportedAccount imported) async {
    final current = await keys.load();
    if (current == null) return false;
    try {
      await _openSession(current);
      return false;
    } on GraphQLResponseException catch (e) {
      final error = e.withCode(GraphQLError.notFound);
      if (error == null || error.reason != GraphQLError.unknownKey) rethrow;
      return error.mergedIntoId == imported.account.id;
    }
  }

  /// Detaches this device's key from the account it holds, before another
  /// takes its place without a merge (then [adopt]): the account stays on
  /// the server and its recovery card brings it back; without a card nor
  /// another device, the server deletes it rather than keep it out of
  /// anyone's reach. Detaching needs a recent signed sign-in, as every
  /// action that could lock an owner out. Throws, nothing changed, when the
  /// server did not answer: the device must not forget a key whose account
  /// the server still keeps for it alone.
  Future<void> leaveForReplace() async {
    // Left already, by an attempt that failed after.
    if (_left) return;
    try {
      await run(signOutForgettingDeviceOperation, fresh: true);
    } on AccountLostException {
      // Gone already (removed, deleted or merged elsewhere): nothing left
      // to detach.
    }
    // From here the key kept opens nothing: a request under way under the
    // account left is not sent again under the one adopted, and no sign-in
    // says the account was lost while the device switches.
    _left = true;
    _generation++;
  }

  /// The device's key was detached from its account by [leaveForReplace],
  /// and the device has not switched yet.
  bool _left = false;

  /// [_left], for the replacement to say what remains to do.
  bool get left => _left;

  /// Gives up [imported]: its new key is detached from it, and the device
  /// keeps the account it held. Nothing once [imported] was adopted or
  /// given up already: its key is then the device's, or gone.
  Future<void> cancelImport(ImportedAccount imported) async {
    if (!identical(_pending, imported)) return;
    _pending = null;
    // A replacement that left the account and failed after: the key kept
    // opens nothing, and the next sign-in says so.
    _left = false;
    try {
      var session = imported.session;
      if (clock().difference(session.openedAt) > freshFor) {
        session = await _openSession(imported.key);
      }
      await client.execute(signOutForgettingDeviceOperation, const {}, _headers(session));
    } on Object catch (e) {
      // The imported account then lists one device too many until it is
      // removed from its devices.
      _log.info('the imported account kept this device: ${e.runtimeType}');
    }
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

  Future<void> _forget({bool lost = false, String? mergedInto}) async {
    _generation++;
    _left = false;
    await keys.delete();
    await secrets.delete(_sessionSlot);
    await secrets.delete(_accountSlot);
    await secrets.delete(_recoverySlot);
    _session = null;
    _loaded = true;
    _events.add(AccountGone(lost: lost, mergedInto: mergedInto));
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
