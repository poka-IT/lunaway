import 'package:flutter/material.dart';
import 'package:lunaway/shared/theme/tokens.dart';

/// Opens a modal sheet from the bottom with the app's own handle on top.
/// Material's handle (`showDragHandle`) shows the arrow under the mouse,
/// out of the theme's reach, and a click on it does nothing; this one shows
/// the pointing hand and a click closes the sheet, as a screen reader's tap
/// on Material's does. The sheet drags by any part, the handle included.
///
/// [handle] false for a sheet whose content draws its own top.
Future<T?> showSheet<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  bool useRootNavigator = false,
  bool useSafeArea = false,
  bool isScrollControlled = false,
  bool handle = true,
}) => showModalBottomSheet<T>(
  context: context,
  useRootNavigator: useRootNavigator,
  useSafeArea: useSafeArea,
  isScrollControlled: isScrollControlled,
  showDragHandle: false,
  builder: handle
      ? (context) => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SheetHandle(),
            Flexible(child: builder(context)),
          ],
        )
      : builder,
);

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
