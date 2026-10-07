import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:lunaway/core/providers.dart';
import 'package:lunaway/features/account/application/account_providers.dart';
import 'package:lunaway/features/account/domain/account.dart';
import 'package:lunaway/features/community/domain/community.dart';
import 'package:lunaway/features/community/domain/contribution.dart';
import 'package:lunaway/features/community/presentation/community_labels.dart';
import 'package:lunaway/features/community/presentation/contribute.dart';
import 'package:lunaway/features/places/data/graphql/place_json.dart';
import 'package:lunaway/features/places/domain/place_content.dart';
import 'package:lunaway/features/vehicle/application/vehicle_providers.dart';
import 'package:lunaway/features/vehicle/domain/vehicle.dart';
import 'package:lunaway/i18n/strings.g.dart';
import 'package:lunaway/shared/labels.dart';
import 'package:lunaway/shared/theme/app_icons.dart';
import 'package:lunaway/shared/theme/tokens.dart';
import 'package:lunaway/shared/widgets/form_sheet.dart';

/// "Still there?": two taps from the place, the first opens this sheet and
/// the second sends the answer. No position goes with it.
Future<void> showConfirmSheet(BuildContext context, {required String placeId}) =>
    showFormSheet<void>(
      context,
      tall: false,
      builder: (context, scroll) => _ConfirmSheet(placeId: placeId, scrollController: scroll),
    );

class _ConfirmSheet extends ConsumerStatefulWidget {
  const new({required this.placeId, this.scrollController});

  final String placeId;
  final ScrollController? scrollController;

  @override
  ConsumerState<_ConfirmSheet> createState() => _ConfirmSheetState();
}

