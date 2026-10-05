import 'package:flutter/material.dart';
import 'package:lunaway/i18n/strings.g.dart';

/// The map of spots. A placeholder until the map layer (LunaMap) lands.
class MapScreen extends StatelessWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return Scaffold(
      appBar: AppBar(title: Text(t.appTitle)),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: .min,
            children: [
              Icon(Icons.map_outlined, size: 64, color: Theme.of(context).colorScheme.primary),
              const SizedBox(height: 16),
              Text(t.map.placeholder, textAlign: .center),
            ],
          ),
        ),
      ),
    );
  }
}
