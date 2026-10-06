import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;
import 'package:logging/logging.dart';
import 'package:lunaway/core/geo/geo.dart';
import 'package:lunaway/core/providers.dart';
import 'package:lunaway/features/favorites/application/favorites_providers.dart';
import 'package:lunaway/features/map/application/map_state.dart';
import 'package:lunaway/features/offline/data/pack_download.dart';
import 'package:lunaway/features/offline/data/pack_files.dart';
import 'package:lunaway/features/offline/domain/packs.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'offline_providers.g.dart';

final _log = Logger('offline');

/// The files of the offline maps; an empty stand-in on the web and the
/// desktops.
// keepAlive: one folder for the run, its path resolved once.
@Riverpod(keepAlive: true)
PackFiles packFiles(Ref ref) => PackFiles.platformFiles();

/// Whether this platform keeps maps offline (Android and iOS).
@riverpod
bool offlineMapsSupported(Ref ref) => ref.watch(packFilesProvider).supported;

/// The outlines of the packs, from the app's assets.
// keepAlive: a constant of the run, read by the map at every move.
@Riverpod(keepAlive: true)
Future<PackOutlines> packOutlines(Ref ref) async =>
    PackOutlines.parse(await rootBundle.loadString('assets/map/offline/regions.json'));

/// The manifest's address on the tile host.
@riverpod
Uri packManifestUrl(Ref ref) =>
    Uri.parse('${ref.watch(appConfigProvider).basemapBase}/packs/manifest.json');

/// The manifest as read: online, or the copy of the last one read when the
/// network does not answer.
@immutable
final class PackCatalog {
  const new({required this.manifest, required this.url, this.fromCopy = false});

  final PackManifest manifest;

  /// What the packs' file names are relative to.
  final Uri url;

  /// A copy kept from an earlier read: the network did not answer now.
  final bool fromCopy;

  Uri urlOf(PackInfo pack) => url.resolve(pack.url);
}

/// The packs to download: the manifest online, its copy offline. Offline
/// without a copy, the error reaches the screen.
@Riverpod(retry: _noRetry)
Future<PackCatalog> packCatalog(Ref ref) async {
  final files = ref.watch(packFilesProvider);
  final url = ref.watch(packManifestUrlProvider);
  final client = ref.watch(httpClientProvider);
  final agent = ref.watch(userAgentProvider);
  try {
    final response = await client
        .get(url, headers: {if (!kIsWeb) 'user-agent': agent})
        .timeout(const Duration(seconds: 20));
    if (response.statusCode != 200) throw http.ClientException('HTTP ${response.statusCode}');
    final text = utf8.decode(response.bodyBytes);
    final manifest = PackManifest.parse(text);
    await files.writeManifestCopy(text);
    return PackCatalog(manifest: manifest, url: url);
  } on Object catch (e) {
    final copy = await files.readManifestCopy();
    if (copy == null) rethrow;
    _log.info('manifest: kept the copy ($e)');
    return PackCatalog(manifest: PackManifest.parse(copy), url: url, fromCopy: true);
  }
}

Duration? _noRetry(int _, Object _) => null;

/// Where a download stands.
enum TransferState { running, waiting, paused, verifying, failed }

/// A pack being downloaded, or paused, or that failed.
@immutable
final class PackTransfer {
  const new({
    required this.pack,
    required this.url,
    required this.state,
    this.received = 0,
    this.etag,
    this.failure,
  });

  static PackTransfer? fromJson(Object? json) {
    if (json is! Map<String, dynamic>) return null;
    final pack = PackInfo.fromJson(json['pack']);
    final url = Uri.tryParse('${json['url']}');
    if (pack == null || url == null || !url.isScheme('https') && !url.isScheme('http')) return null;
    return PackTransfer(
      pack: pack,
      url: url,
      // The user's pause and a failure stay as they were; a download the
      // end of the app cut (running, checking, or waiting its turn) goes
      // back in line, and resumes from where it stopped.
      state: switch (json['state']) {
        'failed' => TransferState.failed,
        'paused' => TransferState.paused,
        _ => TransferState.waiting,
      },
      received: (json['received'] as num?)?.toInt() ?? 0,
      etag: json['etag'] as String?,
      failure: PackDownloadFailure.values.where((f) => f.name == json['failure']).firstOrNull,
    );
  }

