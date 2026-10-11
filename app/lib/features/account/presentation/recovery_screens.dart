import 'dart:async';

import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:logging/logging.dart';
import 'package:lunaway/core/providers.dart';
import 'package:lunaway/core/router/routes.dart';
import 'package:lunaway/features/account/application/account_providers.dart';
import 'package:lunaway/features/account/data/card_file_io.dart'
    if (dart.library.js_interop) 'package:lunaway/features/account/data/card_file_web.dart';
import 'package:lunaway/features/account/data/recovery_qr.dart';
import 'package:lunaway/features/account/domain/recovery_code.dart';
import 'package:lunaway/features/account/presentation/account_import.dart';
import 'package:lunaway/features/community/application/community_providers.dart';
import 'package:lunaway/features/community/data/picture_picker.dart';
import 'package:lunaway/features/community/presentation/photo_flow.dart';
import 'package:lunaway/features/places/data/graphql/graphql_client.dart';
import 'package:lunaway/i18n/strings.g.dart';
import 'package:lunaway/shared/messages.dart';
import 'package:lunaway/shared/theme/app_icons.dart';
import 'package:lunaway/shared/theme/palette.dart';
import 'package:lunaway/shared/theme/tokens.dart';
import 'package:lunaway/shared/widgets/app_form.dart';
import 'package:lunaway/shared/widgets/busy_button.dart';
import 'package:lunaway/shared/widgets/sub_page.dart';
import 'package:share_plus/share_plus.dart';

final _log = Logger('recovery');

/// Makes the recovery card: what it is, then the code, shown once, as a
/// card to keep (its image to save, share or print) and as a QR code.
class RecoveryCardScreen extends ConsumerStatefulWidget {
  const new({this.returns = false, super.key});

  /// Pushed over another page (the choice of an imported account): the
  /// card, once kept, returns to it rather than to the profile.
  final bool returns;

  @override
  ConsumerState<RecoveryCardScreen> createState() => _RecoveryCardScreenState();
}

class _RecoveryCardScreenState extends ConsumerState<RecoveryCardScreen> {
  final GlobalKey _card = GlobalKey();
  String? _code;
  late DateTime _madeAt;

  Future<void> _make() async {
    final t = context.t;
    final messenger = ScaffoldMessenger.maybeOf(context);
    final account = ref.read(accountControllerProvider);
    final previous = account is SignedIn ? account.recoveryCardAt : null;
    if (previous != null && !await _confirmReplace(previous)) return;
    if (!mounted) return;
    try {
      final code = await ref.read(accountControllerProvider.notifier).createRecoveryCode();
      if (!mounted) return;
      setState(() {
        _code = code;
        _madeAt = ref.read(clockProvider)();
      });
    } on Object catch (e) {
      _log.info('no recovery code: $e');
      showMessage(messenger, t.recovery.failed);
    }
  }

  /// The card as a PNG, at print resolution.
  Future<Uint8List?> _image() async {
    final boundary = _card.currentContext?.findRenderObject() as RenderRepaintBoundary?;
    if (boundary == null) return null;
    final image = await boundary.toImage(pixelRatio: 4);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    return data?.buffer.asUint8List();
  }

  Future<void> _save() async {
    final t = context.t;
    final messenger = ScaffoldMessenger.maybeOf(context);
    final box = context.findRenderObject() as RenderBox?;
    try {
      final png = await _image();
      if (png == null) return;
      final file = await cardFile(png, t.recovery.fileName);
      await SharePlus.instance.share(
        ShareParams(
          files: [file],
          fileNameOverrides: ['${t.recovery.fileName}.png'],
          sharePositionOrigin: box == null ? null : box.localToGlobal(Offset.zero) & box.size,
        ),
      );
    } on Object catch (e) {
      _log.info('the card image was not shared: $e');
      showMessage(messenger, t.common.failed);
    }
  }

  @override
  void dispose() {
    // The image shared holds the code: it goes with the page.
    unawaited(forgetCardFiles());
    super.dispose();
  }

