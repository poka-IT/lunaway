import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lunaway/features/account/data/p256.dart';
import 'package:lunaway/features/places/data/demo/persisted_queries.dart';

import '../contract/graphql_validator.dart';
import 'samples.dart';

/// One request the fake API received.
typedef ApiCall = ({String operation, Map<String, Object?> variables, String? token});

/// The Lunaway API in memory, for the widget tests of the account and the
/// community. It does what the real server does that the app relies on:
/// it checks the device's ES256 signature of `lunaway-auth:v1:<nonce>`,
/// makes the account at the first sign-in of an unknown key, wants a
/// session on everything the account does, and records each operation with
/// its variables. Every request and answer is held to
/// `schema/lunaway.graphql`: a drift shows in [violations].
final class FakeApi {
  new({this.level = 0, this.pseudonym = 'Martre du Vercors'});

  static final _schema = SchemaValidator(File('../schema/lunaway.graphql').readAsStringSync());

  /// A valid recovery code (it passes the app's check symbol).
  static const recoveryCode = '2W3Y-9GFA-J1DR-1DGC-WVE0-7C88-CF1';

  int level;
  String pseudonym;

  /// The documents the app named by their hash, as the API keeps them.
  final _persisted = PersistedQueryStore();

  /// No answer at all, as without a network.
  bool offline = false;

  /// While set, the operations in [held] wait for it to complete before
  /// their answer: a slow network, to test what happens meanwhile.
  Completer<void>? hold;
  Set<String> held = {'Confirm'};

  /// Whether the account exists on the server.
  bool get hasAccount => _keys.isNotEmpty;

  final calls = <ApiCall>[];

  /// What the requests and answers broke of the schema. The sample places
  /// of the tests have readable ids (`test-lake`) where the schema wants a
  /// UUID: that one mismatch is the samples', not the app's.
  List<String> get violations => [
    for (final v in _violations)
      if (!RegExp(r': test-[a-z0-9-]+ is not a UUID$').hasMatch(v)) v,
  ];
  final _violations = <String>[];

  /// The JPEG bodies of the photos uploaded.
  final uploads = <Uint8List>[];

  /// The authors the account mutes.
  final muted = <({String id, String pseudonym})>[];

  /// Pseudonyms of other accounts, by id, for the mutes to name them.
  final authors = <String, String>{};

  /// A vending machine of the same kind already within 25 m: the next
  /// `addVendingMachine` is refused with its id, as the server does.
  String? vendingDuplicateOf;

  /// The "still there?" answers about points of interest.
  final poiConfirmations = <Map<String, Object?>>[];

  /// What the account sent, as `myAccount` lists it.
  final confirmations = <Map<String, Object?>>[];
  final reviews = <Map<String, Object?>>[];
  final issues = <Map<String, Object?>>[];
  final submissions = <Map<String, Object?>>[];
  final photos = <Map<String, Object?>>[];

  /// Keys of the account's devices, by thumbprint, with their device id.
  final _keys = <String, String>{};

  /// Sessions of accounts the server made for keys it no longer knew (the
  /// real server makes an account for any unknown key).
  final _strangers = <String>{};

  /// Accounts made that way, then deleted by the app.
  int strangersDeleted = 0;

  /// Every device of the account removed, as from another device: their
  /// keys and sessions stop working.
  void revokeAll() {
    _keys.clear();
    _tokens.clear();
    _revoked = true;
  }

  bool _revoked = false;
  final _tokens = <String, String>{};
  final _nonces = <String>{};
  var _serial = 0;
  final String _accountId = _uuid(1);

  /// The operations received, by name.
  List<String> get operations => [for (final c in calls) c.operation];

  /// Answers as the API did before idempotency keys, `createIfUnknown` and
  /// `PlaceDetailsInput.clear`: it refuses the documents that carry them,
  /// and makes an account for any key it does not know.
  bool older = false;

  /// The operations [older] refused, by name.
  final olderRefusals = <String>[];

  /// The variables of the last [operation] received.
  Map<String, Object?>? last(String operation) =>
      calls.lastWhere((c) => c.operation == operation, orElse: () => _none).variables;

  static const ApiCall _none = (operation: '', variables: {}, token: null);