  Map<String, Object?> toJson() => {
    'pack': {
      'id': pack.id,
      'name': pack.names,
      'kind': pack.region ? 'region' : 'country',
      'country': pack.country,
      'bbox': [pack.bounds.west, pack.bounds.south, pack.bounds.east, pack.bounds.north],
      'url': pack.url,
      'size': pack.size,
      'sha256': pack.sha256,
      'build': pack.build,
      'max_zoom': pack.maxZoom,
    },
    'url': url.toString(),
    'state': state.name,
    'received': received,
    'etag': etag,
    'failure': failure?.name,
  };

  final PackInfo pack;
  final Uri url;
  final TransferState state;
  final int received;
  final String? etag;
  final PackDownloadFailure? failure;

  double get progress => pack.size == 0 ? 0 : (received / pack.size).clamp(0, 1);

  PackTransfer copyWith({
    TransferState? state,
    int? received,
    String? etag,
    PackDownloadFailure? failure,
  }) => PackTransfer(
    pack: pack,
    url: url,
    state: state ?? this.state,
    received: received ?? this.received,
    etag: etag ?? this.etag,
    failure: state == TransferState.failed ? failure ?? this.failure : null,
  );

  @override
  bool operator ==(Object other) =>
      other is PackTransfer &&
      other.pack.id == pack.id &&
      other.pack.build == pack.build &&
      other.state == state &&
      other.received == received &&
      other.failure == failure;

  @override
  int get hashCode => Object.hash(pack.id, pack.build, state, received, failure);
}

/// The offline maps of the device: what is installed, what downloads, and
/// where the files are.
@immutable
final class OfflineMaps {
  const new({
    this.directory,
    this.styleAssets,
    this.installed = const {},
    this.transfers = const {},
    this.usedBytes = 0,
  });

  /// The folder of the packs; null where none is kept.
  final String? directory;

  /// The folder of the offline styles' glyphs and sprites.
  final String? styleAssets;
  final Map<String, InstalledPack> installed;
  final Map<String, PackTransfer> transfers;

  /// Bytes of the files, as last measured on the disk.
  final int usedBytes;

  /// What the maps take now, the downloads under way included: read from
  /// the state, so it grows with a download without touching the disk.
  int get bytesNow =>
      installed.values.fold<int>(0, (n, p) => n + p.size) +
      transfers.values.fold<int>(0, (n, t) => n + t.received);

  OfflineMaps copyWith({
    Map<String, InstalledPack>? installed,
    Map<String, PackTransfer>? transfers,
    int? usedBytes,
  }) => OfflineMaps(
    directory: directory,
    styleAssets: styleAssets,
    installed: installed ?? this.installed,
    transfers: transfers ?? this.transfers,
    usedBytes: usedBytes ?? this.usedBytes,
  );

  @override
  bool operator ==(Object other) =>
      other is OfflineMaps &&
      other.directory == directory &&
      other.styleAssets == styleAssets &&
      mapEquals(other.installed, installed) &&
      mapEquals(other.transfers, transfers) &&
      other.usedBytes == usedBytes;

  @override
  int get hashCode =>
      Object.hash(directory, styleAssets, installed.length, transfers.length, usedBytes);
}

/// The packs on the device and their downloads, one at a time, in the
/// order asked. A download stops when the user pauses it, when the network
/// goes, when the app leaves the screen and at the end of the app; it
/// resumes from where it stopped (`Range`): when the user asks, when the
/// app comes back or starts again, and when the basemap's host answers
/// again after a failure for want of network. A whole file is checked
/// against the manifest's SHA-256 before it replaces anything.
// keepAlive: a download outlives the screen that started it.
@Riverpod(keepAlive: true)
class OfflinePacks extends _$OfflinePacks {
  PackDownloadToken? _token;
  String? _running;
  DateTime _lastReport = DateTime.fromMillisecondsSinceEpoch(0);

