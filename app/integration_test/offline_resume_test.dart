import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:lunaway/app.dart';
import 'package:lunaway/features/offline/application/offline_providers.dart';
import 'package:lunaway/main.dart' as app;

/// A real pack downloaded on a device, paused at about a third, resumed
/// from where it stopped (`Range`, `If-Range`), checked against the
/// manifest's SHA-256, then removed. Bretagne (163 MB) by default:
///
///     fvm flutter test integration_test/offline_resume_test.dart -d <device> \
///       --dart-define=LUNAWAY_BASEMAP_URL=https://<host>/tiles
const _packId = String.fromEnvironment('LUNAWAY_PACK', defaultValue: 'fr-bre');

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('a pack pauses, resumes where it stopped, and is checked', (tester) async {
    await app.main();
    await tester.pump(const Duration(seconds: 1));
    final container = ProviderScope.containerOf(tester.element(find.byType(LunawayApp)));
    Future<T> wait<T>(Future<T> work) async {
      var done = false;
      late T value;
      work.then((v) {
        value = v;
        done = true;
      }).ignore();
      while (!done) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      return value;
    }

    final catalog = await wait(container.read(packCatalogProvider.future));
    final pack = catalog.manifest.byId(_packId)!;
    final packs = container.read(offlinePacksProvider.notifier);
    if ((await wait(container.read(offlinePacksProvider.future))).installed.containsKey(_packId)) {
      await wait(packs.delete(_packId));
    }
    final started = DateTime.now();
    await wait(packs.download(pack, catalog));
    PackTransfer? transfer() => container.read(offlinePacksProvider).value?.transfers[_packId];
    while ((transfer()?.progress ?? 0) < 0.33) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await wait(packs.pause(_packId));
    await tester.pump(const Duration(seconds: 2));
    final paused = transfer()!;
    debugPrint(
      'PAUSED ${paused.state.name} at ${paused.received} of ${pack.size}, etag ${paused.etag}',
    );
    expect(paused.state, TransferState.paused);
    expect(paused.received, greaterThan(0));

    final resumedAt = DateTime.now();
    await wait(packs.resume(_packId));
    var lowest = pack.size;
    while (!(container.read(offlinePacksProvider).value?.installed.containsKey(_packId) ?? false)) {
      final t = transfer();
      if (t != null && t.state == TransferState.running && t.received > 0 && t.received < lowest) {
        lowest = t.received;
      }
      if (t?.state == TransferState.failed) fail('failed: ${t!.failure}');
      await tester.pump(const Duration(milliseconds: 100));
    }
    final done = DateTime.now();
    debugPrint(
      'RESUMED from ${paused.received}: the lowest count seen after the resume was $lowest; '
      'installed after ${done.difference(started).inSeconds} s '
      '(${done.difference(resumedAt).inSeconds} s after the resume)',
    );
    expect(lowest, greaterThanOrEqualTo(paused.received), reason: 'it did not start over');
    final installed = container.read(offlinePacksProvider).value!.installed[_packId]!;
    expect(installed.sha256, pack.sha256);
    expect(installed.size, pack.size);

    await wait(packs.delete(_packId));
    final left = await wait(container.read(offlinePacksProvider.future));
    debugPrint('PACKS LEFT ${left.installed.keys.toList()} ${left.usedBytes}');
    expect(left.installed.containsKey(_packId), isFalse);
  });
}