  static String _uuid(int n) => '00000000-0000-7000-8000-${n.toRadixString(16).padLeft(12, '0')}';

  String _next() => _uuid(1000 + _serial++);

  /// The account as it stands, as `AccountFields` selects it.
  Map<String, Object?> account() => {
    'id': _accountId,
    'pseudonym': pseudonym,
    'trustLevel': level,
    'createdAt': '2026-10-01T08:00:00Z',
    'nextLevel': level >= 4
        ? null
        : {
            'level': level + 1,
            'missing': [
              {'kind': 'ACCOUNT_AGE_DAYS', 'current': 0, 'needed': 3},
              {'kind': 'CONFIRMATIONS', 'current': confirmations.length, 'needed': 3},
            ],
            'instead': {'kind': 'SPONSOR', 'current': 0, 'needed': 1},
          },
  };

  /// Makes the account at [level] already known to the device that signed
  /// in with [token] (a test that starts signed in).
  void addSession(String token, String thumbprint) {
    _keys[thumbprint] = _next();
    _tokens[token] = thumbprint;
  }

  /// The client the app's GraphQL client and photo uploader use; anything
  /// else goes to [fallback] (the demo server's photos).
  http.Client client(http.Client fallback) => MockClient((request) async {
    if (request.url.path.endsWith('/upload')) return await _upload(request);
    if (request.method != 'POST' || !request.url.path.endsWith('/graphql')) {
      return await fallback.send(request).then(http.Response.fromStream);
    }
    final body = jsonDecode(request.body) as Map<String, dynamic>;
    final name = body['operationName'] as String? ?? '';
    final variables = (body['variables'] as Map<String, dynamic>?) ?? const {};
    if (!_handled.contains(name)) {
      return await fallback.send(request).then(http.Response.fromStream);
    }
    final String? document;
    try {
      document = _persisted.documentOf(body);
    } on FormatException {
      return _json(PersistedQueryStore.mismatch);
    }
    if (document == null) return _json(PersistedQueryStore.notFound);
    final query = document;
    if (offline) throw http.ClientException('offline', request.url);
    if (older) {
      // As the API before idempotency keys, `createIfUnknown` and `clear`
      // answered (async-graphql's validation, read on production on
      // 2026-10-06): the document runs nothing.
      final unknown = RegExp(r'\b(idempotencyKey|createIfUnknown):').firstMatch(query)?.group(1);
      final patch = variables['patch'];
      final message = unknown != null
          ? 'Unknown argument "$unknown" on field "x" of type "Mutation".'
          : patch is Map && patch.containsKey('clear')
          ? 'Invalid value for argument "patch", unknown field "clear" of type "PlaceDetailsInput"'
          : null;
      if (message != null) {
        olderRefusals.add(name);
        return _json({
          'data': null,
          'errors': [
            {
              'message': message,
              'extensions': {'code': 'INVALID_INPUT'},
            },
          ],
        });
      }
    }
    final token = request.headers['authorization']?.replaceFirst('Bearer ', '');
    if (held.contains(name)) await hold?.future;
    calls.add((operation: name, variables: variables, token: token));
    for (final e in _schema.validate(query)) {
      _violations.add('$name: $e');
    }
    for (final e in _schema.checkVariables(query, variables)) {
      _violations.add('$name: $e');
    }
    final Object answer;
    try {
      answer = _answer(name, variables, token);
    } on _Refused catch (e) {
      return _json({
        'data': null,
        'errors': [
          {
            'message': e.code,
            'extensions': {'code': e.code, ...e.extensions},
          },
        ],
      });
    }
    final data = answer as Map<String, Object?>;
    for (final e in _schema.checkResponse(
      query,
      jsonDecode(jsonEncode(data)) as Map<String, dynamic>,
    )) {
      _violations.add('$name answer: $e');
    }
    return _json({'data': data});
  });

