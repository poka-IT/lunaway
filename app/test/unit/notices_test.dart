import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunaway/shared/notices.dart';

void main() {
  PassingNotice notice(
    String text, {
    NoticePriority priority = NoticePriority.normal,
    Object? id,
    bool action = false,
  }) => PassingNotice(
    text: text,
    id: id,
    priority: priority,
    action: action ? NoticeAction(label: 'Annuler', onPressed: () {}) : null,
  );

  group('a passing notice', () {
    test('leaves by itself after 4 s, one with an action after 6 s', () {
      fakeAsync((async) {
        final board = NoticeBoard()..say(notice('Nouvel itinéraire'));
        async.elapse(const Duration(milliseconds: 3900));
        expect(board.current?.text, 'Nouvel itinéraire');
        async.elapse(const Duration(milliseconds: 200));
        expect(board.current, isNull);

        board.say(notice('Étape retirée', action: true));
        async.elapse(const Duration(milliseconds: 5900));
        expect(board.current?.text, 'Étape retirée');
        async.elapse(const Duration(milliseconds: 200));
        expect(board.current, isNull);
      });
    });

    test('with an action, stays until closed under a screen reader', () {
      fakeAsync((async) {
        final board = NoticeBoard()
          ..assisted = true
          ..say(notice('Étape retirée', action: true));
        async.elapse(const Duration(minutes: 1));
        expect(board.current?.text, 'Étape retirée');
        board.dismiss();
        expect(board.current, isNull);
        // Without an action, it leaves as for anyone.
        board.say(notice('Signalement envoyé'));
        async.elapse(const Duration(seconds: 5));
        expect(board.current, isNull);
      });
    });

    test('is replaced by the most recent, which shows its whole time', () {
      fakeAsync((async) {
        final board = NoticeBoard()..say(notice('Recherche'));
        async.elapse(const Duration(seconds: 3));
        board.say(notice('Nouvel itinéraire'));
        expect(board.current?.text, 'Nouvel itinéraire');
        async.elapse(const Duration(seconds: 3));
        expect(board.current?.text, 'Nouvel itinéraire', reason: "the first one's time is not its");
        async.elapse(const Duration(seconds: 2));
        expect(board.current, isNull);
      });
    });

    test('of lower priority waits for the urgent one, then shows its whole time', () {
      fakeAsync((async) {
        final board = NoticeBoard()
          ..say(notice('Route fermée', priority: NoticePriority.urgent))
          ..say(notice('Signalement envoyé'));
        expect(board.current?.text, 'Route fermée');
        async.elapse(const Duration(seconds: 3));
        expect(board.current?.text, 'Route fermée');
        async.elapse(const Duration(seconds: 1));
        expect(board.current?.text, 'Signalement envoyé', reason: 'its turn, once the other went');
        async.elapse(const Duration(milliseconds: 3900));
        expect(board.current?.text, 'Signalement envoyé');
        async.elapse(const Duration(milliseconds: 200));
        expect(board.current, isNull);
      });
    });

    test('waits only as long as it would have shown, and only the latest waits', () {
      fakeAsync((async) {
        final board = NoticeBoard()
          ..assisted = true
          // Stays: an action under a screen reader.
          ..say(notice('Route fermée', priority: NoticePriority.urgent, action: true))
          ..say(notice('Premier'))
          ..say(notice('Second'));
        async.elapse(const Duration(seconds: 2));
        board.dismiss();
        expect(board.current?.text, 'Second', reason: 'the latest waited, not the first');
        board
          ..say(notice('Route fermée', priority: NoticePriority.urgent, action: true))
          ..say(notice('Trop tard'));
        async.elapse(const Duration(seconds: 5));
        board.dismiss();
        expect(board.current, isNull, reason: 'it waited longer than its own time');
      });
    });

    test('quiet, shows only when nothing else does', () {
      fakeAsync((async) {
        final board = NoticeBoard()..say(notice('Étape retirée'));
        async.elapse(const Duration(seconds: 1));
        board.say(notice('Recherche', priority: NoticePriority.quiet));
        expect(board.current?.text, 'Étape retirée');
        // The other one leaves at 4 s, within the quiet one's own time.
        async.elapse(const Duration(milliseconds: 3100));
        expect(board.current, isNull, reason: 'dropped, not kept for later');
        board.say(notice('Recherche', priority: NoticePriority.quiet));
        expect(board.current?.text, 'Recherche');
        board.say(notice('Nouvel itinéraire', priority: NoticePriority.quiet));
        expect(
          board.current?.text,
          'Nouvel itinéraire',
          reason: 'a quiet one replaces a quiet one',
        );
      });
    });

    test('told again under the same id takes the place of the shown one, its time anew', () {
      fakeAsync((async) {
        final board = NoticeBoard()..say(notice('Nouvel itinéraire', id: 'alert'));
        final first = board.serial;
        async.elapse(const Duration(seconds: 3));
        board.say(
          notice(
            'Nouvel itinéraire\nÉtape 1 déplacée',
            id: 'alert',
            priority: NoticePriority.quiet,
          ),
        );
        expect(board.current?.text, 'Nouvel itinéraire\nÉtape 1 déplacée');
        expect(board.serial, greaterThan(first), reason: 'a new notice to tell of');
        async.elapse(const Duration(seconds: 3));
        expect(board.current, isNotNull);
      });
    });

    test('closed by the user lets the waiting one show at once', () {
      fakeAsync((async) {
        final board = NoticeBoard()
          ..say(notice('Route fermée', priority: NoticePriority.urgent))
          ..say(notice('Signalement envoyé'))
          ..dismiss();
        expect(board.current?.text, 'Signalement envoyé');
        board.dismiss();
        expect(board.current, isNull);
        async.elapse(const Duration(seconds: 10));
        expect(board.current, isNull);
      });
    });

    test('taken back, shown or waiting, is gone', () {
      fakeAsync((async) {
        final board = NoticeBoard()
          ..say(notice('Route fermée', priority: NoticePriority.urgent))
          ..say(notice('Recherche', id: 'searching'))
          ..withdraw('searching')
          ..dismiss();
        expect(board.current, isNull, reason: 'no longer waiting');
        board
          ..say(notice('Recherche', id: 'searching'))
          ..withdraw('searching');
        expect(board.current, isNull);
      });
    });
  });

  group('a standing notice', () {
    test('folded stays folded at its level, and opens again once graver', () {
      final board = NoticeBoard()..fold('position', 1);
      expect(board.isFolded('position', 1), isTrue);
      expect(board.isFolded('position', 2), isFalse, reason: 'the position lost after old');
      expect(board.isFolded('position', 1), isFalse, reason: 'open until folded anew');
      board.fold('position', 2);
      expect(board.isFolded('position', 1), isTrue, reason: 'better again: stays folded');
    });

    test('ended forgets its folding: back later, it shows open', () {
      final board = NoticeBoard()
        ..fold('off route', 1)
        ..fold('voice', 1)
        ..keepOnly({'voice'});
      expect(board.isFolded('off route', 1), isFalse);
      expect(board.isFolded('voice', 1), isTrue);
      board.unfold('voice');
      expect(board.isFolded('voice', 1), isFalse);
    });

    test('is told to a screen reader once per key', () {
      final board = NoticeBoard();
      var told = 0;
      board.addListener(() => told++);
      expect(board.seen(('position', 1)), isFalse);
      board
        ..markSeen(('position', 1))
        ..markSeen(('position', 1));
      expect(board.seen(('position', 1)), isTrue);
      expect(board.seen(('position', 2)), isFalse);
      expect(told, 1);
    });
  });
}
