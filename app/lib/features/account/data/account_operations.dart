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

final signInOperation = GraphQLOperation<SignInResult>(
  name: 'SignIn',
  document: '''
mutation SignIn(\$jwk: String!, \$nonce: String!, \$signature: String!, \$locale: String) {
  signIn(publicKeyJwk: \$jwk, nonce: \$nonce, signature: \$signature, locale: \$locale) {
    token
    expiresAt
    created
    account { ...AccountFields }
  }
}
$_accountFields''',
  parse: (data) => _signInResult(data['signIn']),
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

/// The account with its level, and the authors it mutes.
final myAccountOperation = GraphQLOperation<({Account account, List<Author> muted})>(
  name: 'MyAccount',
  document: '''
query MyAccount {
  myAccount {
    ...AccountFields
    mutedAuthors { id pseudonym }
  }
}
$_accountFields''',
  parse: (data) {
    final a = data['myAccount'] as Map<String, dynamic>;
    return (
      account: _account(a),
      muted: [
        for (final m in (a['mutedAuthors'] as List<dynamic>).cast<Map<String, dynamic>>())
          Author(id: m['id'] as String, pseudonym: m['pseudonym'] as String),
      ],
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
  signOutElsewhereOperation,
  deleteAccountOperation,
  myDevicesOperation,
  revokeDeviceOperation,
];
