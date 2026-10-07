import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

/// The pointer the sweep hovers with, its own so that it never shares an id
/// with a touch the test made before. A test mouse is always device 1.
const _pointer = 7001;
const _mouseDevice = 1;

/// Cursors that tell a drag handle: the axis it moves along, or a hand
/// that grabs.
final dragCursors = <MouseCursor>{
  SystemMouseCursors.resizeUpDown,
  SystemMouseCursors.resizeRow,
  SystemMouseCursors.resizeLeftRight,
  SystemMouseCursors.resizeColumn,
  SystemMouseCursors.grab,
  SystemMouseCursors.grabbing,
  SystemMouseCursors.move,
};

/// What one sweep saw: how many controls were hovered, and those whose
/// cursor was wrong.
final class CursorSweep {
  int checked = 0;
  final List<String> wrong = [];

  /// Tappables, text fields and disabled buttons hovered, by kind.
  final Map<String, int> byKind = {};

  @override
  String toString() => 'checked $checked $byKind, wrong ${wrong.length}:\n${wrong.join('\n')}';
}

/// Checks that the framework records where each widget was made: without
/// it [debugIsWidgetLocalCreation] says no to every gesture detector, and
/// the sweep would pass over them all.
void _creationTracked() {
  assert(
    WidgetInspectorService.instance.isWidgetCreationTracked(),
    'the sweep needs --track-widget-creation, on by default in flutter test',
  );
}

/// The elements of the test's fake map: it stands for the platform view,
/// whose cursor the browser draws, so its pins are not the app's controls.
Set<Element> _fakeMap() => {
  for (final root in find.byKey(const ValueKey('fake-map')).evaluate()) ...[
    root,
    ...collectAllElementsFrom(root, skipOffstage: false),
  ],
};

/// What a control must show under the mouse, or null when the sweep does
/// not judge it.
({String kind, Set<MouseCursor> accepted})? _expectation(Widget widget) {
  final click = <MouseCursor>{SystemMouseCursors.click};
  switch (widget) {
    case GestureDetector():
      // Those the framework builds inside its own controls (a switch, a
      // drawer's edge) come with their cursor; the app's own do not.
      if (!debugIsWidgetLocalCreation(widget)) return null;
      final taps =
          widget.onTap != null ||
          widget.onTapDown != null ||
          widget.onTapUp != null ||
          widget.onLongPress != null ||
          widget.onDoubleTap != null ||
          widget.onSecondaryTap != null;
      if (taps) return (kind: 'gesture tap', accepted: click);
      final drags =
          widget.onVerticalDragStart != null ||
          widget.onVerticalDragUpdate != null ||
          widget.onHorizontalDragStart != null ||
          widget.onHorizontalDragUpdate != null ||
          widget.onPanStart != null ||
          widget.onPanUpdate != null;
      if (drags) return (kind: 'drag handle', accepted: dragCursors);
      return null;
    case ReorderableDragStartListener(:final enabled):
      if (!enabled || !debugIsWidgetLocalCreation(widget)) return null;
      return (kind: 'drag handle', accepted: dragCursors);
    case InkResponse():
      final taps =
          widget.onTap != null ||
          widget.onTapDown != null ||
          widget.onTapUp != null ||
          widget.onLongPress != null ||
          widget.onDoubleTap != null ||
          widget.onSecondaryTap != null;
      return taps ? (kind: 'ink tap', accepted: click) : null;
    // A dropdown draws its own gesture detector, which the sweep skips as
    // the framework's: it is judged as a whole.
    case DropdownButton(:final onChanged, :final items) when onChanged != null && items != null:
      return (kind: 'dropdown', accepted: click);
    case TextField():
      final enabled = widget.enabled ?? widget.decoration?.enabled ?? true;
      return enabled
          ? (kind: 'text field', accepted: {SystemMouseCursors.text})
          : (kind: 'disabled field', accepted: {SystemMouseCursors.basic});
    case ButtonStyleButton(:final enabled) when !enabled:
      return (kind: 'disabled button', accepted: {SystemMouseCursors.basic});
    default:
      return null;
  }
}

/// A short name for a failure message: the widget, its first text, and
/// the widgets that made it.
String _describe(Element element) {
  String? text;
  void visit(Element e) {
    if (text != null) return;
    final w = e.widget;
    if (w is RichText) {
      text = w.text.toPlainText();
      return;
    }
    if (w is Tooltip) text = w.message;
    e.visitChildren(visit);
  }

  visit(element);
  // An icon button has no text: its tooltip, above the ink, names it.
  var depth = 0;
  element.visitAncestorElements((ancestor) {
    final w = ancestor.widget;
    if (text == null && w is Tooltip) text = w.message;
    return text == null && ++depth < 12;
  });
  final chain = element.debugGetCreatorChain(6);
  return '${element.widget.toStringShort()} "${text ?? ''}" ($chain)';
}

