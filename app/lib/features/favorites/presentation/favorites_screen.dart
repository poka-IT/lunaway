import 'package:flutter/material.dart';
import 'package:lunaway/i18n/strings.g.dart';

/// Saved spots, grouped in lists. Empty until favorites are stored locally.
class FavoritesScreen extends StatelessWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return Scaffold(
      appBar: AppBar(title: Text(t.nav.favorites)),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(t.favorites.empty, textAlign: .center),
        ),
      ),
    );
  }
}
