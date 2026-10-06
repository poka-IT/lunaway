import 'package:flutter/widgets.dart';
import 'package:pointer_interceptor/pointer_interceptor.dart';

/// Wraps a widget drawn over the map. On the web the map is an HTML element
/// that would otherwise receive the clicks meant for the widget; elsewhere
/// this is a no-op.
class OverMap extends StatelessWidget {
  const new({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) => PointerInterceptor(child: child);
}
