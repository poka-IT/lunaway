import 'dart:typed_data';

import 'package:lunaway/features/account/data/account_service.dart';
import 'package:lunaway/features/community/data/community_operations.dart';
import 'package:lunaway/features/community/data/photo_upload.dart';
import 'package:lunaway/features/community/domain/contribution.dart';
import 'package:lunaway/features/places/data/graphql/operations.dart';
import 'package:lunaway/features/places/domain/place_content.dart';

/// What the outbox sends contributions through: the API, as the account.
abstract interface class CommunityApi {
  /// Sends a contribution of [kind] with [variables]; returns what the
  /// server answered (a review, a submission, a confirmation, a flag).
  /// [create] lets it make the account: only a contribution made before
  /// the device had one may.
  Future<Object?> send(
    ContributionKind kind,
    Map<String, Object?> variables, {
    bool create = true,
  });

  /// Sends a photo of [placeId].
  Future<Photo> upload(
    String placeId,
    Uint8List jpeg, {
    bool create = true,
    void Function(double sent)? onProgress,
  });

  /// The account's latest contributions, to find one whose answer was lost.
  Future<MyContributions> recent({int first = 20});
}

/// The API through the account's session: a contribution makes the account
/// when the device has none (the first contribution creates it).
final class GraphQLCommunityApi implements CommunityApi {
  new({required this.account, required this.uploader});

  final AccountService account;
  final PhotoUploader uploader;

  static GraphQLOperation<Object?> operationOf(ContributionKind kind) =>
      switch (kind) {
        ContributionKind.rate => rateOperation,
        ContributionKind.review => reviewOperation,
        ContributionKind.deleteReview => deleteReviewOperation,
        ContributionKind.confirm => confirmOperation,
        ContributionKind.deleteConfirmation => deleteConfirmationOperation,
        ContributionKind.reportIssue => reportIssueOperation,
        ContributionKind.deleteIssueReport => deleteIssueReportOperation,
        ContributionKind.reportContent => reportContentOperation,
        ContributionKind.addPlace => addPlaceOperation,
        ContributionKind.editPlace => editPlaceOperation,
        ContributionKind.deletePlaceSubmission =>
          deletePlaceSubmissionOperation,
        ContributionKind.deletePhoto => deletePhotoOperation,
        ContributionKind.mute => muteAuthorOperation,
        ContributionKind.unmute => unmuteAuthorOperation,
        ContributionKind.photo => throw ArgumentError(
          'a photo goes through upload',
        ),
      };

  @override
  Future<Object?> send(
    ContributionKind kind,
    Map<String, Object?> variables, {
    bool create = true,
  }) => account.run(operationOf(kind), variables: variables, create: create);

  @override
  Future<Photo> upload(
    String placeId,
    Uint8List jpeg, {
    bool create = true,
    void Function(double sent)? onProgress,
  }) async {
    final headers = await account.sessionHeaders(create: create);
    try {
      return await uploader.upload(
        placeId: placeId,
        jpeg: jpeg,
        headers: headers,
        onProgress: onProgress,
      );
    } on UploadException catch (e) {
      // A refused session: sign in again and send once more.
      if (e.status != 401) rethrow;
      return await uploader.upload(
        placeId: placeId,
        jpeg: jpeg,
        headers: await account.renewSession(create: create),
        onProgress: onProgress,
      );
    }
  }

  @override
  Future<MyContributions> recent({int first = 20}) =>
      account.run(myContributionsOperation, variables: {'first': first});
}
