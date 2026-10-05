import 'package:flutter/material.dart';
import 'package:lunaway/i18n/strings.g.dart';

/// The profile tab: language for now, the account and its recovery later.
class ProfileScreen extends StatelessWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final current = TranslationProvider.of(context).locale;
    return Scaffold(
      appBar: AppBar(title: Text(t.nav.profile)),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text(t.profile.language, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          SegmentedButton<AppLocale>(
            segments: [
              ButtonSegment(value: AppLocale.fr, label: Text(t.locale.fr)),
              ButtonSegment(value: AppLocale.en, label: Text(t.locale.en)),
            ],
            selected: {current},
            onSelectionChanged: (selection) => LocaleSettings.setLocale(selection.first),
          ),
          const SizedBox(height: 32),
          Text(t.profile.noAccountNeeded),
        ],
      ),
    );
  }
}
