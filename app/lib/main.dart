import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lunaway/app.dart';
import 'package:lunaway/i18n/strings.g.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await LocaleSettings.useDeviceLocale();
  runApp(ProviderScope(child: TranslationProvider(child: const LunawayApp())));
}