  /// The app is off the screen: the system would cut a download there, so
  /// none starts until it comes back.
  bool _background = false;

  /// The next try of the downloads stopped for want of network.
  Timer? _retry;

  /// The room a download leaves free on the device, beyond its pack.
  static const int spareBytes = 200 * 1024 * 1024;

  /// Bumped with the app when the vendored glyphs or sprites change, so a
  /// device copies them again.
  static const styleAssetsVersion = '1';

  @override
  Future<OfflineMaps> build() async {
    ref.onDispose(() {
      _token?.cancel();
      _retry?.cancel();
    });
    final files = ref.watch(packFilesProvider);
    if (!files.supported) return const OfflineMaps();
    final lifecycle = AppLifecycleListener(
      onPause: () => unawaited(_toBackground()),
      onResume: () {
        _background = false;
        unawaited(_pump());
      },
    );
    ref.onDispose(lifecycle.dispose);
    ref.listen(basemapReachabilityProvider, (previous, next) {
      if (next == true && previous != true) unawaited(_resumeNetworkFailures());
    });
    final dir = await files.directory();
    final styleAssets = await files.installStyleAssets(rootBundle, version: styleAssetsVersion);
    final installed = <String, InstalledPack>{};
    final transfers = <String, PackTransfer>{};
    final index = await files.readIndex();
    if (index != null) {
      try {
        final json = jsonDecode(index) as Map<String, dynamic>;
        for (final p in json['installed'] as List<dynamic>? ?? const []) {
          final pack = InstalledPack.fromJson(p);
          // A file gone (the user cleared the app's data in part) is gone.
          if (pack != null && await files.exists(pack.fileName)) installed[pack.id] = pack;
        }
        for (final t in json['transfers'] as List<dynamic>? ?? const []) {
          final transfer = PackTransfer.fromJson(t);
          if (transfer != null) transfers[transfer.pack.id] = transfer;
        }
      } on Object catch (e) {
        _log.warning('offline index unreadable, starting empty: $e');
      }
    }
    // What the end of the app cut goes on once the packs are read.
    unawaited(Future<void>.microtask(_pump));
    return OfflineMaps(
      directory: dir,
      styleAssets: styleAssets,
      installed: installed,
      transfers: transfers,
      usedBytes: await files.usedBytes(),
    );
  }

  /// The running download goes back in line, to resume when the app comes
  /// back to the screen; one still getting ready (reading the free room)
  /// stops before it asks anything.
  Future<void> _toBackground() async {
    _background = true;
    final id = _running;
    if (id == null || id.isEmpty) return;
    _token?.cancel();
    final current = await future;
    final t = current.transfers[id];
    if (t == null || t.state != TransferState.running) return;
    await _set(
      current.copyWith(
        transfers: {
          ...current.transfers,
          id: t.copyWith(state: TransferState.waiting),
        },
      ),
    );
  }

  /// The downloads stopped for want of network go on, unless the host is
  /// known not to answer; one that fails again tries a minute later.
  Future<void> _resumeNetworkFailures() async {
    if (!ref.mounted || ref.read(basemapReachabilityProvider) == false) return;
    final current = await future;
    final stopped = [
      for (final t in current.transfers.values)
        if (t.state == TransferState.failed && t.failure == PackDownloadFailure.network) t.pack.id,
    ];
    for (final id in stopped) {
      await resume(id);
    }
  }

  PackFiles get _files => ref.read(packFilesProvider);

  Future<void> _save(OfflineMaps value) => _files.writeIndex(
    jsonEncode({
      'installed': [for (final p in value.installed.values) p.toJson()],
      'transfers': [for (final t in value.transfers.values) t.toJson()],
    }),
  );

