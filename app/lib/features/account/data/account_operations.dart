import 'package:lunaway/features/account/domain/account.dart';
import 'package:lunaway/features/places/data/graphql/operations.dart';
import 'package:meta/meta.dart';

const _accountFields = '''
fragment AccountFields on Account {
  id
  pseudonym
  trustLevel
  createdAt
  nextLevel {
    level
    missing { kind current needed }
    instead { kind current needed }
  }
}
''';

Account _account(Object? json) {
  final account = Account.fromJson(json);
  if (account == null) throw const FormatException('not an account');
  return account;
}

/// A sign-in challenge: the nonce to sign, and when it expires.
@immutable
final class Challenge {
  const new({required this.nonce, required this.message});

  final String nonce;
  final String message;
}

/// A session the server opened, with the account it belongs to.
@immutable
final class SignInResult {
  const new({
    required this.token,
    required this.expiresAt,
    required this.created,
    required this.account,
  });

  final String token;
  final DateTime expiresAt;

  /// Whether this sign-in created the account.
  final bool created;
  final Account account;
}

SignInResult _signInResult(Object? json) {
  final m = json! as Map<String, dynamic>;
  return SignInResult(
    token: m['token'] as String,
    expiresAt: DateTime.parse(m['expiresAt'] as String).toUtc(),
    created: m['created'] == true,
    account: _account(m['account']),
  );
}

final authChallengeOperation = GraphQLOperation<Challenge>(
  name: 'AuthChallenge',
  document: '''
mutation AuthChallenge {
  authChallenge { nonce message }
}''',
  parse: (data) {
    final c = data['authChallenge'] as Map<String, dynamic>;
    return Challenge(nonce: c['nonce'] as String, message: c['message'] as String);
  },
);

const _signInDocument = '''
mutation SignIn(
  \$jwk: String!
  \$nonce: String!
  \$signature: String!
  \$locale: String
  \$createIfUnknown: Boolean!
) {
  signIn(
    publicKeyJwk: \$jwk
    nonce: \$nonce
    signature: \$signature
    locale: \$locale
    createIfUnknown: \$createIfUnknown
  ) {
    token
    expiresAt
    created
    account { ...AccountFields }
  }
}
$_accountFields''';

final signInOperation = GraphQLOperation<SignInResult>(
  name: 'SignIn',
  document: _signInDocument,
  parse: (data) => _signInResult(data['signIn']),
  // The API before `createIfUnknown` creates an account for any key it
  // does not know: the account service deletes one made behind a key that
  // held another.
  older: OlderForm.without(_signInDocument, const {'createIfUnknown'}),
);

final recoverAccountOperation = GraphQLOperation<SignInResult>(
  name: 'RecoverAccount',
  document: '''
mutation RecoverAccount(
  \$code: String!
  \$jwk: String!
  \$nonce: String!
  \$signature: String!
  \$revokeOtherDevices: Boolean!
) {
  recoverAccount(
    code: \$code
    publicKeyJwk: \$jwk
    nonce: \$nonce
    signature: \$signature
    revokeOtherDevices: \$revokeOtherDevices
  ) {
    token
    expiresAt
    created
    account { ...AccountFields }
  }
}
$_accountFields''',
  parse: (data) => _signInResult(data['recoverAccount']),
);

String _myAccountDocument({required bool withCard}) =>
    '''
query MyAccount {
  myAccount {
    ...AccountFields
    mutedAuthors { id pseudonym }${withCard ? '\n    recoveryCodeCreatedAt' : ''}
  }
}
$_accountFields''';

/// What `myAccount` says of the recovery code: when it was made, null when
/// the account has none. The record itself is null when the API is older
/// than the field and says nothing.
typedef ServerRecoveryCode = ({DateTime? createdAt});

/// A date of the answer, null for null; anything else throws, so a garbled
/// answer leaves the device's date alone rather than reading as "no card".
DateTime? _date(Object? value) => value == null ? null : DateTime.parse(value as String).toUtc();

/// The account with its level, the authors it mutes, and the date of its
/// recovery code (the same on every device of the account).
final myAccountOperation =
    GraphQLOperation<({Account account, List<Author> muted, ServerRecoveryCode? recoveryCode})>(
      name: 'MyAccount',
      document: _myAccountDocument(withCard: true),
      older: OlderForm.selecting(_myAccountDocument(withCard: false)),
      parse: (data) {
        final a = data['myAccount'] as Map<String, dynamic>;
        return (
          account: _account(a),
          muted: [
            for (final m in (a['mutedAuthors'] as List<dynamic>).cast<Map<String, dynamic>>())
              Author(id: m['id'] as String, pseudonym: m['pseudonym'] as String),
          ],
          recoveryCode: a.containsKey('recoveryCodeCreatedAt')
              ? (createdAt: _date(a['recoveryCodeCreatedAt']))
              : null,
        );
      },
    );

