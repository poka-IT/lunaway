import 'package:lunaway/features/regions/domain/regions.dart';
import 'package:lunaway/i18n/strings.g.dart';
import 'package:lunaway/shared/labels.dart';

/// How the screens name a sync region.
extension RegionNames on Translations {
  // Read through a name, so the translation gate sees every key used.
  Translations get _t => this;

  /// [r]'s name in the reader's language (`Labels.areaName`); the places
  /// of France outside every commune are a region of their own.
  String regionName(RegionInfo r) => r.code == 'FR'
      ? _t.areas.franceRest
      : areaName(r.code, fallback: r.nameIn($meta.locale.languageCode));

  /// The regions as the picker lists them, by the names the reader sees.
  List<RegionGroup> regionGroups(RegionCatalog catalog) =>
      catalog.groups((r) => sortKey(regionName(r)));
}