  /// A new card replaces the one of [previous], whose code stops working
  /// and can never be shown again: said before anything is changed.
  Future<bool> _confirmReplace(DateTime previous) async {
    final t = context.t;
    final date = DateFormat.yMMMMd(t.$meta.locale.languageCode).format(previous.toLocal());
    final replace = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(t.recovery.replaceTitle(date: date)),
        content: Text(t.recovery.replaceBody(date: date)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(t.recovery.replaceKeep),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(t.recovery.replaceConfirm),
          ),
        ],
      ),
    );
    return replace ?? false;
  }

  /// Leaves the card once the user says it is kept.
  Future<void> _leave() async {
    if (!await _confirmLeave() || !mounted) return;
    if (widget.returns) {
      Navigator.of(context).pop();
    } else {
      GoRouter.of(context).go(AppRoutes.profile);
    }
  }

  Future<bool> _confirmLeave() async {
    final t = context.t;
    final leave = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(t.recovery.doneTitle),
        content: Text(t.recovery.doneBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(t.recovery.keep),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(t.recovery.done),
          ),
        ],
      ),
    );
    return leave ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final account = ref.watch(accountControllerProvider);
    final code = _code;
    final pseudonym = account is SignedIn ? account.account.pseudonym : '';
    final hadCard = account is SignedIn && account.recoveryCardAt != null && code == null;
    return PopScope(
      canPop: code == null,
      onPopInvokedWithResult: (popped, _) async {
        if (popped) return;
        await _leave();
      },
      child: SubPage(
        title: t.recovery.title,
        subtitle: code == null ? t.recovery.intro : null,
        // The card is tall: its two ways out stay in sight under it, above
        // the dock, rather than below the fold of a phone.
        footer: code == null
            ? null
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  BusyButton(
                    onPressed: _save,
                    icon: const Icon(AppIcons.share),
                    label: Text(t.recovery.saveImage),
                    style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(56)),
                  ),
                  const SizedBox(height: Space.s),
                  OutlinedButton(
                    onPressed: _leave,
                    style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(56)),
                    child: Text(t.recovery.done),
                  ),
                ],
              ),
        children: [
          if (code == null) ...[
            if (hadCard)
              Padding(
                padding: const EdgeInsets.only(bottom: Space.l),
                child: Text(
                  t.recovery.replaces,
                  style: theme.textTheme.bodyLarge?.copyWith(color: scheme.error),
                ),
              ),
            for (final (i, step) in [t.recovery.step1, t.recovery.step2, t.recovery.step3].indexed)
              Padding(
                padding: const EdgeInsets.only(bottom: Space.m),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ExcludeSemantics(
                      child: CircleAvatar(
                        radius: 16,
                        backgroundColor: scheme.secondaryContainer,
                        child: Text(
                          '${i + 1}',
                          style: theme.textTheme.labelLarge?.copyWith(
                            color: scheme.onSecondaryContainer,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: Space.m),
                    Expanded(child: Text(step, style: theme.textTheme.bodyLarge)),
                  ],
                ),
              ),
            const SizedBox(height: Space.l),
            BusyButton(
              onPressed: account is! SignedIn ? null : _make,
              icon: const Icon(AppIcons.recoveryCard),
              label: Text(t.recovery.make),
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(56)),
            ),
          ] else ...[
            // Read before the card, which runs below the fold of a phone.
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(AppIcons.warning, color: scheme.error),
                const SizedBox(width: Space.s),
                Expanded(child: Text(t.recovery.shownOnce, style: theme.textTheme.bodyLarge)),
              ],
            ),
            const SizedBox(height: Space.l),
            RepaintBoundary(
              key: _card,
              child: RecoveryCardView(code: code, pseudonym: pseudonym, madeAt: _madeAt),
            ),
          ],
        ],
      ),
    );
  }
}

/// The card itself, as it prints: dark ink on white whatever the theme, a
/// paper to keep with the vehicle's papers. The code in large groups of
/// four, the QR code beside it, the account's name, the date, and how to
/// use it.
class RecoveryCardView extends StatelessWidget {
  const new({required this.code, required this.pseudonym, required this.madeAt, super.key});

  final String code;
  final String pseudonym;
  final DateTime madeAt;

