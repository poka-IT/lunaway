import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:lunaway/core/geo/geo.dart';
import 'package:lunaway/features/poi/domain/poi.dart';
import 'package:meta/meta.dart';

/// What a point saved outside the places of the data is: its icon in the
/// lists and on the map, and how its card opens.
enum SavedPointKind {
  /// A postal address, a street or a named spot the search found.
  address('ADDRESS'),

  /// A town or a postcode the search found.
  town('TOWN'),

  /// A bare point of the map.
  point('POINT'),

  /// A shop or a service (a point of interest).
  poi('POI');

  new(this.wire);

  /// The value of `FavoritePointKind` in the API.
  final String wire;

  /// The kind the API names [wire]; an unknown one (an API newer than the
  /// app) reads as a bare point, which every card can show.
  static SavedPointKind fromWire(Object? wire) =>
      values.where((k) => k.wire == wire).firstOrNull ?? point;
}

/// A point saved in a favourite list: an address, a town, a bare point or a
/// shop, with the name the user gave it and a short note. It lives on the
/// device first and goes with the account's lists, private to it.
@immutable
final class SavedPoint {
  const new({
    required this.id,
    required this.kind,
    required this.name,
    required this.position,
    this.note,
    this.address,
    this.poiId,
    this.poiKind,
  });

  /// A point cut and folded as the server keeps it (names on one line,
  /// notes without stray spaces, no control characters), so the copy the
  /// account sends back compares equal to the one saved here and a sync
  /// never sees a change that is not one. An empty name takes [fallback].
  factory normalized({
    required String id,
    required SavedPointKind kind,
    required String name,
    required LatLng position,
    required String fallback,
    String? note,
    String? address,
    String? poiId,
    PoiKind? poiKind,
  }) {
    final poi = kind == SavedPointKind.poi && poiId != null && poiKind != null;
    return SavedPoint(
      id: id,
      kind: poi || kind != SavedPointKind.poi ? kind : SavedPointKind.point,
      name: foldLine(name, maxName) ?? foldLine(fallback, maxName) ?? fallback,
      position: position,
      note: foldNote(note),
      address: foldLine(address, maxAddress),
      poiId: poi ? poiId : null,
      poiKind: poi ? poiKind : null,
    );
  }

  /// The longest name, note and address the server takes, in characters.
  static const maxName = 120;
  static const maxNote = 280;
  static const maxAddress = 200;

  final String id;
  final SavedPointKind kind;
  final String name;
  final LatLng position;
  final String? note;

  /// Its postal address on one line, when it is known.
  final String? address;

  /// The point of interest it is, for a shop or a service.
  final String? poiId;
  final PoiKind? poiKind;

  /// The point with another name and note, folded the same way.
  SavedPoint renamed(String name, String? note) => SavedPoint(
    id: id,
    kind: kind,
    name: foldLine(name, maxName) ?? this.name,
    position: position,
    note: foldNote(note),
    address: address,
    poiId: poiId,
    poiKind: poiKind,
  );

  /// What the sync compares: every field a device or the account can
  /// change, the coordinates to the centimetre.
  String get fingerprint => jsonEncode([
    kind.wire,
    name,
    note,
    address,
    position.lat.toStringAsFixed(7),
    position.lon.toStringAsFixed(7),
    poiId,
    poiKind?.wire,
  ]);

  @override
  bool operator ==(Object other) =>
      other is SavedPoint && other.id == id && other.fingerprint == fingerprint;

  @override
  int get hashCode => Object.hash(id, fingerprint);
}

/// The id of the point saved at [position]: a bare point, an address or a
/// town. The same position gives the same id on every device, so an address
/// saved twice is one favourite, and the card of a point knows whether it
/// is saved without a lookup by name.
String savedPointIdAt(LatLng position) =>
    _uuidOf('at:${position.lat.toStringAsFixed(6)},${position.lon.toStringAsFixed(6)}');

/// The id of the shop or service [poiId] once saved.
String savedPoiPointId(String poiId) => _uuidOf('poi:$poiId');

/// A UUID (version 8, RFC 9562) from [key]: the API takes UUIDs, and a
/// digest keeps the key's content out of the id.
String _uuidOf(String key) {
  final b = sha256.convert(utf8.encode('lunaway-favorite:$key')).bytes.sublist(0, 16);
  b[6] = (b[6] & 0x0f) | 0x80;
  b[8] = (b[8] & 0x3f) | 0x80;
  final hex = [for (final x in b) x.toRadixString(16).padLeft(2, '0')].join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-'
      '${hex.substring(16, 20)}-${hex.substring(20)}';
}

/// Characters a name or a note never keeps: controls (but a note's line
/// breaks) and the marks that turn the direction of the text around.
final _unwanted = RegExp('[\u0000-\u0009\u000b-\u001f\u007f-\u009f\u202a-\u202e\u2066-\u2069]');

/// [text] on one line, its spaces folded, cut at [max] characters; null
/// when nothing is left.
String? foldLine(String? text, int max) {
  if (text == null) return null;
  final words = text.replaceAll(_unwanted, ' ').split(RegExp(r'\s+')).where((w) => w.isNotEmpty);
  final line = words.join(' ');
  if (line.isEmpty) return null;
  return _cut(line, max);
}

/// [text] as a note: its line breaks kept, its ends trimmed, cut at
/// [SavedPoint.maxNote] characters; null when nothing is left.
String? foldNote(String? text) {
  if (text == null) return null;
  final note = text
      .replaceAll('\r\n', '\n')
      .replaceAll('\r', '\n')
      .replaceAll(_unwanted, ' ')
      .trim();
  if (note.isEmpty) return null;
  return _cut(note, SavedPoint.maxNote);
}

/// [text] cut at [max] characters (Unicode scalar values, as the server
/// counts them), never inside a surrogate pair.
String _cut(String text, int max) {
  final runes = text.runes;
  if (runes.length <= max) return text;
  return String.fromCharCodes(runes.take(max)).trimRight();
}
