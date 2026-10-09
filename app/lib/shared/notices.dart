import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show IconData;

/// The one rule every notice of the app follows (the guidance, the route
/// preview, the map). There are two kinds.
///
/// A passing notice tells of something that just happened: a new route, a
/// stop removed, a report sent. It shows for [NoticeTimes.passing] (a
/// little longer with an action to reach, [NoticeTimes.withAction]), then
/// fades; a tap or a swipe towards its edge closes it at once. One at a
/// time: the most recent replaces the one shown, unless that one matters
/// more ([NoticePriority]).
///
/// A standing notice tells of a state that lasts: the position lost, a
/// danger zone the vehicle is in, the route left. It shows as long as the
/// state holds and leaves with it; a tap or a swipe folds it into a small
/// chip, which opens again by itself if the state worsens.
///
/// A screen reader announces each notice once, when it appears (a standing
/// notice again when it worsens), never at each change of a figure in it.
abstract final class NoticeTimes {
  /// Long enough to be read at a glance, short enough not to linger over
  /// the road.
  static const passing = Duration(seconds: 4);

  /// With an action (undo): the time to reach it.
  static const withAction = Duration(seconds: 6);
}

/// How much a passing notice matters against the one shown.
enum NoticePriority {
  /// Shown only when nothing else is: dropped otherwise ("searching a new
  /// route", a new route after the user's own change).
  quiet,

  /// The default.
  normal,

  /// What the road ahead holds (a closure, no other way): a normal notice
  /// that comes meanwhile waits for it to go.
  urgent,
}

/// What a passing notice offers besides closing.
@immutable
final class NoticeAction {
  const new({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;
}

/// Something that just happened, said for a moment.
@immutable
final class PassingNotice {
  const new({
    required this.text,
    this.id,
    this.icon,
    this.strong = false,
    this.priority = NoticePriority.normal,
    this.action,
    this.about,
  });

  final String text;

  /// The same news told again (a new route that now also tells of a stop
  /// moved): it takes the place of the one shown under the same id, and
  /// shows for its whole time again.
  final Object? id;

  final IconData? icon;

  /// A problem rather than news: drawn in the error colours.
  final bool strong;
  final NoticePriority priority;
  final NoticeAction? action;

  /// What it speaks of (a road event's id): a standing notice about the
  /// same thing stays out of sight while this one shows.
  final Object? about;
}

/// The notices of one screen: the passing notice shown, the one waiting
/// behind a more pressing one, and the standing notices the user folded.
/// The screen draws what this says (`NoticeColumn`).
final class NoticeBoard extends ChangeNotifier {
  PassingNotice? _current;
  Timer? _currentTimer;
  int _serial = 0;
  PassingNotice? _waiting;
  Timer? _waitingTimer;
  final Map<Object, int> _folded = {};
  final Set<Object> _seen = {};
  bool _disposed = false;

  /// A screen reader or switch access drives the device: a passing notice
  /// with an action then stays until it is closed, so the action can be
  /// reached.
  bool assisted = false;

  /// The passing notice shown, or none.
  PassingNotice? get current => _current;

  /// Counts the passing notices shown: a new one, or the same one told
  /// again, has a new number.
  int get serial => _serial;

  /// Shows [notice] in place of the one shown, unless that one matters
  /// more: then [notice] waits for it to go, or is dropped when it is
  /// [NoticePriority.quiet]. Only the latest notice waits, and only as long
  /// as it would have shown.
  void say(PassingNotice notice) {
    if (_disposed) return;
    final current = _current;
    final sameNews = notice.id != null && notice.id == current?.id;
    if (current == null || sameNews || notice.priority.index >= current.priority.index) {
      _show(notice);
      return;
    }
    if (notice.priority == NoticePriority.quiet) return;
    final waiting = _waiting;
    if (waiting != null && waiting.priority.index > notice.priority.index) return;
    _waitingTimer?.cancel();
    _waiting = notice;
    _waitingTimer = Timer(_timeOf(notice), () {
      _waiting = null;
      _waitingTimer = null;
    });
  }

  /// Closes the passing notice shown: the one waiting, if any, shows next.
  void dismiss() {
    if (_disposed || _current == null) return;
    _currentTimer?.cancel();
    _currentTimer = null;
    _current = null;
    final next = _waiting;
    _waitingTimer?.cancel();
    _waitingTimer = null;
    _waiting = null;
    if (next != null) {
      _show(next);
    } else {
      notifyListeners();
    }
  }

  /// Takes back the notice of [id], shown or waiting: what it said no
  /// longer holds ("searching a new route" once the search is over).
  void withdraw(Object id) {
    if (_waiting?.id == id) {
      _waitingTimer?.cancel();
      _waitingTimer = null;
      _waiting = null;
    }
    if (_current?.id == id) dismiss();
  }

  void _show(PassingNotice notice) {
    _currentTimer?.cancel();
    _current = notice;
    _serial++;
    final stays = notice.action != null && assisted;
    _currentTimer = stays ? null : Timer(_timeOf(notice), dismiss);
    notifyListeners();
  }

  static Duration _timeOf(PassingNotice notice) =>
      notice.action == null ? NoticeTimes.passing : NoticeTimes.withAction;

  /// Whether the standing notice [id] is folded at [level]. One that rose
  /// above the level it was folded at opens again, and stays open until
  /// folded anew.
  bool isFolded(Object id, int level) {
    final at = _folded[id];
    if (at == null) return false;
    if (level <= at) return true;
    // Bookkeeping only: the caller is drawing it open already.
    _folded.remove(id);
    return false;
  }

  /// The user folded the standing notice [id], shown at [level].
  void fold(Object id, int level) {
    _folded[id] = level;
    notifyListeners();
  }

  /// The user opened the folded notice [id] again.
  void unfold(Object id) {
    if (_folded.remove(id) != null) notifyListeners();
  }

  /// The standing notices on screen are [ids]: the others' states are over,
  /// and so is their folding and their telling (one that comes back later
  /// shows open, and a screen reader hears of it again). The passing notices
  /// gone are forgotten too. Bookkeeping only, nothing to draw again.
  void keepOnly(Set<Object> ids) {
    _folded.removeWhere((id, _) => !ids.contains(id));
    _seen.removeWhere(
      (key) => switch (key) {
        ('standing', final Object id, _) => !ids.contains(id),
        // The one fading out may still be built once more.
        ('passing', final int serial) => serial < _serial - 1,
        _ => false,
      },
    );
  }

  /// What a screen reader is told of once: the passing notice of [serial].
  static Object passingKey(int serial) => ('passing', serial);

  /// The standing notice [id] at [level]: graver is told again, a figure
  /// that changes inside it is not.
  static Object standingKey(Object id, int level) => ('standing', id, level);

  /// Whether a screen reader has been told of [key] ([passingKey],
  /// [standingKey]).
  bool seen(Object key) => _seen.contains(key);

  /// A screen reader has been told of [key]: it is not told again.
  void markSeen(Object key) {
    if (_seen.add(key) && !_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _currentTimer?.cancel();
    _waitingTimer?.cancel();
    super.dispose();
  }
}
