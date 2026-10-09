import 'package:flutter/material.dart';
import 'package:lunaway/i18n/strings.g.dart';
import 'package:lunaway/shared/notices.dart';
import 'package:lunaway/shared/theme/motion.dart';
import 'package:lunaway/shared/theme/tokens.dart';
import 'package:lunaway/shared/widgets/over_map.dart';

/// Gives the widgets below it the [NoticeBoard] of their screen.
class NoticeScope extends InheritedNotifier<NoticeBoard> {
  const new({required NoticeBoard board, required super.child, super.key}) : super(notifier: board);

  /// The board of the nearest scope, listened to.
  static NoticeBoard of(BuildContext context) => maybeOf(context)!;

  static NoticeBoard? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<NoticeScope>()?.notifier;
}

/// A state that lasts, as the screen declares it at each build: shown
/// while it is declared, folded into a chip by the user ([NoticeTimes]).
@immutable
final class StandingNotice {
  const new({
    required this.id,
    required this.text,
    required this.icon,
    this.level = 1,
    this.strong = false,
    this.look,
    this.tellsItself = false,
    this.action,
    this.below,
  });

  /// The same state from one build to the next (the position, a road event
  /// by its id).
  final Object id;

  /// What it says: the card's text, the folded chip's tooltip.
  final String text;
  final IconData icon;

  /// How grave the state is now: folded at one level, the notice opens
  /// again at a higher one (a danger zone ahead, then entered).
  final int level;

  /// A problem: drawn in the error colours.
  final bool strong;

  /// A look of its own in place of the card (a restriction's tile).
  final Widget? look;

  /// [look] makes a node of its own for its words and marks it live
  /// ([NoticeLive]): the notice's node is then not live, so a screen
  /// reader hears it once, not twice.
  final bool tellsItself;

  /// Beside the text: its own buttons (install the voice, close it).
  final Widget? action;

  /// Under the text: answers (a community report's "still there?").
  final Widget? below;
}

/// The notices of a screen, one under the other: the standing notices
/// open, the folded ones as a row of chips, then the passing notice of the
/// [NoticeBoard] in scope, which fades in and out. A tap or a swipe up
/// closes a passing notice and folds a standing one; a tap on a chip
/// opens it again.
class NoticeColumn extends StatelessWidget {
  const new({required this.standing, this.gap = Space.s, this.centred = false, super.key});

  final List<StandingNotice> standing;

  /// Above each notice.
  final double gap;

  /// Each notice at its own width, centred, rather than across the column
  /// (the map's offline line, a pill under the search).
  final bool centred;

  @override
  Widget build(BuildContext context) {
    final board = NoticeScope.of(context)..keepOnly({for (final s in standing) s.id});
    final open = <StandingNotice>[];
    final folded = <StandingNotice>[];
    for (final s in standing) {
      (board.isFolded(s.id, s.level) ? folded : open).add(s);
    }
    return AnimatedSize(
      duration: Motion.of(context, Motion.medium),
      curve: Motion.standard,
      alignment: Alignment.topCenter,
      child: Column(
        crossAxisAlignment: centred ? CrossAxisAlignment.center : CrossAxisAlignment.stretch,
        children: [
          for (final s in open)
            Padding(
              key: ValueKey(('standing', s.id)),
              padding: EdgeInsets.only(top: gap),
              child: _StandingCard(notice: s, board: board),
            ),
          if (folded.isNotEmpty)
            Padding(
              padding: EdgeInsets.only(top: gap),
              child: Align(
                alignment: centred ? Alignment.center : AlignmentDirectional.centerStart,
                child: Wrap(
                  spacing: Space.s,
                  runSpacing: Space.s,
                  children: [
                    for (final s in folded)
                      _FoldedChip(
                        key: ValueKey(('folded', s.id)),
                        notice: s,
                        onTap: () => board.unfold(s.id),
                      ),
                  ],
                ),
              ),
            ),
          _PassingSlot(board: board, gap: gap),
        ],
      ),
    );
  }
}

/// The passing notice of the board, faded in, faded out.
class _PassingSlot extends StatelessWidget {
  const new({required this.board, required this.gap});

  final NoticeBoard board;
  final double gap;

  @override
  Widget build(BuildContext context) {
    final notice = board.current;
    return AnimatedSwitcher(
      duration: Motion.of(context, Motion.medium),
      switchInCurve: Motion.enter,
      switchOutCurve: Motion.exit,
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: SizeTransition(sizeFactor: animation, alignment: Alignment.topCenter, child: child),
      ),
      // The one fading out takes no more touches: a tap on it would close
      // the one that replaced it.
      layoutBuilder: (current, previous) => Stack(
        alignment: Alignment.topCenter,
        children: [
          for (final p in previous) IgnorePointer(child: p),
          ?current,
        ],
      ),
      child: notice == null
          ? const SizedBox(key: ValueKey('no notice'), width: double.infinity)
          : Padding(
              key: ValueKey(('passing', board.serial)),
              padding: EdgeInsets.only(top: gap),
              child: _PassingCard(notice: notice, board: board, serial: board.serial),
            ),
    );
  }
}

class _PassingCard extends StatelessWidget {
  const new({required this.notice, required this.board, required this.serial});

  final PassingNotice notice;
  final NoticeBoard board;
  final int serial;