/// The centre of [box] on screen, when a click there reaches it: a control
/// covered by another, scrolled out of view or under a barrier is left
/// out, since the mouse cannot reach it either.
Offset? _reachableCentre(WidgetTester tester, RenderBox box) {
  if (!box.attached || !box.hasSize || box.size.isEmpty) return null;
  final centre = box.localToGlobal(box.size.center(Offset.zero));
  final hit = tester.hitTestOnBinding(centre);
  return hit.path.any((entry) => entry.target == box) ? centre : null;
}

/// Whether a text field lies under [at]: its own cursor wins over the
/// tappable around it, and the field is checked on its own.
bool _overTextField(WidgetTester tester, Offset at) =>
    tester.hitTestOnBinding(at).path.any((entry) => entry.target is RenderEditable);

/// Hovers a mouse over every control on screen and checks the cursor it
/// shows: the pointing hand over what reacts to a tap (a gesture detector
/// of the app, an ink response, a link in a text), the text cursor over an
/// enabled text field, the basic arrow over a disabled button or field, a
/// resize or grab cursor over a drag handle.
Future<CursorSweep> sweepCursors(WidgetTester tester) async {
  _creationTracked();
  final fakeMap = _fakeMap();
  final sweep = CursorSweep();
  final targets = <({String kind, Set<MouseCursor> accepted, Offset at, String name})>[];
  for (final element in collectAllElementsFrom(tester.binding.rootElement!, skipOffstage: true)) {
    if (fakeMap.contains(element)) continue;
    final expectation = _expectation(element.widget);
    final box = element.renderObject;
    if (expectation != null && box is RenderBox) {
      final at = _reachableCentre(tester, box);
      if (at == null) continue;
      if (expectation.kind != 'text field' &&
          expectation.kind != 'disabled field' &&
          _overTextField(tester, at)) {
        continue;
      }
      targets.add((
        kind: expectation.kind,
        accepted: expectation.accepted,
        at: at,
        name: _describe(element),
      ));
    }
    // A link inside a text: a span with a recognizer.
    if (element.widget case RichText(:final text)
        when box is RenderParagraph && box.attached && box.hasSize) {
      var offset = 0;
      text.visitChildren((span) {
        final length = switch (span) {
          TextSpan(:final text) => text?.length ?? 0,
          _ => 1,
        };
        if (span is TextSpan && span.recognizer != null && length > 0) {
          final boxes = box.getBoxesForSelection(
            TextSelection(baseOffset: offset, extentOffset: offset + length),
          );
          if (boxes.isNotEmpty) {
            final at = box.localToGlobal(boxes.first.toRect().center);
            if (tester.hitTestOnBinding(at).path.any((e) => e.target == box)) {
              targets.add((
                kind: 'text link',
                accepted: {SystemMouseCursors.click},
                at: at,
                name: 'link "${span.text}" (${element.debugGetCreatorChain(4)})',
              ));
            }
          }
        }
        offset += length;
        return true;
      });
    }
  }

  final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse, pointer: _pointer);
  await gesture.addPointer(location: Offset.zero);
  for (final target in targets) {
    await gesture.moveTo(target.at);
    final cursor = RendererBinding.instance.mouseTracker.debugDeviceActiveCursor(_mouseDevice);
    sweep
      ..checked += 1
      ..byKind.update(target.kind, (n) => n + 1, ifAbsent: () => 1);
    if (!target.accepted.contains(cursor)) {
      sweep.wrong.add(
        '${target.kind}: ${target.name} at ${target.at} shows $cursor, '
        'expected ${target.accepted.join(' or ')}',
      );
    }
  }
  await gesture.removePointer();
  // Hovering shows tooltips and ink highlights; their timers end here.
  await tester.pump(const Duration(seconds: 2));
  return sweep;
}

/// Sweeps the screen and fails on any wrong cursor, after checking that
/// the sweep reached at least [atLeast] controls (a sweep that finds
/// nothing would pass on nothing).
Future<CursorSweep> expectCursors(WidgetTester tester, {required int atLeast}) async {
  final sweep = await sweepCursors(tester);
  expect(sweep.wrong, isEmpty, reason: sweep.toString());
  expect(sweep.checked, greaterThanOrEqualTo(atLeast), reason: sweep.toString());
  return sweep;
}