  Future<void> _set(OfflineMaps value, {bool save = true}) async {
    if (!ref.mounted) return;
    state = AsyncData(value);
    if (save) await _save(value);
  }

  /// Downloads [pack] (a new one, or the new build of an installed one) from
  /// [catalog]; it waits its turn behind a running one.
  Future<void> download(PackInfo pack, PackCatalog catalog) async {
    final current = await future;
    final transfer = PackTransfer(
      pack: pack,
      url: catalog.urlOf(pack),
      state: TransferState.waiting,
    );
    final old = current.transfers[pack.id];
    if (old != null && old.pack.build != pack.build) {
      // A part of an older build: never spliced with the new one.
      await _files.delete(old.pack.fileName);
    }
    await _set(current.copyWith(transfers: {...current.transfers, pack.id: transfer}));
    unawaited(_pump());
  }

  /// Pauses [id]; it resumes from where it stopped.
  Future<void> pause(String id) async {
    if (_running == id) _token?.cancel();
    final current = await future;
    final t = current.transfers[id];
    if (t == null || t.state == TransferState.verifying) return;
    await _set(
      current.copyWith(
        transfers: {
          ...current.transfers,
          id: t.copyWith(state: TransferState.paused),
        },
      ),
    );
  }

  /// Resumes [id] (paused, or failed for want of network).
  Future<void> resume(String id) async {
    final current = await future;
    final t = current.transfers[id];
    if (t == null) return;
    await _set(
      current.copyWith(
        transfers: {
          ...current.transfers,
          id: t.copyWith(state: TransferState.waiting),
        },
      ),
    );
    unawaited(_pump());
  }

  /// Stops [id] and drops what it had downloaded.
  Future<void> cancel(String id) async {
    if (_running == id) _token?.cancel();
    final current = await future;
    final t = current.transfers[id];
    if (t == null) return;
    await _files.delete(t.pack.fileName);
    final transfers = {...current.transfers}..remove(id);
    await _set(current.copyWith(transfers: transfers, usedBytes: await _files.usedBytes()));
  }

  /// Removes the installed pack [id].
  Future<void> delete(String id) async {
    final current = await future;
    final pack = current.installed[id];
    if (pack == null) return;
    final installed = {...current.installed}..remove(id);
    // The map stops reading the file before it goes.
    await _set(current.copyWith(installed: installed));
    await _files.delete(pack.fileName);
    await _set((await future).copyWith(usedBytes: await _files.usedBytes()));
  }

  /// Runs the waiting downloads one after the other, while the app is on
  /// the screen.
  Future<void> _pump() async {
    if (_running != null || _background || !ref.mounted) return;
    // Taken before the first await: two calls at once start one download.
    _running = '';
    PackTransfer? next;
    try {
      final current = await future;
      next = current.transfers.values.where((t) => t.state == TransferState.waiting).firstOrNull;
      if (next != null && !_background) {
        _running = next.pack.id;
        await _run(next);
      }
    } finally {
      _running = null;
    }
    if (next != null && ref.mounted && !_background) unawaited(_pump());
  }

