import 'package:collection/collection.dart';
import 'package:meta/meta.dart';

/// What a contribution does, as the outbox stores it.
enum ContributionKind {
  rate,
  review,
  deleteReview,
  confirm,
  deleteConfirmation,
  reportIssue,
  deleteIssueReport,
  reportContent,
  addPlace,
  editPlace,
  deletePlaceSubmission,
  photo,
  deletePhoto,
  mute,
  unmute;

  static ContributionKind? fromName(String name) => values.where((k) => k.name == name).firstOrNull;

  /// Sending it twice changes nothing more than sending it once: a rating
  /// or a review replaces the account's previous one, a deletion of what is
  /// gone is done, a mute of a muted author too. The others create a row
  /// each time: after an attempt whose answer was lost, the next one looks
  /// for that row first.
  bool get idempotent => switch (this) {
    rate ||
    review ||
    deleteReview ||
    deleteConfirmation ||
    deleteIssueReport ||
    reportContent ||
    deletePlaceSubmission ||
    deletePhoto ||
    mute ||
    unmute => true,
    confirm || reportIssue || addPlace || editPlace || photo => false,
  };

  /// A deletion: a target the server no longer has is a success.
  bool get deletes => switch (this) {
    deleteReview ||
    deleteConfirmation ||
    deleteIssueReport ||
    deletePlaceSubmission ||
    deletePhoto => true,
    _ => false,
  };
}

enum OutboxState {
  /// Waiting for its turn or for the network.
  pending,

  /// An attempt is under way, or was cut short by the end of the app.
  sending,

  /// The server refused it: shown to the user, never sent again unless they
  /// ask.
  failed,
}

/// Why the server refused a contribution, for the words shown to the user.
abstract final class OutboxError {
  /// The account's level is below what the action needs.
  static const forbidden = 'FORBIDDEN';

  /// The place, the review or the photo is gone.
  static const notFound = 'NOT_FOUND';

  /// The server refused the content (too long, a link, a name taken).
  static const invalid = 'INVALID_INPUT';

  /// A photo the server cannot read, or one already sent.
  static const unreadablePhoto = 'PHOTO_UNREADABLE';

  /// A photo over the size the server takes.
  static const photoTooLarge = 'PHOTO_TOO_LARGE';

  /// The new place this photo was for was refused or withdrawn.
  static const placeRefused = 'PLACE_REFUSED';

  /// The photo's bytes are no longer on the device.
  static const fileLost = 'FILE_LOST';

  /// Made by another account than the one on this device now.
  static const otherAccount = 'OTHER_ACCOUNT';

  /// Anything else.
  static const other = 'OTHER';
}

/// A contribution made on this device and not yet accepted by the server.
@immutable
final class PendingContribution {
  const new({
    required this.id,
    required this.kind,
    required this.payload,
    required this.createdAt,
    this.placeId,
    this.fileId,
    this.accountId,
    this.state = OutboxState.pending,
    this.uncertain = false,
    this.attempts = 0,
    this.nextAttemptAt,
    this.attemptStartedAt,
    this.errorCode,
    this.errorDetail,
  });

  final String id;
  final ContributionKind kind;
  final String? placeId;

  /// The variables of the request.
  final Map<String, Object?> payload;
  final String? fileId;
  final String? accountId;
  final DateTime createdAt;
  final OutboxState state;
  final bool uncertain;
  final int attempts;
  final DateTime? nextAttemptAt;
  final DateTime? attemptStartedAt;
  final String? errorCode;
  final String? errorDetail;

  bool get failed => state == OutboxState.failed;

  @override
  bool operator ==(Object other) =>
      other is PendingContribution &&
      other.id == id &&
      other.kind == kind &&
      other.placeId == placeId &&
      const DeepCollectionEquality().equals(other.payload, payload) &&
      other.fileId == fileId &&
      other.accountId == accountId &&
      other.createdAt == createdAt &&
      other.state == state &&
      other.uncertain == uncertain &&
      other.attempts == attempts &&
      other.nextAttemptAt == nextAttemptAt &&
      other.attemptStartedAt == attemptStartedAt &&
      other.errorCode == errorCode &&
      other.errorDetail == errorDetail;

  @override
  int get hashCode => Object.hash(id, state, attempts, errorCode, uncertain);

  @override
  String toString() => 'PendingContribution($id, ${kind.name}, ${state.name})';
}
