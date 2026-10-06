import 'package:lunaway/features/community/domain/community.dart';
import 'package:lunaway/features/places/data/graphql/operations.dart';
import 'package:lunaway/features/places/data/graphql/place_json.dart';
import 'package:lunaway/features/places/domain/place_content.dart';

const _submissionFields = '''
fragment SubmissionFields on PlaceSubmission { id kind placeId status createdAt appliedAt }
''';

PlaceSubmission submissionFromJson(Map<String, dynamic> m) => PlaceSubmission(
  id: m['id'] as String,
  kind: SubmissionKind.fromWire(m['kind']),
  placeId: m['placeId'] as String?,
  status: SubmissionStatus.fromWire(m['status']),
  createdAt: DateTime.parse(m['createdAt'] as String).toUtc(),
  appliedAt: DateTime.tryParse('${m['appliedAt']}')?.toUtc(),
);

Confirmation confirmationFromJson(Map<String, dynamic> m) => Confirmation(
  id: m['id'] as String,
  placeId: m['placeId'] as String,
  status:
      ConfirmationStatus.fromWire(m['status']) ?? ConfirmationStatus.stillOk,
  createdAt: DateTime.parse(m['createdAt'] as String).toUtc(),
);

IssueReport issueReportFromJson(Map<String, dynamic> m) => IssueReport(
  id: m['id'] as String,
  placeId: m['placeId'] as String,
  kind: IssueKind.fromWire(m['kind']) ?? IssueKind.danger,
  createdAt: DateTime.parse(m['createdAt'] as String).toUtc(),
);

Review _review(Object? json) {
  final review = reviewFromJson(json);
  if (review == null) throw const FormatException('not a review');
  return review;
}

final rateOperation = GraphQLOperation<Review>(
  name: 'Rate',
  document: '''
mutation Rate(\$placeId: UUID!, \$stars: Int!) {
  rate(placeId: \$placeId, stars: \$stars) { ...MyReviewFields }
}
$myReviewFields''',
  parse: (data) => _review(data['rate']),
);

final reviewOperation = GraphQLOperation<Review>(
  name: 'WriteReview',
  document: '''
mutation WriteReview(
  \$placeId: UUID!
  \$stars: Int!
  \$text: String!
  \$visitedOn: NaiveDate
  \$vehicle: VehicleKind
  \$lang: String
) {
  review(
    placeId: \$placeId
    stars: \$stars
    text: \$text
    visitedOn: \$visitedOn
    vehicle: \$vehicle
    lang: \$lang
  ) { ...MyReviewFields }
}
$myReviewFields''',
  parse: (data) => _review(data['review']),
);

final deleteReviewOperation = GraphQLOperation<bool>(
  name: 'DeleteReview',
  document: r'mutation DeleteReview($id: UUID!) { deleteReview(id: $id) }',
  parse: (data) => data['deleteReview'] == true,
);

/// "Still there?": no position is ever sent (decided: a confirmation says
/// nothing of where its author is).
final confirmOperation = GraphQLOperation<Confirmation>(
  name: 'Confirm',
  document: r'''
mutation Confirm($placeId: UUID!, $status: ConfirmationStatus!, $note: String) {
  confirm(placeId: $placeId, status: $status, note: $note) { id placeId status createdAt }
}''',
  parse: (data) =>
      confirmationFromJson(data['confirm'] as Map<String, dynamic>),
);

final deleteConfirmationOperation = GraphQLOperation<bool>(
  name: 'DeleteConfirmation',
  document: r'mutation DeleteConfirmation($id: UUID!) { deleteConfirmation(id: $id) }',
  parse: (data) => data['deleteConfirmation'] == true,
);

final reportIssueOperation = GraphQLOperation<IssueReport>(
  name: 'ReportIssue',
  document: r'''
mutation ReportIssue($placeId: UUID!, $kind: IssueKind!, $note: String) {
  reportIssue(placeId: $placeId, kind: $kind, note: $note) { id placeId kind createdAt }
}''',
  parse: (data) =>
      issueReportFromJson(data['reportIssue'] as Map<String, dynamic>),
);

final deleteIssueReportOperation = GraphQLOperation<bool>(
  name: 'DeleteIssueReport',
  document:
      r'mutation DeleteIssueReport($id: UUID!) { deleteIssueReport(id: $id) }',
  parse: (data) => data['deleteIssueReport'] == true,
);

final reportContentOperation = GraphQLOperation<bool>(
  name: 'ReportContent',
  document: r'''
mutation ReportContent($target: ReportTarget!, $id: UUID!, $reason: ReportReason!, $note: String) {
  reportContent(target: $target, id: $id, reason: $reason, note: $note)
}''',
  parse: (data) => data['reportContent'] == true,
);

