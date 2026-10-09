import 'dart:ui' show Tristate;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunaway/features/map/domain/luna_map.dart';
import 'package:lunaway/features/map/presentation/locate_button.dart';
import 'package:lunaway/features/map/presentation/map_credit.dart';
import 'package:lunaway/features/map/presentation/map_search.dart';
import 'package:lunaway/features/map/presentation/nearby_list.dart';
import 'package:lunaway/features/map/presentation/quick_filters.dart';
import 'package:lunaway/shared/widgets/focus_revealed_button.dart';
import 'package:lunaway/shared/widgets/over_map.dart';
import 'package:lunaway/shared/widgets/spring_sheet.dart';
import 'package:pointer_interceptor/pointer_interceptor.dart';

import '../helpers/fakes.dart';
import '../helpers/pump.dart';
import '../unit/contrast_test.dart' show contrast, graphic;

/// The keyboard on the map as the browser runs it. There the map and the
/// interceptor under each surface over it are HTML elements, and the
/// framework gives each a focus node of its own (`PlatformViewLink`); the
/// fakes below add those nodes, which a test on the Dart VM otherwise
/// lacks. A whole round of Tab reaches the search, the chips, the button
/// over the map, the map's buttons and the list, in that order, without a
/// stop where nothing shows, and Shift+Tab walks it back.
void main() {
  const add = 'Ajouter un lieu au centre de la carte';
  const credit = '© OpenStreetMap · Protomaps';
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
  const zoom = ['Zoomer', 'Dézoomer'];

  // The list pane: its header (the count and the sort) and its rows.
  final listPane = find.byWidgetPredicate((w) => w is NearbyCount || w is NearbyList);
  final layouts = <(String, Size, TestVariant<Object?>, List<String>, Finder)>[
    ('phone', phone, const DefaultTestVariant(), const [], find.byType(SpringSheet)),
    ('tablet', tablet, mouse, zoom, listPane),
    ('desktop', desktop, mouse, zoom, listPane),
  ];
  for (final (name, size, variant, zoomButtons, list) in layouts) {
    testWidgets(
      '$name: Tab goes from the search through the chips, the button over the map, '
      "the map's buttons and its credit to the list, and Shift+Tab back",
      variant: variant,
      (tester) async {
        await pumpLunaway(tester, size: size, map: _HtmlMap());
        if (size == tablet) {
          // The list is a panel there, closed until asked for.
          await tester.tap(find.textContaining('Liste'));
          await settleShort(tester);
        }
        // The position's button, in words or round as the room allows
        // (LocateButton): the same stop either way. The map's credit
        // follows them.
        final controls = [
          ...zoomButtons,
          if (find.text('Voir autour de moi').evaluate().isEmpty)
            'Afficher ma position'
          else
            'Voir autour de moi',
          credit,
        ];

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
          reason:
              "the map's buttons and its credit follow the button, the keyboard does not stay "
              'on it: $names',
        );
        final first = forward[at + 1 + controls.length];
        expect(_inside(first, list), isTrue, reason: 'the list comes last: $names');

        final back = await _press(tester, controls.length + 2, shift: true);
        expect(back.map(_nameOf), [
          ...controls.reversed,
          add,
          _nameOf(forward[at - 1]),
        ], reason: 'Shift+Tab walks the same way back');

        // One round of the whole window, back to the search: no stop shows
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

  testWidgets('phone, the sheet raised to the top: every stop of the round shows', (tester) async {
    final semantics = tester.ensureSemantics();
    await pumpLunaway(tester, map: _HtmlMap());
    // What the screen reader is given, the semantics tree itself.
    expect(find.semantics.byLabel(add), findsOne, reason: 'a screen reader finds it');
    await tester.drag(find.text('5 lieux ici'), const Offset(0, -900));
    await settleShort(tester);
    expect(find.semantics.byLabel(add), findsNothing, reason: 'nor under the sheet');
    expect(find.semantics.byLabel(RegExp('^Crédits de la carte')), findsNothing);
    semantics.dispose();
    expect(
      find.byType(TextField).hitTestable(),
      findsNothing,
      reason: 'the search under the sheet',
    );
    final first = (await _press(tester, 1)).single;
    final round = [first];
    for (var i = 0; i < 80; i++) {
      final node = (await _press(tester, 1)).single;
      if (node == first) break;
      round.add(node);
    }
    final names = round.map(_nameOf).toList();
    for (final (what, finder) in [
      ('the search', find.byType(MapSearch)),
      ('the chips', find.byType(QuickFilters)),
      ('the button over the map', find.byType(FocusRevealedButton)),
      ("the position's button", find.byType(LocateButton)),
      ("the map's credit", find.byType(MapCredit)),
    ]) {
      expect(round.where((n) => _inside(n, finder)), isEmpty, reason: '$what is covered: $names');
    }
    expect(names, isNot(contains(null)), reason: 'every stop shows what holds the focus: $names');
    expect(names, contains('Aire du Lac Bleu (démo)'), reason: 'the rows of the list: $names');

    // Lowered again, the map's stops come back.
    await tester.drag(find.text('5 lieux ici'), const Offset(0, 900));
    await settleShort(tester);
    final again = await _press(tester, 40);
    expect(again.map(_nameOf), containsAll([add, credit]));
  });

  testWidgets("the map's credit opens the OpenStreetMap rights from the keyboard", (tester) async {
    final semantics = tester.ensureSemantics();
    final app = await pumpLunaway(tester, map: _HtmlMap());
    final node = find.semantics.byLabel(RegExp('^Crédits de la carte'));
    expect(node, findsOne);
    expect(
      node.evaluate().single.flagsCollection.isFocused,
      Tristate.isFalse,
      reason: 'it can take the focus',
    );
    for (var i = 0; i < 40 && _nameOf(FocusManager.instance.primaryFocus!) != credit; i++) {
      await _press(tester, 1);
    }
    expect(_nameOf(FocusManager.instance.primaryFocus!), credit);
    // A screen reader in a browser follows the keyboard to a node that says
    // it can take the focus and holds it.
    final flags = node.evaluate().single.flagsCollection;
    expect(flags.isFocused, Tristate.isTrue);
    expect(flags.isButton, isTrue);
    semantics.dispose();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(app.external.opened, [osmCopyright]);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();
    expect(app.external.opened, [osmCopyright, osmCopyright]);
    // What Enter sends in a browser.
    Actions.invoke(FocusManager.instance.primaryFocus!.context!, const ButtonActivateIntent());
    await tester.pump();
    expect(app.external.opened, hasLength(3));
  });

  for (final brightness in Brightness.values) {
    testWidgets(
      "${brightness.name}: the keyboard's focus rings the map's buttons and its credit, at 3:1 "
      'against the surface at least',
      variant: mouse,
      (tester) async {
        await pumpLunaway(tester, size: desktop, map: _HtmlMap(), brightness: brightness);
        final scheme = Theme.of(tester.element(find.byType(MapSearch))).colorScheme;
        final ringed = <String>{};
        for (var i = 0; i < 40 && ringed.length < 4; i++) {
          final node = (await _press(tester, 1)).single;
          final name = _nameOf(node);
          if (name == null || !const [add, 'Zoomer', 'Dézoomer', credit].contains(name)) continue;
          final side = name == credit ? _creditSide(tester) : _buttonSide(node);
          expect(side.width, greaterThanOrEqualTo(2), reason: '$name holds a visible ring');
          expect(
            contrast(side.color, scheme.surface),
            greaterThanOrEqualTo(graphic),
            reason: "$name's ring against the surface",
          );
          ringed.add(name);
        }
        expect(ringed, {add, 'Zoomer', 'Dézoomer', credit});
        // Out of the keyboard's highlight mode (a touch), no ring.
        FocusManager.instance.highlightStrategy = FocusHighlightStrategy.alwaysTouch;
        addTearDown(
          () => FocusManager.instance.highlightStrategy = FocusHighlightStrategy.automatic,
        );
        await tester.pump();
        expect(_creditSide(tester).style, BorderStyle.none);
        final zoom = find.byTooltip('Zoomer');
        Focus.of(tester.element(find.descendant(of: zoom, matching: find.byType(Icon))))
            .requestFocus();
        await tester.pump();
        expect(_nameOf(FocusManager.instance.primaryFocus!), 'Zoomer');
        expect(_buttonSide(FocusManager.instance.primaryFocus!).style, BorderStyle.none);
      },
    );
  }

  testWidgets(
    "a touch after the keyboard takes the ring away, as it takes Material's wash",
    variant: mouse,
    (tester) async {
      await pumpLunaway(tester, size: desktop, map: _HtmlMap());
      for (var i = 0; i < 40 && _nameOf(FocusManager.instance.primaryFocus!) != 'Zoomer'; i++) {
        await _press(tester, 1);
      }
      final node = FocusManager.instance.primaryFocus!;
      expect(_buttonSide(node).width, 3, reason: 'the keyboard rings it');
      FocusManager.instance.highlightStrategy = FocusHighlightStrategy.alwaysTouch;
      addTearDown(() => FocusManager.instance.highlightStrategy = FocusHighlightStrategy.automatic);
      await tester.pump();
      expect(FocusManager.instance.primaryFocus, node, reason: 'it keeps the focus');
      expect(_buttonSide(node).style, BorderStyle.none, reason: 'its ring goes');
    },
  );

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

/// The edge of the button that holds [node], as its Material draws it.
BorderSide _buttonSide(FocusNode node) =>
    switch (node.context!.findAncestorWidgetOfExactType<Material>()?.shape) {
      final OutlinedBorder shape => shape.side,
      _ => BorderSide.none,
    };

/// The edge of the map's credit label.
BorderSide _creditSide(WidgetTester tester) {
  final box = tester.widget<DecoratedBox>(
    find.descendant(of: find.byType(MapCredit), matching: find.byType(DecoratedBox)).first,
  );
  return ((box.decoration as ShapeDecoration).shape as OutlinedBorder).side;
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