  static const _handled = {
    'AuthChallenge',
    'SignIn',
    'RecoverAccount',
    'MyAccount',
    'UpdateProfile',
    'CreateRecoveryCode',
    'SignOut',
    'SignOutElsewhere',
    'DeleteAccount',
    'MyDevices',
    'RevokeDevice',
    'Rate',
    'WriteReview',
    'DeleteReview',
    'Confirm',
    'DeleteConfirmation',
    'ReportIssue',
    'DeleteIssueReport',
    'ConfirmPoi',
    'AddVendingMachine',
    'ReportContent',
    'AddPlace',
    'EditPlace',
    'DeletePlaceSubmission',
    'DeletePhoto',
    'MuteAuthor',
    'UnmuteAuthor',
    'MyContributions',
    'MyFavoriteLists',
    'ImportFavorites',
    'SaveToList',
    'RemoveFromList',
    'RenameList',
    'DeleteList',
  };

  static http.Response _json(Object body) => http.Response(
    jsonEncode(body),
    200,
    headers: {'content-type': 'application/json; charset=utf-8'},
  );

  String _signedIn(String? token) {
    final key = token == null ? null : _tokens[token];
    if (key == null || !_keys.containsKey(key)) throw const _Refused('UNAUTHENTICATED');
    return key;
  }

  Map<String, Object?> _session(String thumbprint, {required bool created}) {
    final token = 'token-${_serial++}';
    _tokens[token] = thumbprint;
    return {
      'token': token,
      'expiresAt': '2026-11-06T08:00:00Z',
      'created': created,
      'account': account(),
    };
  }

  /// Checks the signature of a challenge this server gave, once.
  String _verify(Map<String, Object?> v) {
    final nonce = v['nonce']! as String;
    if (!_nonces.remove(nonce)) throw const _Refused('BAD_CHALLENGE');
    final jwk = PublicJwk.fromJson(jsonDecode(v['jwk']! as String) as Map<String, Object?>);
    final message = Uint8List.fromList(utf8.encode('${P256.challengePrefix}$nonce'));
    final signature = P256.fromB64url(v['signature']! as String) ?? Uint8List(0);
    if (!P256.verify(jwk, message, signature)) throw const _Refused('BAD_SIGNATURE');
    return jwk.thumbprint;
  }

  Map<String, Object?> _review(Map<String, Object?> v, {String? text}) {
    reviews.removeWhere((r) => r['placeId'] == v['placeId']);
    final review = {
      'id': _next(),
      'sourceId': 'lunaway',
      'placeId': v['placeId'],
      'rating': v['stars'],
      'text': text,
      'lang': text == null ? null : v['lang'],
      'authorName': pseudonym,
      'authorId': _accountId,
      'authorVehicle': v['vehicle'],
      'visitedAt': v['visitedOn'],
      'createdAt': testNow.toIso8601String(),
      'status': 'PUBLISHED',
    };
    reviews.add(review);
    return review;
  }

  Map<String, Object?> _submission(String kind, Object? placeId) {
    final s = {
      'id': _next(),
      'kind': kind,
      'placeId': placeId,
      'status': 'PROPOSED',
      'createdAt': testNow.toIso8601String(),
      'poiId': null,
      'appliedAt': null,
    };
    submissions.add(s);
    return s;
  }

  bool _remove(List<Map<String, Object?>> rows, Object? id) {
    rows.removeWhere((r) => r['id'] == id);
    return true;
  }

