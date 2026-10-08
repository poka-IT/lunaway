import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunaway/features/map/domain/luna_map.dart';
import 'package:lunaway/features/map/presentation/map_search.dart';
import 'package:lunaway/features/map/presentation/nearby_list.dart';
import 'package:lunaway/features/map/presentation/quick_filters.dart';
import 'package:lunaway/shared/widgets/over_map.dart';
import 'package:lunaway/shared/widgets/spring_sheet.dart';
import 'package:pointer_interceptor/pointer_interceptor.dart';

import '../helpers/fakes.dart';
import '../helpers/pump.dart';

/// The keyboard on the map as the browser runs it. There the map and the
/// interceptor under each surface over it are HTML elements, and the
/// framework gives each a focus node of its own (`PlatformViewLink`); the
/// fakes below add those nodes, which a test on the Dart VM otherwise
/// lacks. A whole round of Tab reaches the search, the chips, the button
/// over the map, the map's buttons and the list, in that order, without a
/// stop where nothing shows, and Shift+Tab walks it back.
void main() {
  const add = 'Ajouter un lieu au centre de la carte';
  final native = PointerInterceptorPlatform.instance;

  setUp(() {
    MapShield.enabled = true;
    PointerInterceptorPlatform.instance = _WebInterceptor();
  });
  tearDown(() {
    MapShield.enabled = kIsWeb;
    PointerInterceptorPlatform.instance = native;
  });

  // Where a mouse is at hand the map has zoom buttons, as in a browser.
  final mouse = TargetPlatformVariant.only(TargetPlatform.macOS);
  const zoomAndPosition = ['Zoomer', 'Dézoomer', 'Afficher ma position'];
  // The list beside the map, with its header (the count and the order).
  final listPane = find.byWidgetPredicate((w) => w is NearbyList || w is NearbyCount);

  final layouts = <(String, Size, TestVariant<Object?>, List<String>, Finder)>[
    (
      'phone',
      phone,
      const DefaultTestVariant(),
      // The country's view before the user is located: the position's
      // button says it in words (LocateButton). Beside the zoom's buttons
      // the tests' wide letters leave it round.
      ['Voir autour de moi'],
      find.byType(SpringSheet),
    ),
    ('tablet', tablet, mouse, zoomAndPosition, listPane),
    ('desktop', desktop, mouse, zoomAndPosition, listPane),
  ];
  for (final (name, size, variant, controls, list) in layouts) {
    testWidgets(
      '$name: Tab goes from the search through the chips, the button over the map and '
      "the map's buttons to the list, and Shift+Tab back",
      variant: variant,
      (tester) async {
        await pumpLunaway(tester, size: size, map: _HtmlMap());
        if (size == tablet) {
          // The list is a panel there, closed until asked for.
          await tester.tap(find.textContaining('Liste'));
          await settleShort(tester);
        }

        // Tab until one stop past the map's buttons, at most 40 times.
        final forward = <FocusNode>[];
        for (var i = 0; i < 40; i++) {
          forward.addAll(await _press(tester, 1));
          final at = forward.map(_nameOf).toList().indexOf(add);
          if (at >= 0 && forward.length > at + 1 + controls.length) break;
        }
        final names = forward.map(_nameOf).toList();
        final at = names.indexOf(add);
        expect(at, isNonNegative, reason: 'the keyboard reaches the button over the map: $names');
        expect(
          _inside(forward.first, find.byType(MapSearch)),
          isTrue,
          reason: 'the first Tab goes to the search: $names',
        );
        expect(
          forward.sublist(1, at).every((n) => _inside(n, find.byType(QuickFilters))),
          isTrue,
          reason: 'the chips come between the search and the button: $names',
        );
        expect(
          names.sublist(at + 1, at + 1 + controls.length),
          controls,
          reason: "the map's buttons follow the button, the keyboard does not stay on it: $names",
        );
        final first = forward[at + 1 + controls.length];
        expect(_inside(first, list), isTrue, reason: 'the list comes last: $names');

        final back = await _press(tester, controls.length + 2, shift: true);
        expect(back.map(_nameOf), [
          ...controls.reversed,
          add,
          _nameOf(forward[at - 1]),
        ], reason: 'Shift+Tab walks the same way back');

        // On round the whole window, back to the search: no stop shows
        // nothing.
        final round = [...forward];
        for (var i = 0; i < 80; i++) {
          final node = (await _press(tester, 1)).single;
          if (node == forward.first) break;
          round.add(node);
        }
        final seen = round.map(_nameOf).toList();
        expect(seen, isNot(contains(null)), reason: 'every stop shows what holds the focus: $seen');
      },
    );
  }

  testWidgets('tablet: the closed list panel, off the screen, takes no stop', variant: mouse, (
    tester,
  ) async {
    await pumpLunaway(tester, size: tablet, map: _HtmlMap());
    final first = (await _press(tester, 1)).single;
    final round = [first];
    for (var i = 0; i < 80; i++) {
      final node = (await _press(tester, 1)).single;
      if (node == first) break;
      round.add(node);
    }
    expect(
      round.where((n) => _inside(n, find.byType(NearbyList))).map(_nameOf),
      isEmpty,
      reason: 'the rows of a closed panel are out of sight',
    );
    expect(round.map(_nameOf), contains(startsWith('Liste')), reason: 'its button is in the round');
  });
}

/// Presses Tab, or Shift+Tab, [times] and gives what holds the focus after
/// each press.
Future<List<FocusNode>> _press(WidgetTester tester, int times, {bool shift = false}) async {
  final out = <FocusNode>[];
  for (var i = 0; i < times; i++) {
    if (shift) await tester.sendKeyDownEvent(LogicalKeyboardKey.shift);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    if (shift) await tester.sendKeyUpEvent(LogicalKeyboardKey.shift);
    await tester.pump();
    out.add(FocusManager.instance.primaryFocus!);
  }
  return out;
}

/// What a user sees holding the focus: a field, the first text of a button
/// or a row, or an icon button's tooltip; null for a stop that shows
/// nothing.
String? _nameOf(FocusNode node) {
  final context = node.context;
  if (context == null) return null;
  if (context.findAncestorWidgetOfExactType<EditableText>() != null) return 'field';
  String? text;
  void visit(Element e) {
    if (text != null) return;
    if (e.widget case Text(:final data?)) {
      text = data;
      return;
    }
    e.visitChildren(visit);
  }

  (context as Element).visitChildren(visit);
  return text ?? context.findAncestorWidgetOfExactType<Tooltip>()?.message;
}

/// Whether [node] lies inside what [finder] finds.
bool _inside(FocusNode node, Finder finder) {
  final within = finder.evaluate().toSet();
  var found = false;
  node.context?.visitAncestorElements((e) {
    found = within.contains(e);
    return !found;
  });
  return found;
}

/// The interceptor of `pointer_interceptor_web`: an HTML element beside the
/// child, whose node the framework puts in the tab order.
final class _WebInterceptor extends PointerInterceptorPlatform {
  @override
  Widget buildWidget({required Widget child, bool debug = false, Key? key}) => Stack(
    key: key,
    alignment: Alignment.center,
    children: [
      const Positioned.fill(child: Focus(child: SizedBox.expand())),
      child,
    ],
  );
}

/// The map as an HTML element: a node of the tab order around it.
final class _HtmlMap extends FakeMap {
  @override
  Widget build(BuildContext context, LunaMapProps props) =>
      Focus(child: super.build(context, props));
}
