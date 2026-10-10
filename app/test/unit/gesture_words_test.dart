import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The gestures of a finger, by language: "Touchez une étoile" read on a
/// computer, where the user clicks.
const _touch = {
  'fr': r'\btouche[zr]\b|\bappui long\b|\bappuyez\b',
  'en': r'\btaps?\b|\blong[- ]press|\btouch\b',
  'de': r'\btippen\b|\bgedrückt\b|\blange drücken\b',
  'es': r'\btoca\b|\btoque\b|\btócalo\b|\bmant[eé]n(lo)? pulsado\b|\btocar\b',
  'it': r'\btocca\b|\btoccando\b|\btieni premuto\b',
  'nl': r'\btik\b|\btikt\b|\bdruk lang\b|\blang indrukken\b',
};

/// The gestures of a mouse, by language.
const _click = {
  'fr': r'\bclic\b|\bcliquez\b',
  'en': r'\bclick\b|\bright-click\b',
  'de': r'\bklick|\bklicken\b|\brechtsklick\b',
  'es': r'\bclic\b',
  'it': r'\bclic\b',
  'nl': r'\bklik\b|\bklikken\b',
};

/// Texts read on one kind of device only: the notification of the guidance
/// exists on Android, where the user touches.
const _touchOnly = {'navigation.guidance.notificationWhy.body'};

Map<String, String> _flatten(Map<String, dynamic> node, [String prefix = '']) => {
  for (final MapEntry(:key, :value) in node.entries)
    ...switch (value) {
      final Map<String, dynamic> group => _flatten(group, '$prefix$key.'),
      final String text => {'$prefix$key': text},
      _ => const <String, String>{},
    },
};

void main() {
  for (final code in _touch.keys) {
    test('$code: a gesture is named only where the app knows the pointer', () {
      final texts = _flatten(
        jsonDecode(File('lib/i18n/$code.i18n.json').readAsStringSync()) as Map<String, dynamic>,
      );
      final touch = RegExp(_touch[code]!, caseSensitive: false);
      final click = RegExp(_click[code]!, caseSensitive: false);
      final wrong = [
        for (final MapEntry(:key, :value) in texts.entries)
          // A finger's word in a text with no twin for the mouse.
          if (touch.hasMatch(value) &&
              !texts.containsKey('${key}Click') &&
              !_touchOnly.contains(key))
            '$key: $value'
          // A mouse's word outside the mouse's twin.
          else if (click.hasMatch(value) && !key.endsWith('Click'))
            '$key: $value',
      ];
      expect(wrong, isEmpty);
    });
  }
}
