import 'package:collection/collection.dart';
import 'package:meta/meta.dart';

/// What the next trust level needs.
enum RequirementKind {
  accountAgeDays('ACCOUNT_AGE_DAYS'),
  confirmations('CONFIRMATIONS'),
  contributions('CONTRIBUTIONS'),
  activeDays('ACTIVE_DAYS'),
  noRemoval('NO_REMOVAL'),
  sponsor('SPONSOR'),
  nomination('NOMINATION'),
  administration('ADMINISTRATION');

  new(this.wire);

  final String wire;

  static RequirementKind? fromWire(Object? wire) =>
      values.where((k) => k.wire == wire).firstOrNull;
}

/// One requirement of the next level, with where the account stands for a
/// count.
@immutable
final class LevelRequirement {
  const new({required this.kind, this.current, this.needed});

  final RequirementKind kind;
  final int? current;
  final int? needed;

  Map<String, Object?> toJson() => {
    'kind': kind.wire,
    'current': current,
    'needed': needed,
  };

  static LevelRequirement? fromJson(Object? json) {
    if (json is! Map<String, dynamic>) return null;
    final kind = RequirementKind.fromWire(json['kind']);
    if (kind == null) return null;
    return LevelRequirement(
      kind: kind,
      current: (json['current'] as num?)?.toInt(),
      needed: (json['needed'] as num?)?.toInt(),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is LevelRequirement &&
      other.kind == kind &&
      other.current == current &&
      other.needed == needed;

  @override
  int get hashCode => Object.hash(kind, current, needed);
}

/// The level after the account's and what it still needs.
@immutable
final class NextLevel {
  const new({required this.level, this.missing = const [], this.instead});

  final int level;
  final List<LevelRequirement> missing;

  /// Another way to reach it (a sponsor for level 1).
  final LevelRequirement? instead;

  Map<String, Object?> toJson() => {
    'level': level,
    'missing': [for (final m in missing) m.toJson()],
    'instead': instead?.toJson(),
  };

  static NextLevel? fromJson(Object? json) {
    if (json is! Map<String, dynamic>) return null;
    final level = (json['level'] as num?)?.toInt();
    if (level == null) return null;
    return NextLevel(
      level: level,
      missing: [
        for (final m in (json['missing'] as List<dynamic>? ?? const []))
          ?LevelRequirement.fromJson(m),
      ],
      instead: LevelRequirement.fromJson(json['instead']),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is NextLevel &&
      other.level == level &&
      const ListEquality<LevelRequirement>().equals(other.missing, missing) &&
      other.instead == instead;

  @override
  int get hashCode => Object.hash(level, Object.hashAll(missing), instead);
}

/// What each level opens, as the API enforces it.
abstract final class TrustLevels {
  /// Ratings, confirmations, reports, lists, mutes.
  static const basic = 0;

  /// Written reviews, photos, and proposals to edit a place.
  static const review = 1;
  static const photo = 1;
  static const proposeEdit = 1;

  /// New places.
  static const addPlace = 2;

  /// Place edits applied without a moderator.
  static const editDirectly = 3;
}

/// The signed-in account, as the device remembers it between two reads of
/// `myAccount`.
@immutable
final class Account {
  const new({
    required this.id,
    required this.pseudonym,
    required this.trustLevel,
    required this.createdAt,
    this.nextLevel,
  });

  final String id;
  final String pseudonym;
  final int trustLevel;
  final NextLevel? nextLevel;
  final DateTime createdAt;

  Account copyWith({String? pseudonym}) => Account(
    id: id,
    pseudonym: pseudonym ?? this.pseudonym,
    trustLevel: trustLevel,
    createdAt: createdAt,
    nextLevel: nextLevel,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'pseudonym': pseudonym,
    'trustLevel': trustLevel,
    'nextLevel': nextLevel?.toJson(),
    'createdAt': createdAt.toUtc().toIso8601String(),
  };

  static Account? fromJson(Object? json) {
    if (json is! Map<String, dynamic>) return null;
    final id = json['id'];
    final pseudonym = json['pseudonym'];
    final level = json['trustLevel'];
    final created = DateTime.tryParse('${json['createdAt']}');
    if (id is! String ||
        pseudonym is! String ||
        level is! num ||
        created == null)
      return null;
    return Account(
      id: id,
      pseudonym: pseudonym,
      trustLevel: level.toInt(),
      nextLevel: NextLevel.fromJson(json['nextLevel']),
      createdAt: created.toUtc(),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is Account &&
      other.id == id &&
      other.pseudonym == pseudonym &&
      other.trustLevel == trustLevel &&
      other.nextLevel == nextLevel &&
      other.createdAt == createdAt;

  @override
  int get hashCode =>
      Object.hash(id, pseudonym, trustLevel, nextLevel, createdAt);
}

/// A public author: what `muteAuthor` takes, and its name.
@immutable
final class Author {
  const new({required this.id, required this.pseudonym});

  final String id;
  final String pseudonym;

  @override
  bool operator ==(Object other) =>
      other is Author && other.id == id && other.pseudonym == pseudonym;

  @override
  int get hashCode => Object.hash(id, pseudonym);
}

/// A device key attached to the account.
@immutable
final class Device {
  const new({
    required this.id,
    required this.createdAt,
    required this.lastUsedAt,
    required this.current,
  });

  final String id;
  final DateTime createdAt;
  final DateTime lastUsedAt;
  final bool current;
}

/// The bounds of a pseudonym, as the API checks them (it also refuses
/// insults, links and contact details).
abstract final class Pseudonym {
  static const minLength = 3;
  static const maxLength = 32;

  /// Spaces reduced as the server does; null when the length is wrong or no
  /// two letters are left.
  static String? clean(String raw) {
    final text = raw
        .trim()
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .join(' ');
    final length = text.runes.length;
    if (length < minLength || length > maxLength) return null;
    if (RegExp(r'\p{L}', unicode: true).allMatches(text).length < 2)
      return null;
    return text;
  }
}
