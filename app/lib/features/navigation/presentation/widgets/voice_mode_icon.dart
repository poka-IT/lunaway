import 'package:flutter/widgets.dart';
import 'package:lunaway/features/navigation/domain/route_settings.dart';
import 'package:lunaway/shared/theme/app_icons.dart';
import 'package:lunaway/shared/theme/phosphor_glyphs.dart';

/// The voice mode, as the guidance's voice button shows it: the speaker
/// with its waves (everything said), the speaker with an exclamation mark
/// where the waves were (the alerts only), the speaker struck through
/// (muted).
class VoiceModeIcon extends StatelessWidget {
  const new(this.mode, {this.size, super.key});

  final VoiceMode mode;

  /// The side of the square; the theme's icon size by default.
  final double? size;

  @override
  Widget build(BuildContext context) => switch (mode) {
    VoiceMode.full => Icon(AppIcons.voiceOn, size: size),
    VoiceMode.muted => Icon(AppIcons.voiceOff, size: size),
    VoiceMode.alerts => _AlertsOnly(size: size),
  };
}

/// Phosphor has no speaker with an exclamation mark: its speaker without
/// waves, and the mark drawn where Phosphor puts the cross of its muted
/// speaker, with the stroke of its regular weight.
class _AlertsOnly extends StatelessWidget {
  const new({this.size});

  final double? size;

  @override
  Widget build(BuildContext context) {
    final theme = IconTheme.of(context);
    final side = size ?? theme.size ?? 24;
    final color = theme.color ?? const Color(0xFF000000);
    return SizedBox.square(
      dimension: side,
      child: CustomPaint(
        foregroundPainter: _ExclamationPainter(color),
        child: Icon(PhosphorRegular.speakerNone, size: side, color: color),
      ),
    );
  }
}

/// The exclamation mark on Phosphor's grid of 256: a bar of its regular
/// stroke (16) and a dot, centred on x 216 like the cross of `speaker-x`,
/// and on the speaker's middle height.
class _ExclamationPainter extends CustomPainter {
  const new(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final unit = size.shortestSide / 256;
    final paint = Paint()
      ..color = color
      ..isAntiAlias = true;
    canvas
      ..drawLine(
        Offset(216 * unit, 84 * unit),
        Offset(216 * unit, 140 * unit),
        paint
          ..style = PaintingStyle.stroke
          ..strokeWidth = 16 * unit
          ..strokeCap = StrokeCap.round,
      )
      ..drawCircle(
        Offset(216 * unit, 172 * unit),
        12 * unit,
        Paint()
          ..color = color
          ..isAntiAlias = true,
      );
  }

  @override
  bool shouldRepaint(_ExclamationPainter old) => old.color != color;
}