  // Paper and ink: the card prints the same in both themes.
  static const Color _paper = Colors.white;
  static const Color _ink = Palette.minuit;
  static const Color _muted = Palette.minuit500;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final base = Theme.of(context).textTheme;
    final groups = RecoveryCode.groups(code);
    final codeStyle = base.headlineSmall?.copyWith(
      color: _ink,
      fontFamily: 'Atkinson',
      fontWeight: FontWeight.w700,
      letterSpacing: 2,
      fontFeatures: const [ui.FontFeature.tabularFigures()],
    );
    final codeView = Semantics(
      label: '${t.recovery.codeLabel} ${groups.join(' ')}',
      excludeSemantics: true,
      child: Wrap(
        spacing: Space.m,
        runSpacing: Space.xs,
        children: [for (final g in groups) Text(g, style: codeStyle)],
      ),
    );
    final qr = SizedBox.square(
      dimension: 132,
      child: CustomPaint(painter: _QrPainter(recoveryQrModules(code), _ink)),
    );
    return Container(
      padding: const EdgeInsets.all(Space.xl),
      decoration: BoxDecoration(
        color: _paper,
        borderRadius: BorderRadius.circular(LunaTokens.radiusXl),
        border: Border.all(color: Palette.creme500, width: 1.5),
      ),
      child: DefaultTextStyle.merge(
        style: base.bodyMedium?.copyWith(color: _ink),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 460;
            final text = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Image.asset(
                      'assets/brand/lunaway-mark.png',
                      height: 28,
                      excludeFromSemantics: true,
                    ),
                    const SizedBox(width: Space.s),
                    Expanded(
                      child: Text(
                        t.recovery.cardHeading,
                        style: base.titleLarge?.copyWith(color: _ink),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: Space.s),
                Text(t.recovery.cardAccount(name: pseudonym)),
                const SizedBox(height: Space.m),
                codeView,
              ],
            );
            final foot = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(t.recovery.cardHow, style: base.bodySmall?.copyWith(color: _ink)),
                const SizedBox(height: Space.xs),
                Text(t.recovery.cardWarning, style: base.bodySmall?.copyWith(color: _ink)),
                const SizedBox(height: Space.xs),
                Text(
                  t.recovery.cardMade(
                    date: DateFormat.yMMMMd(t.$meta.locale.languageCode).format(madeAt.toLocal()),
                  ),
                  style: base.bodySmall?.copyWith(color: _muted),
                ),
              ],
            );
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (wide)
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: text),
                      const SizedBox(width: Space.l),
                      qr,
                    ],
                  )
                else ...[
                  text,
                  const SizedBox(height: Space.l),
                  Center(child: qr),
                ],
                const SizedBox(height: Space.l),
                foot,
              ],
            );
          },
        ),
      ),
    );
  }
}

class _QrPainter extends CustomPainter {
  new(this.modules, this.ink);

  final List<List<bool>> modules;
  final Color ink;

  @override
  void paint(Canvas canvas, Size size) {
    // Four modules of white around the code, as scanners expect.
    const quiet = 4;
    final n = modules.length + quiet * 2;
    final cell = size.width / n;
    final paint = Paint()..color = ink;
    for (var y = 0; y < modules.length; y++) {
      for (var x = 0; x < modules[y].length; x++) {
        if (modules[y][x]) {
          canvas.drawRect(
            Rect.fromLTWH((x + quiet) * cell, (y + quiet) * cell, cell + 0.4, cell + 0.4),
            paint,
          );
        }
      }
    }
  }

  @override
  bool shouldRepaint(_QrPainter old) => old.modules != modules;
}

/// Brings an account to this device from its recovery code, typed or read
/// on a photo of the card. The code is checked here first, so a typo never
/// spends one of the server's five attempts an hour.
///
/// With [importing], the device already holds an account: the one of the
/// code opens beside it, and a sheet then asks what becomes of the two
/// (`chooseForImported`).
class RecoverScreen extends ConsumerStatefulWidget {
  const new({this.importing = false, super.key});

  final bool importing;

  @override
  ConsumerState<RecoverScreen> createState() => _RecoverScreenState();
}

class _RecoverScreenState extends ConsumerState<RecoverScreen> {
  final _code = TextEditingController();
  bool _revoke = false;

  /// The server's answer about the code typed, until it changes.
  String? _refused;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _read() async {
    final t = context.t;
    final messenger = ScaffoldMessenger.maybeOf(context);
    final picker = ref.read(picturePickerProvider);
    var source = PictureSource.gallery;
    if (picker.offers(PictureSource.camera)) {
      final chosen = await chooseSource(context);
      if (chosen == null) return;
      source = chosen;
    }
    final bytes = await picker.pick(source);
    if (bytes == null || !mounted) return;
    final code = await showBusy(context, t.recover.reading, readRecoveryCard(bytes));
    if (!mounted) return;
    if (code == null) {
      showMessage(messenger, t.recover.scanFailed);
      return;
    }
    setState(() {
      _code.text = code;
      _refused = null;
    });
  }

  /// Asks the server for the account (the form has checked the code): a
  /// code it does not know shows on the field, a refusal or a failure above
  /// the button, the code kept.
  Future<void> _submit() async {
    final t = context.t;
    final code = RecoveryCode.parse(_code.text);
    if (code == null) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    final router = GoRouter.of(context);
    try {
      if (widget.importing) {
        await _import(code);
        return;
      }
      final outbox = ref.read(outboxStoreProvider);
      final account = await ref
          .read(accountControllerProvider.notifier)
          .recover(code, revokeOthers: _revoke);
      // The contributions waiting on this device belong to the account now.
      await outbox.claimFor(account.id);
      showMessage(messenger, t.recover.done(name: account.pseudonym));
      router.go(AppRoutes.profile);
    } on FormRefused {
      rethrow;
    } on GraphQLRateLimitedException {
      throw FormFailure(t.recover.tooMany, retry: false);
    } on GraphQLResponseException catch (e) {
      if (e.hasCode(GraphQLError.rateLimited)) throw FormFailure(t.recover.tooMany, retry: false);
      if (e.hasCode(GraphQLError.notFound) || e.hasCode(GraphQLError.invalidInput)) {
        if (mounted) {
          setState(
            () => _refused = e.hasCode(GraphQLError.notFound)
                ? t.recover.notFound
                : t.recover.invalid,
          );
        }
        throw const FormRefused();
      }
      throw FormFailure(t.common.failed);
    } on Object catch (e) {
      _log.info('recovery failed: $e');
      throw FormFailure(t.common.offline);
    }
  }