  Object _answer(String name, Map<String, Object?> v, String? token) {
    switch (name) {
      case 'AuthChallenge':
        final nonce = P256.b64url(List<int>.generate(32, (i) => (i * 7 + _serial++) % 256));
        _nonces.add(nonce);
        return {
          'authChallenge': {'nonce': nonce, 'message': '${P256.challengePrefix}$nonce'},
        };
      case 'SignIn':
        final key = _verify(v);
        final unknown = !_keys.containsKey(key) && (_keys.isNotEmpty || _revoked);
        // `createIfUnknown: false`: an unknown key makes nothing.
        if (v['createIfUnknown'] == false && (unknown || _keys.isEmpty)) {
          throw const _Refused('NOT_FOUND');
        }
        if (unknown) {
          // A key it does not know: the server makes another account.
          final token = 'stranger-${_serial++}';
          _strangers.add(token);
          return {
            'signIn': {
              'token': token,
              'expiresAt': '2026-11-06T08:00:00Z',
              'created': true,
              'account': {...account(), 'id': _uuid(2), 'pseudonym': 'Inconnu'},
            },
          };
        }
        final created = _keys.isEmpty;
        _keys.putIfAbsent(key, _next);
        return {'signIn': _session(key, created: created)};
      case 'RecoverAccount':
        final key = _verify(v);
        if (v['code'] != recoveryCode) throw const _Refused('INVALID_RECOVERY_CODE');
        if (v['revokeOtherDevices'] == true) _keys.clear();
        _keys[key] = _next();
        return {'recoverAccount': _session(key, created: false)};
    }
    if (name == 'DeleteAccount' && _strangers.remove(token)) {
      strangersDeleted++;
      return {'deleteAccount': true};
    }
    final key = _signedIn(token);
    String id() => v['id']! as String;
    // The same idempotency key gets the answer the first request stored.
    final idempotency = v['idempotencyKey'];
    if (idempotency is String && _keyed.containsKey('$name/$idempotency')) {
      return _keyed['$name/$idempotency']!;
    }
    final answer = _answerSignedIn(name, v, key, id);
    if (idempotency is String) _keyed['$name/$idempotency'] = answer;
    return answer;
  }

  /// The answers stored by idempotency key, by operation.
  final _keyed = <String, Map<String, Object?>>{};

  Map<String, Object?> _answerSignedIn(
    String name,
    Map<String, Object?> v,
    String key,
    String Function() id,
  ) {
    return switch (name) {
      'MyAccount' => {
        'myAccount': {
          ...account(),
          'mutedAuthors': [
            for (final m in muted) {'id': m.id, 'pseudonym': m.pseudonym},
          ],
        },
      },
      'UpdateProfile' => () {
        pseudonym = v['pseudonym']! as String;
        return {'updateProfile': account()};
      }(),
      'CreateRecoveryCode' => {
        'createRecoveryCode': {'code': recoveryCode},
      },
      'SignOut' => {'signOut': true},
      'SignOutElsewhere' => () {
        final others = _keys.length - 1;
        _keys.removeWhere((k, _) => k != key);
        return {'signOutElsewhere': others};
      }(),
      'DeleteAccount' => () {
        _keys.clear();
        _tokens.clear();
        return {'deleteAccount': true};
      }(),
      'MyDevices' => {
        'myAccount': {
          'id': _accountId,
          'devices': [
            for (final MapEntry(key: k, value: device) in _keys.entries)
              {
                'id': device,
                'createdAt': '2026-10-01T08:00:00Z',
                'lastUsedAt': testNow.toIso8601String(),
                'current': k == key,
              },
          ],
        },
      },
      'RevokeDevice' => () {
        _keys.removeWhere((_, device) => device == id());
        return {'revokeDevice': true};
      }(),
      'Rate' => {'rate': _review(v)},
      'WriteReview' => {'review': _review(v, text: v['text'] as String?)},
      'DeleteReview' => {'deleteReview': _remove(reviews, id())},
      'Confirm' => () {
        final c = {
          'id': _next(),
          'placeId': v['placeId'],
          'status': v['status'],
          'createdAt': testNow.toIso8601String(),
        };
        confirmations.add(c);
        return {'confirm': c};
      }(),
      'DeleteConfirmation' => {'deleteConfirmation': _remove(confirmations, id())},
      'ReportIssue' => () {
        final i = {
          'id': _next(),
          'placeId': v['placeId'],
          'kind': v['kind'],
          'createdAt': testNow.toIso8601String(),
        };
        issues.add(i);
        return {'reportIssue': i};
      }(),
      'DeleteIssueReport' => {'deleteIssueReport': _remove(issues, id())},
      'ReportContent' => {'reportContent': true},
      'AddPlace' => {'addPlace': _submission('CREATE', null)},
      'ConfirmPoi' => () {
        final c = {'id': _next(), 'poiId': v['poiId'], 'stillThere': v['stillThere']};
        poiConfirmations.add(c);
        return {
          'confirmPoi': {'id': c['id']},
        };
      }(),
      'AddVendingMachine' => () {
        if (vendingDuplicateOf case final existing?) {
          throw _Refused('INVALID_INPUT', extensions: {'existingId': existing});
        }
        return {'addVendingMachine': _submission('POI', null)};
      }(),
      'EditPlace' => {'editPlace': _submission('EDIT', v['placeId'])},
      'DeletePlaceSubmission' => {'deletePlaceSubmission': _remove(submissions, id())},
      'DeletePhoto' => {'deletePhoto': _remove(photos, id())},
      'MuteAuthor' => () {
        if (!muted.any((m) => m.id == id())) {
          muted.add((id: id(), pseudonym: authors[id()] ?? 'Auteur'));
        }
        return {'muteAuthor': true};
      }(),
      'UnmuteAuthor' => () {
        muted.removeWhere((m) => m.id == id());
        return {'unmuteAuthor': true};
      }(),
      'MyContributions' => {
        'myAccount': {
          'id': _accountId,
          'reviews': {'nodes': reviews, 'totalCount': reviews.length},
          'photos': {'nodes': photos, 'totalCount': photos.length},
          'confirmations': {'nodes': confirmations, 'totalCount': confirmations.length},
          'issueReports': {'nodes': issues, 'totalCount': issues.length},
          'placeSubmissions': {'nodes': submissions, 'totalCount': submissions.length},
        },
      },
      'MyFavoriteLists' => {'myFavoriteLists': <Object?>[]},
      'ImportFavorites' => {
        'importFavorites': [
          for (final l in (v['lists']! as List<Object?>).cast<Map<String, Object?>>())
            {
              'id': _next(),
              'name': l['name'],
              'places': [
                for (final p in (l['placeIds'] as List<Object?>? ?? const [])) {'placeId': p},
              ],
            },
        ],
      },
      'SaveToList' || 'RemoveFromList' => {
        name == 'SaveToList' ? 'saveToList' : 'removeFromList': {'id': v['listId']},
      },
      'RenameList' => {
        'renameList': {'id': id()},
      },
      'DeleteList' => {'deleteList': true},
      _ => throw _Refused('UNKNOWN $name'),
    };
  }

