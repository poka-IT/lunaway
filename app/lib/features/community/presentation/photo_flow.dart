import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:lunaway/features/account/domain/account.dart';
import 'package:lunaway/features/community/application/community_providers.dart';
import 'package:lunaway/features/community/data/photo_prepare.dart';
import 'package:lunaway/features/community/data/picture_picker.dart';
import 'package:lunaway/features/community/domain/contribution.dart';
import 'package:lunaway/features/community/presentation/contribute.dart';
import 'package:lunaway/i18n/strings.g.dart';
import 'package:lunaway/shared/messages.dart';
import 'package:lunaway/shared/theme/app_icons.dart';
import 'package:lunaway/shared/theme/tokens.dart';
import 'package:lunaway/shared/widgets/form_sheet.dart';

final _log = Logger('photo');

/// Picks a picture (camera or gallery on a phone, a file elsewhere) and
/// prepares it for the API; null when the user cancels or the picture
/// cannot be read (said in a message).
Future<PreparedPhoto?> pickPhoto(BuildContext context, WidgetRef ref) async {
  final t = context.t;
  final messenger = ScaffoldMessenger.maybeOf(context);
  final picker = ref.read(picturePickerProvider);
  var source = PictureSource.gallery;
  if (picker.offers(PictureSource.camera)) {
    final chosen = await chooseSource(context);
    if (chosen == null) return null;
    source = chosen;
  }
  final bytes = await picker.pick(source);
  if (bytes == null || !context.mounted) return null;
  try {
    return await showBusy(
      context,
      t.photoFlow.preparing,
      ref.read(photoPreparerProvider).prepare(bytes),
    );
  } on Object catch (e) {
    _log.info('the picture could not be prepared: $e');
    showMessage(messenger, t.photoFlow.unreadable);
    return null;
  }
}

/// The camera or the gallery, as two large choices.
Future<PictureSource?> chooseSource(BuildContext context) {
  final t = context.t;
  return showFormSheet<PictureSource>(
    context,
    tall: false,
    builder: (context, scroll) => FormSheetFrame(
      title: t.photoFlow.title,
      scrollController: scroll,
      children: [
        ChoiceTile(
          icon: AppIcons.camera,
          label: t.photoFlow.camera,
          onTap: () => Navigator.of(context).pop(PictureSource.camera),
        ),
        ChoiceTile(
          icon: AppIcons.gallery,
          label: t.photoFlow.gallery,
          onTap: () => Navigator.of(context).pop(PictureSource.gallery),
        ),
      ],
    ),
  );
}

/// Shows [text] with a spinner while [work] runs; the user cannot leave it
/// half done.
Future<T> showBusy<T>(BuildContext context, String text, Future<T> work) async {
  final navigator = Navigator.of(context, rootNavigator: true);
  var open = true;
  final route = DialogRoute<void>(
    context: context,
    barrierDismissible: false,
    builder: (context) => PopScope(
      canPop: false,
      child: AlertDialog(
        content: Row(
          children: [
            const SizedBox.square(dimension: 28, child: CircularProgressIndicator()),
            const SizedBox(width: Space.l),
            Expanded(child: Text(text)),
          ],
        ),
      ),
    ),
  );
  unawaited(navigator.push(route).whenComplete(() => open = false));
  try {
    return await work;
  } finally {
    if (open && route.isActive) navigator.removeRoute(route);
  }
}

/// Adds a photo to a place: the level first, then the picture, a look at
/// it with what its publication means, and the outbox, which sends it now
/// or when the network comes back.
Future<void> addPhotoToPlace(BuildContext context, WidgetRef ref, String placeId) async {
  final t = context.t;
  if (!await passesGate(context, ref, level: TrustLevels.photo, title: t.gate.photo)) return;
  if (!context.mounted) return;
  final photo = await pickPhoto(context, ref);
  if (photo == null || !context.mounted) return;
  final send = await showFormSheet<bool>(
    context,
    builder: (context, scroll) => PhotoPreview(photo: photo, scrollController: scroll),
  );
  if (!(send ?? false) || !context.mounted) return;
  final fileId = await ref.read(pendingFilesProvider).put(photo.jpeg);
  if (!context.mounted) return;
  await submitContribution(
    context,
    ContributionKind.photo,
    placeId: placeId,
    fileId: fileId,
    payload: {'placeId': placeId},
  );
}

/// The prepared photo before it is sent, with its licence and what is
/// taken out of it.
class PhotoPreview extends StatelessWidget {
  const new({required this.photo, this.scrollController, super.key});

  final PreparedPhoto photo;
  final ScrollController? scrollController;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final theme = Theme.of(context);
    return FormSheetFrame(
      title: t.photoFlow.title,
      scrollController: scrollController,
      footnote: Text(t.photoFlow.licence),
      action: FilledButton.icon(
        onPressed: () => Navigator.of(context).pop(true),
        icon: const Icon(AppIcons.uploading),
        label: Text(t.photoFlow.send),
      ),
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(LunaTokens.radiusL),
          child: AspectRatio(
            aspectRatio: photo.width / photo.height,
            child: Image.memory(photo.jpeg, fit: BoxFit.cover, excludeFromSemantics: true),
          ),
        ),
        const SizedBox(height: Space.m),
        Row(
          children: [
            Icon(AppIcons.privacy, color: theme.colorScheme.secondary),
            const SizedBox(width: Space.s),
            Expanded(child: Text(t.photoFlow.stripped, style: theme.textTheme.bodyMedium)),
          ],
        ),
      ],
    );
  }
}