  @override
  Widget build(BuildContext context) {
    final action = notice.action;
    return _Touchable(
      board: board,
      seenKey: NoticeBoard.passingKey(serial),
      hint: context.t.notices.close,
      onClose: board.dismiss,
      child: NoticeCard(
        text: notice.text,
        icon: notice.icon,
        strong: notice.strong,
        action: action == null
            ? null
            : TextButton(
                onPressed: () {
                  board.dismiss();
                  action.onPressed();
                },
                child: Text(action.label),
              ),
      ),
    );
  }
}

class _StandingCard extends StatelessWidget {
  const new({required this.notice, required this.board});

  final StandingNotice notice;
  final NoticeBoard board;

  @override
  Widget build(BuildContext context) => _Touchable(
    board: board,
    // Worse is told again; a figure that changes inside it is not.
    seenKey: NoticeBoard.standingKey(notice.id, notice.level),
    hint: context.t.notices.fold,
    onClose: () => board.fold(notice.id, notice.level),
    tellsItself: notice.tellsItself,
    child:
        notice.look ??
        NoticeCard(
          text: notice.text,
          icon: notice.icon,
          strong: notice.strong,
          action: notice.action,
          below: notice.below,
        ),
  );
}

/// A notice that closes (or folds) on a tap, a swipe up, or a screen
/// reader's dismiss; a live region on its first frame only, so a screen
/// reader tells of it once and not at each change of a figure in it.
class _Touchable extends StatefulWidget {
  const new({
    required this.board,
    required this.seenKey,
    required this.hint,
    required this.onClose,
    required this.child,
    this.tellsItself = false,
  });

  final NoticeBoard board;
  final Object seenKey;
  final String hint;
  final VoidCallback onClose;
  final Widget child;

  /// The child marks its own node live ([StandingNotice.tellsItself]).
  final bool tellsItself;

  @override
  State<_Touchable> createState() => _TouchableState();
}

/// An upward swipe past this many logical pixels, or this fast, closes.
const double _swipeUpBy = 24;
const double _swipeUpSpeed = 300;

class _TouchableState extends State<_Touchable> {
  double _dragged = 0;

  @override
  Widget build(BuildContext context) {
    final live = !widget.board.seen(widget.seenKey);
    if (live) {
      final board = widget.board;
      final key = widget.seenKey;
      WidgetsBinding.instance.addPostFrameCallback((_) => board.markSeen(key));
    }
    return OverMap(
      child: Semantics(
        container: true,
        liveRegion: live && !widget.tellsItself,
        onTap: widget.onClose,
        onTapHint: widget.hint,
        onDismiss: widget.onClose,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            // The node above carries the tap and the dismiss; a swipe is no
            // scroll to offer a screen reader.
            excludeFromSemantics: true,
            onTap: widget.onClose,
            onVerticalDragStart: (_) => _dragged = 0,
            onVerticalDragUpdate: (d) => _dragged += d.delta.dy,
            onVerticalDragEnd: (d) {
              if (_dragged <= -_swipeUpBy || (d.primaryVelocity ?? 0) <= -_swipeUpSpeed) {
                widget.onClose();
              }
            },
            child: NoticeLive(live: live, child: widget.child),
          ),
        ),
      ),
    );
  }
}

/// Whether the notice around is on its first frame, told to a screen reader
/// now. A look that makes a semantics node of its own for its words (a
/// button of its own) marks that node live with it; the words of any other
/// look join the notice's node, which is live already.
class NoticeLive extends InheritedWidget {
  const new({required this.live, required super.child, super.key});

  final bool live;

  static bool of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<NoticeLive>()?.live ?? false;

  @override
  bool updateShouldNotify(NoticeLive oldWidget) => oldWidget.live != live;
}

/// A standing notice folded: its icon in a small pill, its words in the
/// tooltip; a tap opens it again.
class _FoldedChip extends StatelessWidget {
  const new({required this.notice, required this.onTap, super.key});

  final StandingNotice notice;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (bg, fg) = notice.strong
        ? (scheme.errorContainer, scheme.onErrorContainer)
        : (scheme.secondaryContainer, scheme.onSecondaryContainer);
    final height = controlHeight(context, 48);
    return OverMap(
      child: Tooltip(
        message: notice.text,
        // The chip's own label says it.
        excludeFromSemantics: true,
        child: Semantics(
          button: true,
          label: notice.text,
          onTapHint: context.t.notices.unfold,
          child: Material(
            color: bg,
            shape: const StadiumBorder(),
            elevation: 2,
            child: InkWell(
              customBorder: const StadiumBorder(),
              mouseCursor: WidgetStateMouseCursor.clickable,
              onTap: onTap,
              child: SizedBox(
                height: height,
                width: height + Space.m,
                child: Icon(notice.icon, color: fg),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The look of a notice: a rounded card, teal for news, in the error
/// colours for a problem; its icon, its words, its own buttons beside them
/// and its answers under them.
class NoticeCard extends StatelessWidget {
  const new({
    required this.text,
    this.icon,
    this.strong = false,
    this.action,
    this.below,
    super.key,
  });

  final String text;
  final IconData? icon;
  final bool strong;
  final Widget? action;
  final Widget? below;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final (bg, fg) = strong
        ? (scheme.errorContainer, scheme.onErrorContainer)
        : (scheme.secondaryContainer, scheme.onSecondaryContainer);
    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(LunaTokens.radiusL),
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: Space.m, vertical: Space.sm),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                if (icon != null) ...[Icon(icon, color: fg), const SizedBox(width: Space.m)],
                Expanded(
                  child: Text(text, style: theme.textTheme.titleSmall?.copyWith(color: fg)),
                ),
                ?action,
              ],
            ),
            if (below case final below?) ...[const SizedBox(height: Space.s), below],
          ],
        ),
      ),
    );
  }
}
