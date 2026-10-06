import 'package:lunaway/features/account/domain/account.dart';
import 'package:lunaway/features/community/domain/community.dart';
import 'package:lunaway/features/community/domain/contribution.dart';
import 'package:lunaway/features/places/domain/place_content.dart';
import 'package:lunaway/i18n/strings.g.dart';

/// The words of the community: issues, reasons, statuses, the outbox.
extension CommunityLabels on Translations {
  // Read through a name, so the translation gate sees every key used.
  Translations get _t => this;

  String issueKind(IssueKind k) => switch (k) {
    .nightBan => _t.issueSheet.kind.nightBan,
    .serviceBroken => _t.issueSheet.kind.serviceBroken,
    .noAccess => _t.issueSheet.kind.noAccess,
    .danger => _t.issueSheet.kind.danger,
  };

  String issueHint(IssueKind k) => switch (k) {
    .nightBan => _t.issueSheet.hint.nightBan,
    .serviceBroken => _t.issueSheet.hint.serviceBroken,
    .noAccess => _t.issueSheet.hint.noAccess,
    .danger => _t.issueSheet.hint.danger,
  };

  String reportReason(ReportReason r) => switch (r) {
    .spam => _t.reportSheet.reason.spam,
    .offensive => _t.reportSheet.reason.offensive,
    .wrong => _t.reportSheet.reason.wrong,
    .privacy => _t.reportSheet.reason.privacy,
    .other => _t.reportSheet.reason.other,
  };

  String confirmationStatus(ConfirmationStatus s) => switch (s) {
    .stillOk => _t.confirmSheet.status.stillOk,
    .closed => _t.confirmSheet.status.closed,
    .changed => _t.confirmSheet.status.changed,
  };

  String contributionStatus(ContributionStatus s) => switch (s) {
    .published => _t.mine.status.published,
    .pending => _t.mine.status.pending,
    .hidden => _t.mine.status.hidden,
    .removed => _t.mine.status.removed,
  };

  String submissionStatus(SubmissionStatus s) => switch (s) {
    .proposed => _t.mine.submission.proposed,
    .accepted => _t.mine.submission.accepted,
    .applied => _t.mine.submission.applied,
    .rejected => _t.mine.submission.rejected,
    .withdrawn => _t.mine.submission.withdrawn,
  };

  /// What a level lets the account do, in a sentence.
  String levelOpens(int level) => switch (level) {
    <= 0 => _t.account.levelOpens.l0,
    1 => _t.account.levelOpens.l1,
    2 => _t.account.levelOpens.l2,
    3 => _t.account.levelOpens.l3,
    _ => _t.account.levelOpens.l4,
  };

  String requirement(LevelRequirement r) {
    final needed = '${r.needed ?? 0}';
    final current = '${r.current ?? 0}';
    return switch (r.kind) {
      .accountAgeDays => _t.account.requirement.age(needed: needed, current: current),
      .confirmations => _t.account.requirement.confirmations(needed: needed, current: current),
      .contributions => _t.account.requirement.contributions(needed: needed, current: current),
      .activeDays => _t.account.requirement.activeDays(needed: needed, current: current),
      .noRemoval => _t.account.requirement.noRemoval,
      .sponsor => _t.account.requirement.sponsor,
      .nomination => _t.account.requirement.nomination,
      .administration => _t.account.requirement.administration,
    };
  }

  /// A waiting contribution, in a line.
  String pendingLabel(PendingContribution e, {String? placeName}) {
    final p = e.payload;
    return switch (e.kind) {
      .rate => _t.outbox.kind.rate(stars: '${p['stars']}'),
      .review => _t.outbox.kind.review,
      .deleteReview => _t.outbox.kind.deleteReview,
      .confirm => _t.outbox.kind.confirm(
        status: confirmationStatus(
          ConfirmationStatus.fromWire(p['status']) ?? ConfirmationStatus.stillOk,
        ),
      ),
      .deleteConfirmation => _t.outbox.kind.deleteConfirmation,
      .reportIssue => _t.outbox.kind.reportIssue(
        kind: issueKind(IssueKind.fromWire(p['kind']) ?? IssueKind.danger),
      ),
      .deleteIssueReport => _t.outbox.kind.deleteIssueReport,
      .reportContent => _t.outbox.kind.reportContent,
      .addPlace => _t.outbox.kind.addPlace(name: _newPlaceName(p) ?? ''),
      .editPlace => _t.outbox.kind.editPlace,
      .deletePlaceSubmission => _t.outbox.kind.deletePlaceSubmission,
      .photo => _t.outbox.kind.photo,
      .deletePhoto => _t.outbox.kind.deletePhoto,
      .mute => _t.outbox.kind.mute,
      .unmute => _t.outbox.kind.unmute,
      .confirmPoi => p['stillThere'] == false ? _t.outbox.kind.poiGone : _t.outbox.kind.poiThere,
      .addVendingMachine => _t.outbox.kind.addVendingMachine,
    };
  }

  static String? _newPlaceName(Map<String, Object?> payload) {
    final input = payload['input'];
    if (input is! Map) return null;
    final details = input['details'];
    return details is Map ? details['name'] as String? : null;
  }

  /// Why the server refused a contribution.
  String outboxError(String? code) => switch (code) {
    OutboxError.forbidden => _t.outbox.error.forbidden,
    OutboxError.notFound => _t.outbox.error.notFound,
    OutboxError.invalid => _t.outbox.error.invalid,
    OutboxError.unreadablePhoto => _t.outbox.error.unreadablePhoto,
    OutboxError.photoTooLarge => _t.outbox.error.photoTooLarge,
    OutboxError.placeRefused => _t.outbox.error.placeRefused,
    OutboxError.fileLost => _t.outbox.error.fileLost,
    OutboxError.otherAccount => _t.outbox.error.otherAccount,
    OutboxError.duplicate => _t.outbox.error.duplicate,
    _ => _t.outbox.error.other,
  };
}