class _ConfirmSheetState extends ConsumerState<_ConfirmSheet> {
  final _note = TextEditingController();
  bool _sending = false;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _send(ConfirmationStatus status) async {
    if (_sending) return;
    setState(() => _sending = true);
    final navigator = Navigator.of(context);
    final note = _note.text.trim();
    // The message is shown from the place's context once the sheet is gone.
    final messengerContext = navigator.context;
    navigator.pop();
    await submitContribution(
      messengerContext,
      ContributionKind.confirm,
      placeId: widget.placeId,
      payload: {
        'placeId': widget.placeId,
        'status': status.wire,
        if (status != ConfirmationStatus.stillOk && note.isNotEmpty) 'note': note,
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final scheme = Theme.of(context).colorScheme;
    return FormSheetFrame(
      title: t.confirmSheet.title,
      subtitle: t.confirmSheet.body,
      scrollController: widget.scrollController,
      children: [
        ChoiceTile(
          icon: AppIcons.checkCircle,
          tone: scheme.secondary,
          label: t.confirmSheet.stillOk,
          onTap: _sending ? null : () => _send(ConfirmationStatus.stillOk),
        ),
        ChoiceTile(
          icon: AppIcons.closed,
          tone: scheme.error,
          label: t.confirmSheet.closed,
          hint: t.confirmSheet.closedHint,
          onTap: _sending ? null : () => _send(ConfirmationStatus.closed),
        ),
        ChoiceTile(
          icon: AppIcons.rename,
          label: t.confirmSheet.changed,
          hint: t.confirmSheet.changedHint,
          onTap: _sending ? null : () => _send(ConfirmationStatus.changed),
        ),
        const SizedBox(height: Space.s),
        TextField(
          controller: _note,
          maxLength: ContributionLimits.noteMax,
          minLines: 1,
          maxLines: 3,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(
            labelText: t.confirmSheet.note,
            hintText: t.confirmSheet.noteHint,
          ),
        ),
      ],
    );
  }
}

/// Reports a problem met at a place.
Future<void> showIssueSheet(BuildContext context, {required String placeId}) => showFormSheet<void>(
  context,
  builder: (context, scroll) => _IssueSheet(placeId: placeId, scrollController: scroll),
);

class _IssueSheet extends ConsumerStatefulWidget {
  const new({required this.placeId, this.scrollController});

  final String placeId;
  final ScrollController? scrollController;

  @override
  ConsumerState<_IssueSheet> createState() => _IssueSheetState();
}

class _IssueSheetState extends ConsumerState<_IssueSheet> {
  final _note = TextEditingController();
  IssueKind? _kind;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final kind = _kind;
    if (kind == null) return;
    final navigator = Navigator.of(context);
    final note = _note.text.trim();
    navigator.pop();
    await submitContribution(
      navigator.context,
      ContributionKind.reportIssue,
      placeId: widget.placeId,
      payload: {'placeId': widget.placeId, 'kind': kind.wire, if (note.isNotEmpty) 'note': note},
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return FormSheetFrame(
      title: t.issueSheet.title,
      subtitle: t.issueSheet.body,
      scrollController: widget.scrollController,
      action: FilledButton(onPressed: _kind == null ? null : _send, child: Text(t.issueSheet.send)),
      children: [
        for (final kind in IssueKind.values)
          ChoiceTile(
            icon: AppIcons.issue(kind),
            label: t.issueKind(kind),
            hint: t.issueHint(kind),
            selected: _kind == kind,
            onTap: () => setState(() => _kind = kind),
          ),
        const SizedBox(height: Space.s),
        TextField(
          controller: _note,
          maxLength: ContributionLimits.noteMax,
          minLines: 1,
          maxLines: 4,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(labelText: t.issueSheet.note),
        ),
      ],
    );
  }
}

/// Reports a review, a photo or a place to the moderators.
Future<void> showReportSheet(
  BuildContext context, {
  required ReportTarget target,
  required String id,
  String? placeId,
}) => showFormSheet<void>(
  context,
  builder: (context, scroll) =>
      _ReportSheet(target: target, id: id, placeId: placeId, scrollController: scroll),
);

class _ReportSheet extends ConsumerStatefulWidget {
  const new({required this.target, required this.id, this.placeId, this.scrollController});

  final ReportTarget target;
  final String id;
  final String? placeId;
  final ScrollController? scrollController;

  @override
  ConsumerState<_ReportSheet> createState() => _ReportSheetState();
}

class _ReportSheetState extends ConsumerState<_ReportSheet> {
  final _note = TextEditingController();
  ReportReason? _reason;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  bool get _ready =>
      _reason != null && (_reason != ReportReason.other || _note.text.trim().isNotEmpty);

  Future<void> _send() async {
    final reason = _reason;
    if (reason == null) return;
    final t = context.t;
    final navigator = Navigator.of(context);
    final note = _note.text.trim();
    navigator.pop();
    await submitContribution(
      navigator.context,
      ContributionKind.reportContent,
      placeId: widget.placeId,
      sentText: t.reportSheet.sent,
      payload: {
        'target': widget.target.wire,
        'id': widget.id,
        'reason': reason.wire,
        if (note.isNotEmpty) 'note': note,
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return FormSheetFrame(
      title: switch (widget.target) {
        ReportTarget.review || ReportTarget.externalReview => t.reportSheet.review,
        ReportTarget.photo || ReportTarget.externalPhoto => t.reportSheet.photo,
        ReportTarget.place => t.reportSheet.place,
      },
      subtitle: t.reportSheet.body,
      scrollController: widget.scrollController,
      action: FilledButton(onPressed: _ready ? _send : null, child: Text(t.common.send)),
      children: [
        for (final reason in ReportReason.values)
          ChoiceTile(
            icon: AppIcons.reportReason(reason),
            label: t.reportReason(reason),
            selected: _reason == reason,
            onTap: () => setState(() => _reason = reason),
          ),
        const SizedBox(height: Space.s),
        TextField(
          controller: _note,
          maxLength: ContributionLimits.noteMax,
          minLines: 1,
          maxLines: 4,
          textCapitalization: TextCapitalization.sentences,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            labelText: _reason == ReportReason.other ? t.reportSheet.noteOther : t.reportSheet.note,
          ),
        ),
      ],
    );
  }
}

/// Hides an author's reviews and photos from this account, after a word of
/// what it does.
Future<void> confirmMute(BuildContext context, WidgetRef ref, Author author) async {
  final t = context.t;
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(t.reportSheet.muteTitle(name: author.pseudonym)),
      content: Text(t.reportSheet.muteBody),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(false), child: Text(t.common.cancel)),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(t.reportSheet.muteAuthor),
        ),
      ],
    ),
  );
  if (!(ok ?? false) || !context.mounted) return;
  // Hidden at once, before the server hears of it.
  final account = ref.read(accountControllerProvider);
  if (account is SignedIn) {
    ref.read(accountControllerProvider.notifier).showMuted([
      ...account.muted.where((a) => a.id != author.id),
      author,
    ]);
  }
  await submitContribution(
    context,
    ContributionKind.mute,
    payload: {'id': author.id},
    sentText: t.reportSheet.muted(name: author.pseudonym),
  );
}

/// Writes or edits the account's review of a place.
Future<void> showReviewSheet(BuildContext context, {required String placeId, Review? existing}) =>
    showFormSheet<void>(
      context,
      builder: (context, scroll) =>
          _ReviewSheet(placeId: placeId, existing: existing, scrollController: scroll),
    );

/// The coarse kind a review names, from the user's vehicle profile.
ReviewVehicle? reviewVehicleOf(Vehicle? vehicle) => switch (vehicle?.type) {
  VehicleType.van => ReviewVehicle.van,
  VehicleType.campervan => ReviewVehicle.campervan,
  VehicleType.lowProfile ||
  VehicleType.overcab ||
  VehicleType.integrated => ReviewVehicle.motorhome,
  null => null,
};

class _ReviewSheet extends ConsumerStatefulWidget {
  const new({required this.placeId, this.existing, this.scrollController});

  final String placeId;
  final Review? existing;
  final ScrollController? scrollController;

  @override
  ConsumerState<_ReviewSheet> createState() => _ReviewSheetState();
}