  Future<void> _run(PackTransfer transfer) async {
    final id = transfer.pack.id;
    final token = _token = PackDownloadToken();
    Future<void> update(PackTransfer Function(PackTransfer) change, {bool save = true}) async {
      if (!ref.mounted) return;
      final current = await future;
      final t = current.transfers[id];
      if (t == null) return;
      await _set(current.copyWith(transfers: {...current.transfers, id: change(t)}), save: save);
    }

    // Room for the rest of the pack and some more: a pack never fills the
    // device, where the user's own data would then fail to save.
    final free = await _files.freeBytes();
    if (free != null && free < transfer.pack.size - transfer.received + spareBytes) {
      _log.info('${transfer.pack.id}: $free bytes free, not enough');
      await update(
        (t) => t.copyWith(state: TransferState.failed, failure: PackDownloadFailure.storage),
      );
      return;
    }
    // The app left the screen while this one got ready: it waits in line.
    if (_background || token.cancelled) return;
    await update((t) => t.copyWith(state: TransferState.running));
    final downloader = PackDownloader(
      client: ref.read(httpClientProvider),
      userAgent: kIsWeb ? null : ref.read(userAgentProvider),
    );
    try {
      final result = await downloader.download(
        transfer.url,
        size: transfer.pack.size,
        sink: _files.partSink(transfer.pack.fileName),
        token: token,
        etag: transfer.etag,
        onProgress: (received) {
          final now = DateTime.now();
          if (now.difference(_lastReport) < const Duration(milliseconds: 250)) return;
          _lastReport = now;
          unawaited(update((t) => t.copyWith(received: received), save: false));
        },
      );
      if (!result.complete) {
        await update(
          (t) => t.copyWith(
            // Back in line when the app left the screen; else the user's
            // pause.
            state: t.state == TransferState.waiting || _background
                ? TransferState.waiting
                : TransferState.paused,
            received: result.received,
            etag: result.etag,
          ),
        );
        return;
      }
      await update(
        (t) => t.copyWith(
          state: TransferState.verifying,
          received: result.received,
          etag: result.etag,
        ),
      );
      final digest = await _files.partSha256(transfer.pack.fileName);
      if (digest != transfer.pack.sha256) {
        await _files.delete(transfer.pack.fileName);
        throw const PackDownloadException(PackDownloadFailure.corrupt, 'sha256 differs');
      }
      await _files.install(transfer.pack.fileName);
      if (!ref.mounted) return;
      final current = await future;
      final previous = current.installed[id];
      final installed = {
        ...current.installed,
        id: InstalledPack.from(transfer.pack, DateTime.now().toUtc()),
      };
      final transfers = {...current.transfers}..remove(id);
      await _set(current.copyWith(installed: installed, transfers: transfers));
      if (previous != null && previous.fileName != transfer.pack.fileName) {
        await _files.delete(previous.fileName);
      }
      await _set((await future).copyWith(usedBytes: await _files.usedBytes()), save: false);
    } on PackDownloadException catch (e) {
      _log.info('${transfer.pack.id}: $e');
      if (e.failure == PackDownloadFailure.storage) {
        // The device is full: the part goes, so the rest of the device
        // works again; the download starts over once there is room.
        await _files.delete(transfer.pack.fileName);
        await update((t) => t.copyWith(received: 0));
      }
      await update((t) => t.copyWith(state: TransferState.failed, failure: e.failure));
      if (e.failure == PackDownloadFailure.network) {
        _retry?.cancel();
        _retry = Timer(const Duration(minutes: 1), () => unawaited(_resumeNetworkFailures()));
      }
    } on Object catch (e, st) {
      _log.warning('${transfer.pack.id}: download failed', e, st);
      await update(
        (t) => t.copyWith(state: TransferState.failed, failure: PackDownloadFailure.storage),
      );
    }
  }
}

/// Where an offline style finds its files: the packs' folder, and that of
/// the glyphs and sprites; null before they are read, or where no map is
/// kept offline. Equal from one progress of a download to the next, so the
/// map's style is not made again four times a second.
@riverpod
({String directory, String styleAssets})? offlineStyleFiles(Ref ref) {
  final maps = ref.watch(offlinePacksProvider).value;
  final directory = maps?.directory;
  final assets = maps?.styleAssets;
  if (directory == null || assets == null) return null;
  return (directory: directory, styleAssets: assets);
}

/// Whether the basemap's host answers: null until the first probe, false
/// when it does not (the device is offline, or the host is down: the map
/// then reads a downloaded pack where there is one). A small TileJSON read,
/// at launch, on each return to the foreground, every ten minutes online
/// and every minute offline, only while the app is in the foreground; and
/// when the map comes to rest or the guidance moves on with an answer older
/// than [staleAfter] (see [probeIfStale]).
// keepAlive: the map and its notice read it for the whole run.
@Riverpod(keepAlive: true)
class BasemapReachability extends _$BasemapReachability {
  Timer? _timer;
  AppLifecycleListener? _lifecycle;
  bool _paused = false;
  DateTime? _askedAt;
  bool _asking = false;