  Future<http.Response> _upload(http.Request request) async {
    if (offline) throw http.ClientException('offline', request.url);
    final token = request.headers['authorization']?.replaceFirst('Bearer ', '');
    try {
      _signedIn(token);
    } on _Refused {
      return http.Response('{"error":{"code":"UNAUTHENTICATED"}}', 401);
    }
    final bytes = request.bodyBytes;
    // The JPEG part of the multipart body, from its SOI to its EOI marker.
    final start = _indexOf(bytes, const [0xFF, 0xD8, 0xFF]);
    final end = _lastIndexOf(bytes, const [0xFF, 0xD9]);
    uploads.add(Uint8List.sublistView(bytes, start, end + 2));
    final placeId = RegExp(r'name="placeId"\r\n\r\n([^\r]+)')
        .firstMatch(latin1.decode(bytes, allowInvalid: true))?[1];
    calls.add((operation: 'upload', variables: {'placeId': placeId}, token: token));
    final photo = {
      'id': _next(),
      'sourceId': 'lunaway',
      'thumbUrl': '$testApiBase/media/demo-1/thumb',
      'largeUrl': '$testApiBase/media/demo-1/large',
      'width': 1600,
      'height': 1200,
      'thumbhash': null,
      'createdAt': testNow.toIso8601String(),
      'status': 'PUBLISHED',
    };
    photos.add(photo);
    return _json({'photo': photo});
  }

  static int _indexOf(List<int> bytes, List<int> pattern) {
    for (var i = 0; i + pattern.length <= bytes.length; i++) {
      var match = true;
      for (var j = 0; j < pattern.length && match; j++) {
        match = bytes[i + j] == pattern[j];
      }
      if (match) return i;
    }
    return -1;
  }

  static int _lastIndexOf(List<int> bytes, List<int> pattern) {
    for (var i = bytes.length - pattern.length; i >= 0; i--) {
      var match = true;
      for (var j = 0; j < pattern.length && match; j++) {
        match = bytes[i + j] == pattern[j];
      }
      if (match) return i;
    }
    return -1;
  }
}

final class _Refused implements Exception {
  const new(this.code, {this.extensions = const {}});

  final String code;
  final Map<String, Object?> extensions;
}
