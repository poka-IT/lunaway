import 'package:flutter/material.dart';
import 'package:lunaway/shared/theme/tokens.dart';

/// Opens a modal sheet from the bottom with the app's own handle on top.
/// Material's handle (`showDragHandle`) shows the arrow under the mouse,
/// out of the theme's reach, and a click on it does nothing; this one shows
/// the pointing hand and a click closes the sheet, as a screen reader's tap
/// on Material's does. The sheet drags by any part, the handle included.
///
/// [handle] false for a sheet whose content draws its own top.
///
/// [startInset] is the room the sheet leaves on the left of the window, a
/// panel it must not cover (the guidance's maneuver, the phone on its
/// side), read again whenever the window changes: the sheet stands in what
/// remains, centred, as wide as Material's at most.
Future<T?> showSheet<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  bool useRootNavigator = false,
  bool useSafeArea = false,
  bool isScrollControlled = false,
  bool handle = true,
  double Function(BuildContext context)? startInset,
}) {
  Widget withHandle(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      const SheetHandle(),
      Flexible(child: builder(context)),
    ],
  );
  final content = handle ? withHandle : builder;
  return showModalBottomSheet<T>(
    context: context,
    useRootNavigator: useRootNavigator,
    useSafeArea: useSafeArea,
    isScrollControlled: isScrollControlled,
    showDragHandle: false,
    // Beside a panel, the sheet draws its own surface where it stands.
    backgroundColor: startInset == null ? null : Colors.transparent,
    constraints: startInset == null ? null : const BoxConstraints(),
    builder: startInset == null
        ? content
        : (context) => _Beside(inset: startInset(context), child: content(context)),
  );
}

/// Material's widest bottom sheet.
const double _sheetMaxWidth = 640;

/// A sheet right of [inset], centred in the room left, with the theme's
/// surface and shape.
class _Beside extends StatelessWidget {
  const new({required this.inset, required this.child});

  final double inset;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sheet = theme.bottomSheetTheme;
    final width = MediaQuery.sizeOf(context).width;
    final start = inset.clamp(0.0, width);
    final room = width - start;
    final wide = room < _sheetMaxWidth ? room : _sheetMaxWidth;
    final side = (room - wide) / 2;
    return Stack(
      children: [
        // Beside the sheet, a tap closes it, as anywhere else outside.
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            excludeFromSemantics: true,
            onTap: () => Navigator.of(context).maybePop(),
          ),
        ),
        Padding(
          padding: EdgeInsets.only(left: start + side, right: side),
          child: Material(
            color: sheet.modalBackgroundColor ?? sheet.backgroundColor ?? theme.colorScheme.surface,
            surfaceTintColor: sheet.surfaceTintColor,
            elevation: sheet.modalElevation ?? sheet.elevation ?? 0,
            shape: sheet.shape,
            clipBehavior: Clip.antiAlias,
            // The inset stands clear of the system's left inset already.
            child: MediaQuery.removePadding(context: context, removeLeft: start > 0, child: child),
          ),
        ),
      ],
    );
  }
}

/// The handle at the top of a sheet: the size and colour of Material's, in
/// a 48 dp target that closes the sheet.
class SheetHandle extends StatelessWidget {
  const new({super.key});

  /// Material's own height for the band of its handle.
  static const double height = kMinInteractiveDimension;

  @override
  Widget build(BuildContext context) {
    void close() => Navigator.of(context).maybePop();
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: Semantics(
        container: true,
        button: true,
        label: MaterialLocalizations.of(context).modalBarrierDismissLabel,
        onTap: close,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          excludeFromSemantics: true,
          onTap: close,
          child: SizedBox(
            width: height,
            height: height,
            child: Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.outline,
                  borderRadius: BorderRadius.circular(LunaTokens.radiusPill),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