class _ReviewSheetState extends ConsumerState<_ReviewSheet> {
  late final _text = TextEditingController(text: widget.existing?.text ?? '');
  late int? _stars = widget.existing?.rating;
  late DateTime? _visited = widget.existing?.visitedAt ?? _today();
  late ReviewVehicle? _vehicle =
      widget.existing?.authorVehicle ?? reviewVehicleOf(ref.read(vehicleProvider).value);
  bool _tried = false;

  DateTime _today() {
    final now = ref.read(clockProvider)();
    return DateTime(now.year, now.month, now.day);
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  int get _length => _text.text.trim().runes.length;

  bool get _valid =>
      _stars != null &&
      _length >= ContributionLimits.reviewMin &&
      _length <= ContributionLimits.reviewMax;

  Future<void> _publish() async {
    setState(() => _tried = true);
    if (!_valid) return;
    final navigator = Navigator.of(context);
    final lang = context.t.$meta.locale.languageCode;
    navigator.pop();
    await submitContribution(
      navigator.context,
      ContributionKind.review,
      placeId: widget.placeId,
      payload: {
        'placeId': widget.placeId,
        'stars': _stars,
        'text': _text.text.trim(),
        if (_visited != null) 'visitedOn': naiveDate(_visited!),
        if (_vehicle != null) 'vehicle': _vehicle!.wire,
        'lang': lang,
      },
    );
  }

  Future<void> _pickDate() async {
    final today = _today();
    final picked = await showDatePicker(
      context: context,
      initialDate: _visited ?? today,
      // An older stay already on the review stays in reach.
      firstDate: _visited != null && _visited!.year < today.year - 5
          ? _visited!
          : DateTime(today.year - 5),
      lastDate: today,
    );
    if (picked != null) setState(() => _visited = picked);
  }

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final missing = ContributionLimits.reviewMin - _length;
    return FormSheetFrame(
      title: widget.existing?.text == null ? t.reviewSheet.titleNew : t.reviewSheet.titleEdit,
      scrollController: widget.scrollController,
      footnote: Text(t.reviewSheet.licence),
      action: FilledButton(onPressed: _publish, child: Text(t.reviewSheet.publish)),
      children: [
        Text(t.contribute.yourRating, style: theme.textTheme.titleMedium),
        const SizedBox(height: Space.xs),
        StarPicker(value: _stars, onChanged: (v) => setState(() => _stars = v), size: 40),
        if (_tried && _stars == null)
          Text(
            t.reviewSheet.starsRequired,
            style: theme.textTheme.bodySmall?.copyWith(color: scheme.error),
          ),
        const SizedBox(height: Space.l),
        TextField(
          controller: _text,
          minLines: 4,
          maxLines: 10,
          maxLength: ContributionLimits.reviewMax,
          textCapitalization: TextCapitalization.sentences,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            labelText: t.reviewSheet.text,
            hintText: t.reviewSheet.textHint,
            alignLabelWithHint: true,
            helperText: missing > 0 ? t.reviewSheet.tooShort(n: missing) : null,
            errorText: _tried && missing > 0 ? t.reviewSheet.tooShort(n: missing) : null,
          ),
        ),
        const SizedBox(height: Space.s),
        // Named above the button, as the rating is: a caption under it read
        // as a note about the field that follows.
        Text(t.reviewSheet.visited, style: theme.textTheme.titleSmall),
        const SizedBox(height: Space.xs),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _pickDate,
                icon: const Icon(AppIcons.calendar),
                label: Text(
                  _visited == null
                      ? t.reviewSheet.visitedNone
                      : DateFormat.yMMMd(t.$meta.locale.languageCode).format(_visited!),
                ),
              ),
            ),
            if (_visited != null)
              IconButton(
                tooltip: t.reviewSheet.visitedNone,
                icon: const Icon(AppIcons.close),
                onPressed: () => setState(() => _visited = null),
              ),
          ],
        ),
        const SizedBox(height: Space.l),
        DropdownButtonFormField<ReviewVehicle?>(
          initialValue: _vehicle,
          decoration: InputDecoration(labelText: t.reviewSheet.vehicle),
          items: [
            DropdownMenuItem(child: Text(t.reviewSheet.vehicleNone)),
            for (final v in ReviewVehicle.values)
              DropdownMenuItem(value: v, child: Text(t.reviewVehicle(v))),
          ],
          onChanged: (v) => setState(() => _vehicle = v),
        ),
      ],
    );
  }
}

/// Five stars to pick a rating; each one a 48 dp target with its own label.
class StarPicker extends StatelessWidget {
  const new({required this.value, required this.onChanged, this.size = 32, super.key});

  final int? value;
  final ValueChanged<int> onChanged;
  final double size;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final scheme = Theme.of(context).colorScheme;
    return Wrap(
      children: [
        for (var i = 1; i <= 5; i++)
          IconButton(
            tooltip: t.contribute.rateStar(n: i),
            isSelected: value != null && i <= value!,
            onPressed: () => onChanged(i),
            iconSize: size,
            constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
            icon: Icon(
              value != null && i <= value! ? AppIcons.star : AppIcons.starEmpty,
              color: scheme.primary,
            ),
          ),
      ],
    );
  }
}