final updateProfileOperation = GraphQLOperation<Account>(
  name: 'UpdateProfile',
  document: '''
mutation UpdateProfile(\$pseudonym: String!) {
  updateProfile(pseudonym: \$pseudonym) { ...AccountFields }
}
$_accountFields''',
  parse: (data) => _account(data['updateProfile']),
);

final createRecoveryCodeOperation = GraphQLOperation<String>(
  name: 'CreateRecoveryCode',
  document: '''
mutation CreateRecoveryCode {
  createRecoveryCode { code }
}''',
  parse: (data) => (data['createRecoveryCode'] as Map<String, dynamic>)['code'] as String,
);

final signOutOperation = GraphQLOperation<bool>(
  name: 'SignOut',
  document: 'mutation SignOut { signOut }',
  parse: (data) => data['signOut'] == true,
);

/// Ends the session and detaches its key from the account: the device
/// leaves that account for good (another account imported in its place,
/// an import given up).
final signOutForgettingDeviceOperation = GraphQLOperation<bool>(
  name: 'SignOutForgettingDevice',
  document: 'mutation SignOutForgettingDevice { signOut(forgetDevice: true) }',
  parse: (data) => data['signOut'] == true,
);

/// Which home the account kept when another was merged into it.
enum MergedHome {
  /// Neither had one.
  none('NONE'),

  /// The account kept its own; the merged account's went with it.
  kept('KEPT'),

  /// The merged account's home became the account's.
  moved('MOVED');

  new(this.wire);

  final String wire;

  static MergedHome fromWire(Object? wire) =>
      values.where((h) => h.wire == wire).firstOrNull ?? none;
}

/// The account another one was merged into, and which home it kept.
typedef MergeResult = ({Account account, MergedHome home});

final mergeAccountOperation = GraphQLOperation<MergeResult>(
  name: 'MergeAccount',
  document: '''
mutation MergeAccount(
  \$jwk: String!
  \$nonce: String!
  \$absorbedSignature: String!
  \$signature: String!
) {
  mergeAccount(
    absorbedKeyJwk: \$jwk
    nonce: \$nonce
    absorbedSignature: \$absorbedSignature
    signature: \$signature
  ) {
    home
    account { ...AccountFields }
  }
}
$_accountFields''',
  parse: (data) {
    final m = data['mergeAccount'] as Map<String, dynamic>;
    return (account: _account(m['account']), home: MergedHome.fromWire(m['home']));
  },
);

/// Whether the account of the session has a home, read before a merge so
/// the choice can say which home stays.
final accountHasHomeOperation = GraphQLOperation<bool>(
  name: 'AccountHasHome',
  document: 'query AccountHasHome { myHome { updatedAt } }',
  parse: (data) => data['myHome'] != null,
);

final signOutElsewhereOperation = GraphQLOperation<int>(
  name: 'SignOutElsewhere',
  document: 'mutation SignOutElsewhere { signOutElsewhere }',
  parse: (data) => (data['signOutElsewhere'] as num).toInt(),
);

final deleteAccountOperation = GraphQLOperation<bool>(
  name: 'DeleteAccount',
  document: 'mutation DeleteAccount { deleteAccount(confirm: "DELETE") }',
  parse: (data) => data['deleteAccount'] == true,
);

final myDevicesOperation = GraphQLOperation<List<Device>>(
  name: 'MyDevices',
  document: '''
query MyDevices {
  myAccount {
    id
    devices { id createdAt lastUsedAt current }
  }
}''',
  parse: (data) => [
    for (final d
        in ((data['myAccount'] as Map<String, dynamic>)['devices'] as List<dynamic>)
            .cast<Map<String, dynamic>>())
      Device(
        id: d['id'] as String,
        createdAt: DateTime.parse(d['createdAt'] as String).toUtc(),
        lastUsedAt: DateTime.parse(d['lastUsedAt'] as String).toUtc(),
        current: d['current'] == true,
      ),
  ],
);

final revokeDeviceOperation = GraphQLOperation<bool>(
  name: 'RevokeDevice',
  document: r'mutation RevokeDevice($id: UUID!) { revokeDevice(id: $id) }',
  parse: (data) => data['revokeDevice'] == true,
);

/// Every account operation, for the contract test.
final accountOperations = <GraphQLOperation<Object?>>[
  authChallengeOperation,
  signInOperation,
  recoverAccountOperation,
  myAccountOperation,
  updateProfileOperation,
  createRecoveryCodeOperation,
  signOutOperation,
  signOutForgettingDeviceOperation,
  mergeAccountOperation,
  accountHasHomeOperation,
  signOutElsewhereOperation,
  deleteAccountOperation,
  myDevicesOperation,
  revokeDeviceOperation,
];