  /// Opens the account of [code] beside the device's, then asks what
  /// becomes of the two. The card of the device's own account opens it
  /// again: said on the field, and its new key detached at once.
  Future<void> _import(String code) async {
    final t = context.t;
    final controller = ref.read(accountControllerProvider.notifier);
    final current = ref.read(accountControllerProvider);
    final imported = await controller.importAccount(code);
    if (!mounted || current is! SignedIn) {
      await controller.cancelImport(imported);
      return;
    }
    if (current.account.id == imported.account.id) {
      await controller.cancelImport(imported);
      if (mounted) {
        setState(() => _refused = t.accountImport.same(current: current.account.pseudonym));
      }
      throw const FormRefused();
    }
    await chooseForImported(context, ref, imported);
  }

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final account = ref.watch(accountControllerProvider);
    final current = account is SignedIn ? account.account.pseudonym : '';
    final symbols = RecoveryCode.symbolsOf(_code.text);
    final valid = RecoveryCode.parse(_code.text) != null;
    final remaining = symbols == null ? 0 : RecoveryCode.symbols - symbols.length;
    // Said as the user types: how many symbols are left, then whether the
    // check symbol agrees once they are all there.
    String? hint;
    if (valid) {
      hint = t.recover.valid;
    } else if (symbols != null && remaining > 0 && remaining < RecoveryCode.symbols) {
      hint = t.recover.remaining(n: remaining);
    }
    final complete = symbols == null || remaining <= 0;
    return LunaForm(
      onSubmit: _submit,
      child: SubPage(
        // A form: every field built, so the button checks them all.
        builtWhole: true,
        title: widget.importing ? t.accountImport.title : t.recover.title,
        subtitle: widget.importing ? t.accountImport.intro(current: current) : t.recover.intro,
        children: [
          LunaTextField(
            controller: _code,
            label: t.recover.field,
            hint: t.recover.fieldHint,
            icon: AppIcons.recoveryCard,
            autocorrect: false,
            enableSuggestions: false,
            textCapitalization: TextCapitalization.characters,
            inputFormatters: [LengthLimitingTextInputFormatter(60)],
            style: theme.textTheme.titleLarge?.copyWith(fontFamily: 'Atkinson', letterSpacing: 1.5),
            onChanged: (_) => setState(() => _refused = null),
            // The code opens the account: no keyboard learns it or suggests it.
            keyboardType: TextInputType.visiblePassword,
            enableIMEPersonalizedLearning: false,
            // The keyboard's own key sends the code, as the button does.
            textInputAction: TextInputAction.go,
            helper: hint,
            // A code whole but wrong is said at once, before the server would
            // spend one of its five attempts an hour on it.
            error:
                _refused ??
                (complete && !valid && _code.text.trim().isNotEmpty ? t.recover.invalid : null),
            suffixIcon: valid ? Icon(AppIcons.checkCircle, color: scheme.secondary) : null,
            validator: (text) {
              final symbols = RecoveryCode.symbolsOf(text ?? '');
              if ((text ?? '').trim().isEmpty) return t.recover.required;
              if (RecoveryCode.parse(text ?? '') != null) return null;
              final left = symbols == null ? 0 : RecoveryCode.symbols - symbols.length;
              return left > 0 ? t.recover.remaining(n: left) : t.recover.invalid;
            },
          ),
          const SizedBox(height: Space.m),
          BusyButton(
            onPressed: _read,
            look: BusyLook.outlined,
            icon: const Icon(AppIcons.scan),
            label: Text(
              ref.read(picturePickerProvider).offers(PictureSource.camera)
                  ? t.recover.scan
                  : t.recover.scanFile,
            ),
            style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(56)),
          ),
          // The other devices of an account opened beside this one's are
          // its own business: the import leaves them as they are.
          if (!widget.importing) ...[
            const SizedBox(height: Space.l),
            CheckboxListTile(
              value: _revoke,
              onChanged: (v) => setState(() => _revoke = v ?? false),
              contentPadding: EdgeInsets.zero,
              title: Text(t.recover.revoke),
              subtitle: Text(t.recover.revokeHint),
            ),
          ],
          const SizedBox(height: Space.l),
          SubmitButton(
            label: widget.importing ? t.accountImport.submit : t.recover.submit,
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(56)),
          ),
        ],
      ),
    );
  }
}