  /// How old an answer may be when the map is in use.
  static const staleAfter = Duration(seconds: 30);

  @override
  bool? build() {
    ref.onDispose(() {
      _timer?.cancel();
      _lifecycle?.dispose();
    });
    _lifecycle = AppLifecycleListener(
      onResume: () {
        _paused = false;
        unawaited(probe());
      },
      onPause: () {
        _paused = true;
        _timer?.cancel();
      },
    );
    _timer = Timer(const Duration(seconds: 2), () => unawaited(probe()));
    return null;
  }

  /// Takes [reachable] as the host's answer until the next probe: the
  /// screenshot tours show the offline map without cutting the network.
  @visibleForTesting
  void assume({required bool? reachable}) => state = reachable;

  /// Asks again when the last answer is older than [staleAfter]. The
  /// ten-minute rhythm alone left the map blank for that long when the
  /// network went in the middle of a trip, a downloaded pack beside it.
  Future<void> probeIfStale() async {
    final at = _askedAt;
    if (_asking) return;
    if (at != null && ref.read(clockProvider)().difference(at) < staleAfter) return;
    await probe();
  }

  /// Asks the host now, then again later.
  Future<void> probe() async {
    _timer?.cancel();
    _asking = true;
    _askedAt = ref.read(clockProvider)();
    final base = ref.read(appConfigProvider).basemapBase;
    var reachable = false;
    try {
      final response = await ref
          .read(httpClientProvider)
          .get(
            Uri.parse('$base/planet.json'),
            headers: {if (!kIsWeb) 'user-agent': ref.read(userAgentProvider)},
          )
          .timeout(const Duration(seconds: 8));
      reachable = response.statusCode == 200;
    } on Object catch (e) {
      _log.fine('basemap host not reached: $e');
    } finally {
      _asking = false;
    }
    if (!ref.mounted) return;
    state = reachable;
    // A probe that ends after the app left the screen asks nothing more
    // until it comes back.
    if (_paused) return;
    _timer = Timer(
      reachable ? const Duration(minutes: 10) : const Duration(minutes: 1),
      () => unawaited(probe()),
    );
  }
}

/// The pack the map draws while the basemap's host does not answer: the
/// installed one under the centre of the view (the smallest, a region
/// before its country), and the last one while the view leaves every pack;
/// null online.
// keepAlive: the style of the map follows it for the whole run.
@Riverpod(keepAlive: true)
class ActiveOfflinePack extends _$ActiveOfflinePack {
  @override
  InstalledPack? build() {
    final offline = ref.watch(basemapReachabilityProvider) == false;
    final installed = ref.watch(offlinePacksProvider).value?.installed ?? const {};
    if (!offline || installed.isEmpty) return null;
    final center = ref.watch(viewportProvider)?.center;
    final outlines = ref.watch(packOutlinesProvider).value ?? PackOutlines.empty;
    final here = center == null
        ? null
        : packAt(
            installed.values,
            center,
            outlines: outlines,
            id: (p) => p.id,
            bounds: (p) => p.bounds,
          );
    final previous = stateOrNull;
    if (here != null) return here;
    // Leaving every pack keeps the last one rather than a blank map.
    return previous != null && installed.containsKey(previous.id) ? installed[previous.id] : null;
  }
}

/// The places of the favourites, for the packs to suggest.
@riverpod
Future<List<LatLng>> favoritePositions(Ref ref) async {
  final repo = ref.watch(favoritesRepositoryProvider);
  final out = <LatLng>[];
  for (final list in await repo.watchLists().first) {
    out.addAll([for (final e in await repo.watchEntries(list.id).first) e.position]);
  }
  return out;
}