final addPlaceOperation = GraphQLOperation<PlaceSubmission>(
  name: 'AddPlace',
  document: '''
mutation AddPlace(\$input: NewPlaceInput!) {
  addPlace(input: \$input) { ...SubmissionFields }
}
$_submissionFields''',
  parse: (data) => submissionFromJson(data['addPlace'] as Map<String, dynamic>),
);

final editPlaceOperation = GraphQLOperation<PlaceSubmission>(
  name: 'EditPlace',
  document: '''
mutation EditPlace(\$placeId: UUID!, \$patch: PlaceDetailsInput!) {
  editPlace(placeId: \$placeId, patch: \$patch) { ...SubmissionFields }
}
$_submissionFields''',
  parse: (data) =>
      submissionFromJson(data['editPlace'] as Map<String, dynamic>),
);

final deletePlaceSubmissionOperation = GraphQLOperation<bool>(
  name: 'DeletePlaceSubmission',
  document: r'mutation DeletePlaceSubmission($id: UUID!) { deletePlaceSubmission(id: $id) }',
  parse: (data) => data['deletePlaceSubmission'] == true,
);

final deletePhotoOperation = GraphQLOperation<bool>(
  name: 'DeletePhoto',
  document: r'mutation DeletePhoto($id: UUID!) { deletePhoto(id: $id) }',
  parse: (data) => data['deletePhoto'] == true,
);

final muteAuthorOperation = GraphQLOperation<bool>(
  name: 'MuteAuthor',
  document: r'mutation MuteAuthor($id: UUID!) { muteAuthor(accountId: $id) }',
  parse: (data) => data['muteAuthor'] == true,
);

final unmuteAuthorOperation = GraphQLOperation<bool>(
  name: 'UnmuteAuthor',
  document:
      r'mutation UnmuteAuthor($id: UUID!) { unmuteAuthor(accountId: $id) }',
  parse: (data) => data['unmuteAuthor'] == true,
);

/// The account's own contributions, newest first, every status.
typedef MyContributions = ({
  List<Review> reviews,
  int reviewTotal,
  List<Photo> photos,
  int photoTotal,
  List<Confirmation> confirmations,
  int confirmationTotal,
  List<IssueReport> issues,
  int issueTotal,
  List<PlaceSubmission> submissions,
  int submissionTotal,
});

final myContributionsOperation = GraphQLOperation<MyContributions>(
  name: 'MyContributions',
  document: '''
query MyContributions(\$first: Int) {
  myAccount {
    id
    reviews(first: \$first) { nodes { ...MyReviewFields } totalCount }
    photos(first: \$first) {
      nodes { id sourceId thumbUrl largeUrl width height thumbhash createdAt status }
      totalCount
    }
    confirmations(first: \$first) { nodes { id placeId status createdAt } totalCount }
    issueReports(first: \$first) { nodes { id placeId kind createdAt } totalCount }
    placeSubmissions(first: \$first) { nodes { ...SubmissionFields } totalCount }
  }
}
$myReviewFields$_submissionFields''',
  parse: (data) {
    final a = data['myAccount'] as Map<String, dynamic>;
    List<Map<String, dynamic>> nodes(String field) =>
        ((a[field] as Map<String, dynamic>)['nodes'] as List<dynamic>)
            .cast<Map<String, dynamic>>();
    int total(String field) =>
        ((a[field] as Map<String, dynamic>)['totalCount'] as num).toInt();
    return (
      reviews: [for (final r in nodes('reviews')) ?reviewFromJson(r)],
      reviewTotal: total('reviews'),
      photos: photosFromJson(nodes('photos')),
      photoTotal: total('photos'),
      confirmations: [
        for (final c in nodes('confirmations')) confirmationFromJson(c),
      ],
      confirmationTotal: total('confirmations'),
      issues: [for (final i in nodes('issueReports')) issueReportFromJson(i)],
      issueTotal: total('issueReports'),
      submissions: [
        for (final s in nodes('placeSubmissions')) submissionFromJson(s),
      ],
      submissionTotal: total('placeSubmissions'),
    );
  },
);

/// Every contribution operation, for the contract test.
final communityOperations = <GraphQLOperation<Object?>>[
  rateOperation,
  reviewOperation,
  deleteReviewOperation,
  confirmOperation,
  deleteConfirmationOperation,
  reportIssueOperation,
  deleteIssueReportOperation,
  reportContentOperation,
  addPlaceOperation,
  editPlaceOperation,
  deletePlaceSubmissionOperation,
  deletePhotoOperation,
  muteAuthorOperation,
  unmuteAuthorOperation,
  myContributionsOperation,
];
