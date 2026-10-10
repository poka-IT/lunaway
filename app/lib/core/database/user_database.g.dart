// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'user_database.dart';

// ignore_for_file: type=lint
class Settings extends Table with TableInfo<Settings, SettingRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  Settings(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL PRIMARY KEY',
  );
  static const VerificationMeta _valueMeta = const VerificationMeta('value');
  late final GeneratedColumn<String> value = GeneratedColumn<String>(
    'value',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  @override
  List<GeneratedColumn> get $columns => [id, value];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'settings';
  @override
  VerificationContext validateIntegrity(
    Insertable<SettingRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('value')) {
      context.handle(
        _valueMeta,
        value.isAcceptableOrUnknown(data['value']!, _valueMeta),
      );
    } else if (isInserting) {
      context.missing(_valueMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  SettingRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SettingRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      value: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}value'],
      )!,
    );
  }

  @override
  Settings createAlias(String alias) {
    return Settings(attachedDatabase, alias);
  }

  @override
  bool get dontWriteConstraints => true;
}

class SettingRow extends DataClass implements Insertable<SettingRow> {
  final String id;
  final String value;
  const SettingRow({required this.id, required this.value});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['value'] = Variable<String>(value);
    return map;
  }

  SettingsCompanion toCompanion(bool nullToAbsent) {
    return SettingsCompanion(id: Value(id), value: Value(value));
  }

  factory SettingRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SettingRow(
      id: serializer.fromJson<String>(json['id']),
      value: serializer.fromJson<String>(json['value']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'value': serializer.toJson<String>(value),
    };
  }

  SettingRow copyWith({String? id, String? value}) =>
      SettingRow(id: id ?? this.id, value: value ?? this.value);
  SettingRow copyWithCompanion(SettingsCompanion data) {
    return SettingRow(
      id: data.id.present ? data.id.value : this.id,
      value: data.value.present ? data.value.value : this.value,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SettingRow(')
          ..write('id: $id, ')
          ..write('value: $value')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, value);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SettingRow && other.id == this.id && other.value == this.value);
}

class SettingsCompanion extends UpdateCompanion<SettingRow> {
  final Value<String> id;
  final Value<String> value;
  final Value<int> rowid;
  const SettingsCompanion({
    this.id = const Value.absent(),
    this.value = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SettingsCompanion.insert({
    required String id,
    required String value,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       value = Value(value);
  static Insertable<SettingRow> custom({
    Expression<String>? id,
    Expression<String>? value,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (value != null) 'value': value,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SettingsCompanion copyWith({
    Value<String>? id,
    Value<String>? value,
    Value<int>? rowid,
  }) {
    return SettingsCompanion(
      id: id ?? this.id,
      value: value ?? this.value,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (value.present) {
      map['value'] = Variable<String>(value.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SettingsCompanion(')
          ..write('id: $id, ')
          ..write('value: $value, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class FavoriteLists extends Table
    with TableInfo<FavoriteLists, FavoriteListRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  FavoriteLists(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    $customConstraints: 'NOT NULL PRIMARY KEY AUTOINCREMENT',
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    $customConstraints: '',
  );
  static const VerificationMeta _isDefaultMeta = const VerificationMeta(
    'isDefault',
  );
  late final GeneratedColumn<bool> isDefault = GeneratedColumn<bool>(
    'is_default',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    $customConstraints: 'NOT NULL DEFAULT FALSE',
    defaultValue: const CustomExpression('FALSE'),
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  late final GeneratedColumn<int> createdAt = GeneratedColumn<int>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  static const VerificationMeta _serverIdMeta = const VerificationMeta(
    'serverId',
  );
  late final GeneratedColumn<String> serverId = GeneratedColumn<String>(
    'server_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    $customConstraints: '',
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    name,
    isDefault,
    createdAt,
    serverId,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'favorite_lists';
  @override
  VerificationContext validateIntegrity(
    Insertable<FavoriteListRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    }
    if (data.containsKey('is_default')) {
      context.handle(
        _isDefaultMeta,
        isDefault.isAcceptableOrUnknown(data['is_default']!, _isDefaultMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('server_id')) {
      context.handle(
        _serverIdMeta,
        serverId.isAcceptableOrUnknown(data['server_id']!, _serverIdMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  FavoriteListRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return FavoriteListRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      ),
      isDefault: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_default'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}created_at'],
      )!,
      serverId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}server_id'],
      ),
    );
  }

  @override
  FavoriteLists createAlias(String alias) {
    return FavoriteLists(attachedDatabase, alias);
  }

  @override
  bool get dontWriteConstraints => true;
}

class FavoriteListRow extends DataClass implements Insertable<FavoriteListRow> {
  final int id;

  /// Null for the default list, whose name follows the app language.
  final String? name;
  final bool isDefault;
  final int createdAt;

  /// The account's copy of the list (its UUID) once the favourites are
  /// synced; null for a list the account has not seen yet. Added in version 2.
  final String? serverId;
  const FavoriteListRow({
    required this.id,
    this.name,
    required this.isDefault,
    required this.createdAt,
    this.serverId,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    if (!nullToAbsent || name != null) {
      map['name'] = Variable<String>(name);
    }
    map['is_default'] = Variable<bool>(isDefault);
    map['created_at'] = Variable<int>(createdAt);
    if (!nullToAbsent || serverId != null) {
      map['server_id'] = Variable<String>(serverId);
    }
    return map;
  }

  FavoriteListsCompanion toCompanion(bool nullToAbsent) {
    return FavoriteListsCompanion(
      id: Value(id),
      name: name == null && nullToAbsent ? const Value.absent() : Value(name),
      isDefault: Value(isDefault),
      createdAt: Value(createdAt),
      serverId: serverId == null && nullToAbsent
          ? const Value.absent()
          : Value(serverId),
    );
  }

  factory FavoriteListRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return FavoriteListRow(
      id: serializer.fromJson<int>(json['id']),
      name: serializer.fromJson<String?>(json['name']),
      isDefault: serializer.fromJson<bool>(json['is_default']),
      createdAt: serializer.fromJson<int>(json['created_at']),
      serverId: serializer.fromJson<String?>(json['server_id']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'name': serializer.toJson<String?>(name),
      'is_default': serializer.toJson<bool>(isDefault),
      'created_at': serializer.toJson<int>(createdAt),
      'server_id': serializer.toJson<String?>(serverId),
    };
  }

  FavoriteListRow copyWith({
    int? id,
    Value<String?> name = const Value.absent(),
    bool? isDefault,
    int? createdAt,
    Value<String?> serverId = const Value.absent(),
  }) => FavoriteListRow(
    id: id ?? this.id,
    name: name.present ? name.value : this.name,
    isDefault: isDefault ?? this.isDefault,
    createdAt: createdAt ?? this.createdAt,
    serverId: serverId.present ? serverId.value : this.serverId,
  );
  FavoriteListRow copyWithCompanion(FavoriteListsCompanion data) {
    return FavoriteListRow(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      isDefault: data.isDefault.present ? data.isDefault.value : this.isDefault,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      serverId: data.serverId.present ? data.serverId.value : this.serverId,
    );
  }

  @override
  String toString() {
    return (StringBuffer('FavoriteListRow(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('isDefault: $isDefault, ')
          ..write('createdAt: $createdAt, ')
          ..write('serverId: $serverId')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, name, isDefault, createdAt, serverId);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is FavoriteListRow &&
          other.id == this.id &&
          other.name == this.name &&
          other.isDefault == this.isDefault &&
          other.createdAt == this.createdAt &&
          other.serverId == this.serverId);
}

class FavoriteListsCompanion extends UpdateCompanion<FavoriteListRow> {
  final Value<int> id;
  final Value<String?> name;
  final Value<bool> isDefault;
  final Value<int> createdAt;
  final Value<String?> serverId;
  const FavoriteListsCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.isDefault = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.serverId = const Value.absent(),
  });
  FavoriteListsCompanion.insert({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.isDefault = const Value.absent(),
    required int createdAt,
    this.serverId = const Value.absent(),
  }) : createdAt = Value(createdAt);
  static Insertable<FavoriteListRow> custom({
    Expression<int>? id,
    Expression<String>? name,
    Expression<bool>? isDefault,
    Expression<int>? createdAt,
    Expression<String>? serverId,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (isDefault != null) 'is_default': isDefault,
      if (createdAt != null) 'created_at': createdAt,
      if (serverId != null) 'server_id': serverId,
    });
  }

  FavoriteListsCompanion copyWith({
    Value<int>? id,
    Value<String?>? name,
    Value<bool>? isDefault,
    Value<int>? createdAt,
    Value<String?>? serverId,
  }) {
    return FavoriteListsCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      isDefault: isDefault ?? this.isDefault,
      createdAt: createdAt ?? this.createdAt,
      serverId: serverId ?? this.serverId,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (isDefault.present) {
      map['is_default'] = Variable<bool>(isDefault.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<int>(createdAt.value);
    }
    if (serverId.present) {
      map['server_id'] = Variable<String>(serverId.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('FavoriteListsCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('isDefault: $isDefault, ')
          ..write('createdAt: $createdAt, ')
          ..write('serverId: $serverId')
          ..write(')'))
        .toString();
  }
}

class FavoriteItems extends Table
    with TableInfo<FavoriteItems, FavoriteItemRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  FavoriteItems(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _listIdMeta = const VerificationMeta('listId');
  late final GeneratedColumn<int> listId = GeneratedColumn<int>(
    'list_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    $customConstraints:
        'NOT NULL REFERENCES favorite_lists(id)ON DELETE CASCADE',
  );
  static const VerificationMeta _placeIdMeta = const VerificationMeta(
    'placeId',
  );
  late final GeneratedColumn<String> placeId = GeneratedColumn<String>(
    'place_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    $customConstraints: '',
  );
  static const VerificationMeta _kindMeta = const VerificationMeta('kind');
  late final GeneratedColumn<String> kind = GeneratedColumn<String>(
    'kind',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  static const VerificationMeta _overnightMeta = const VerificationMeta(
    'overnight',
  );
  late final GeneratedColumn<String> overnight = GeneratedColumn<String>(
    'overnight',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    $customConstraints: 'NOT NULL DEFAULT \'UNKNOWN\'',
    defaultValue: const CustomExpression('\'UNKNOWN\''),
  );
  static const VerificationMeta _cityMeta = const VerificationMeta('city');
  late final GeneratedColumn<String> city = GeneratedColumn<String>(
    'city',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    $customConstraints: '',
  );
  static const VerificationMeta _latMeta = const VerificationMeta('lat');
  late final GeneratedColumn<double> lat = GeneratedColumn<double>(
    'lat',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  static const VerificationMeta _lonMeta = const VerificationMeta('lon');
  late final GeneratedColumn<double> lon = GeneratedColumn<double>(
    'lon',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  static const VerificationMeta _addedAtMeta = const VerificationMeta(
    'addedAt',
  );
  late final GeneratedColumn<int> addedAt = GeneratedColumn<int>(
    'added_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  @override
  List<GeneratedColumn> get $columns => [
    listId,
    placeId,
    name,
    kind,
    overnight,
    city,
    lat,
    lon,
    addedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'favorite_items';
  @override
  VerificationContext validateIntegrity(
    Insertable<FavoriteItemRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('list_id')) {
      context.handle(
        _listIdMeta,
        listId.isAcceptableOrUnknown(data['list_id']!, _listIdMeta),
      );
    } else if (isInserting) {
      context.missing(_listIdMeta);
    }
    if (data.containsKey('place_id')) {
      context.handle(
        _placeIdMeta,
        placeId.isAcceptableOrUnknown(data['place_id']!, _placeIdMeta),
      );
    } else if (isInserting) {
      context.missing(_placeIdMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    }
    if (data.containsKey('kind')) {
      context.handle(
        _kindMeta,
        kind.isAcceptableOrUnknown(data['kind']!, _kindMeta),
      );
    } else if (isInserting) {
      context.missing(_kindMeta);
    }
    if (data.containsKey('overnight')) {
      context.handle(
        _overnightMeta,
        overnight.isAcceptableOrUnknown(data['overnight']!, _overnightMeta),
      );
    }
    if (data.containsKey('city')) {
      context.handle(
        _cityMeta,
        city.isAcceptableOrUnknown(data['city']!, _cityMeta),
      );
    }
    if (data.containsKey('lat')) {
      context.handle(
        _latMeta,
        lat.isAcceptableOrUnknown(data['lat']!, _latMeta),
      );
    } else if (isInserting) {
      context.missing(_latMeta);
    }
    if (data.containsKey('lon')) {
      context.handle(
        _lonMeta,
        lon.isAcceptableOrUnknown(data['lon']!, _lonMeta),
      );
    } else if (isInserting) {
      context.missing(_lonMeta);
    }
    if (data.containsKey('added_at')) {
      context.handle(
        _addedAtMeta,
        addedAt.isAcceptableOrUnknown(data['added_at']!, _addedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_addedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {listId, placeId};
  @override
  FavoriteItemRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return FavoriteItemRow(
      listId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}list_id'],
      )!,
      placeId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}place_id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      ),
      kind: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}kind'],
      )!,
      overnight: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}overnight'],
      )!,
      city: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}city'],
      ),
      lat: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}lat'],
      )!,
      lon: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}lon'],
      )!,
      addedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}added_at'],
      )!,
    );
  }

  @override
  FavoriteItems createAlias(String alias) {
    return FavoriteItems(attachedDatabase, alias);
  }

  @override
  List<String> get customConstraints => const [
    'PRIMARY KEY(list_id, place_id)',
  ];
  @override
  bool get dontWriteConstraints => true;
}

class FavoriteItemRow extends DataClass implements Insertable<FavoriteItemRow> {
  final int listId;
  final String placeId;
  final String? name;
  final String kind;
  final String overnight;
  final String? city;
  final double lat;
  final double lon;
  final int addedAt;
  const FavoriteItemRow({
    required this.listId,
    required this.placeId,
    this.name,
    required this.kind,
    required this.overnight,
    this.city,
    required this.lat,
    required this.lon,
    required this.addedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['list_id'] = Variable<int>(listId);
    map['place_id'] = Variable<String>(placeId);
    if (!nullToAbsent || name != null) {
      map['name'] = Variable<String>(name);
    }
    map['kind'] = Variable<String>(kind);
    map['overnight'] = Variable<String>(overnight);
    if (!nullToAbsent || city != null) {
      map['city'] = Variable<String>(city);
    }
    map['lat'] = Variable<double>(lat);
    map['lon'] = Variable<double>(lon);
    map['added_at'] = Variable<int>(addedAt);
    return map;
  }

  FavoriteItemsCompanion toCompanion(bool nullToAbsent) {
    return FavoriteItemsCompanion(
      listId: Value(listId),
      placeId: Value(placeId),
      name: name == null && nullToAbsent ? const Value.absent() : Value(name),
      kind: Value(kind),
      overnight: Value(overnight),
      city: city == null && nullToAbsent ? const Value.absent() : Value(city),
      lat: Value(lat),
      lon: Value(lon),
      addedAt: Value(addedAt),
    );
  }

  factory FavoriteItemRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return FavoriteItemRow(
      listId: serializer.fromJson<int>(json['list_id']),
      placeId: serializer.fromJson<String>(json['place_id']),
      name: serializer.fromJson<String?>(json['name']),
      kind: serializer.fromJson<String>(json['kind']),
      overnight: serializer.fromJson<String>(json['overnight']),
      city: serializer.fromJson<String?>(json['city']),
      lat: serializer.fromJson<double>(json['lat']),
      lon: serializer.fromJson<double>(json['lon']),
      addedAt: serializer.fromJson<int>(json['added_at']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'list_id': serializer.toJson<int>(listId),
      'place_id': serializer.toJson<String>(placeId),
      'name': serializer.toJson<String?>(name),
      'kind': serializer.toJson<String>(kind),
      'overnight': serializer.toJson<String>(overnight),
      'city': serializer.toJson<String?>(city),
      'lat': serializer.toJson<double>(lat),
      'lon': serializer.toJson<double>(lon),
      'added_at': serializer.toJson<int>(addedAt),
    };
  }

  FavoriteItemRow copyWith({
    int? listId,
    String? placeId,
    Value<String?> name = const Value.absent(),
    String? kind,
    String? overnight,
    Value<String?> city = const Value.absent(),
    double? lat,
    double? lon,
    int? addedAt,
  }) => FavoriteItemRow(
    listId: listId ?? this.listId,
    placeId: placeId ?? this.placeId,
    name: name.present ? name.value : this.name,
    kind: kind ?? this.kind,
    overnight: overnight ?? this.overnight,
    city: city.present ? city.value : this.city,
    lat: lat ?? this.lat,
    lon: lon ?? this.lon,
    addedAt: addedAt ?? this.addedAt,
  );
  FavoriteItemRow copyWithCompanion(FavoriteItemsCompanion data) {
    return FavoriteItemRow(
      listId: data.listId.present ? data.listId.value : this.listId,
      placeId: data.placeId.present ? data.placeId.value : this.placeId,
      name: data.name.present ? data.name.value : this.name,
      kind: data.kind.present ? data.kind.value : this.kind,
      overnight: data.overnight.present ? data.overnight.value : this.overnight,
      city: data.city.present ? data.city.value : this.city,
      lat: data.lat.present ? data.lat.value : this.lat,
      lon: data.lon.present ? data.lon.value : this.lon,
      addedAt: data.addedAt.present ? data.addedAt.value : this.addedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('FavoriteItemRow(')
          ..write('listId: $listId, ')
          ..write('placeId: $placeId, ')
          ..write('name: $name, ')
          ..write('kind: $kind, ')
          ..write('overnight: $overnight, ')
          ..write('city: $city, ')
          ..write('lat: $lat, ')
          ..write('lon: $lon, ')
          ..write('addedAt: $addedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    listId,
    placeId,
    name,
    kind,
    overnight,
    city,
    lat,
    lon,
    addedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is FavoriteItemRow &&
          other.listId == this.listId &&
          other.placeId == this.placeId &&
          other.name == this.name &&
          other.kind == this.kind &&
          other.overnight == this.overnight &&
          other.city == this.city &&
          other.lat == this.lat &&
          other.lon == this.lon &&
          other.addedAt == this.addedAt);
}

class FavoriteItemsCompanion extends UpdateCompanion<FavoriteItemRow> {
  final Value<int> listId;
  final Value<String> placeId;
  final Value<String?> name;
  final Value<String> kind;
  final Value<String> overnight;
  final Value<String?> city;
  final Value<double> lat;
  final Value<double> lon;
  final Value<int> addedAt;
  final Value<int> rowid;
  const FavoriteItemsCompanion({
    this.listId = const Value.absent(),
    this.placeId = const Value.absent(),
    this.name = const Value.absent(),
    this.kind = const Value.absent(),
    this.overnight = const Value.absent(),
    this.city = const Value.absent(),
    this.lat = const Value.absent(),
    this.lon = const Value.absent(),
    this.addedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  FavoriteItemsCompanion.insert({
    required int listId,
    required String placeId,
    this.name = const Value.absent(),
    required String kind,
    this.overnight = const Value.absent(),
    this.city = const Value.absent(),
    required double lat,
    required double lon,
    required int addedAt,
    this.rowid = const Value.absent(),
  }) : listId = Value(listId),
       placeId = Value(placeId),
       kind = Value(kind),
       lat = Value(lat),
       lon = Value(lon),
       addedAt = Value(addedAt);
  static Insertable<FavoriteItemRow> custom({
    Expression<int>? listId,
    Expression<String>? placeId,
    Expression<String>? name,
    Expression<String>? kind,
    Expression<String>? overnight,
    Expression<String>? city,
    Expression<double>? lat,
    Expression<double>? lon,
    Expression<int>? addedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (listId != null) 'list_id': listId,
      if (placeId != null) 'place_id': placeId,
      if (name != null) 'name': name,
      if (kind != null) 'kind': kind,
      if (overnight != null) 'overnight': overnight,
      if (city != null) 'city': city,
      if (lat != null) 'lat': lat,
      if (lon != null) 'lon': lon,
      if (addedAt != null) 'added_at': addedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  FavoriteItemsCompanion copyWith({
    Value<int>? listId,
    Value<String>? placeId,
    Value<String?>? name,
    Value<String>? kind,
    Value<String>? overnight,
    Value<String?>? city,
    Value<double>? lat,
    Value<double>? lon,
    Value<int>? addedAt,
    Value<int>? rowid,
  }) {
    return FavoriteItemsCompanion(
      listId: listId ?? this.listId,
      placeId: placeId ?? this.placeId,
      name: name ?? this.name,
      kind: kind ?? this.kind,
      overnight: overnight ?? this.overnight,
      city: city ?? this.city,
      lat: lat ?? this.lat,
      lon: lon ?? this.lon,
      addedAt: addedAt ?? this.addedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (listId.present) {
      map['list_id'] = Variable<int>(listId.value);
    }
    if (placeId.present) {
      map['place_id'] = Variable<String>(placeId.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (kind.present) {
      map['kind'] = Variable<String>(kind.value);
    }
    if (overnight.present) {
      map['overnight'] = Variable<String>(overnight.value);
    }
    if (city.present) {
      map['city'] = Variable<String>(city.value);
    }
    if (lat.present) {
      map['lat'] = Variable<double>(lat.value);
    }
    if (lon.present) {
      map['lon'] = Variable<double>(lon.value);
    }
    if (addedAt.present) {
      map['added_at'] = Variable<int>(addedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('FavoriteItemsCompanion(')
          ..write('listId: $listId, ')
          ..write('placeId: $placeId, ')
          ..write('name: $name, ')
          ..write('kind: $kind, ')
          ..write('overnight: $overnight, ')
          ..write('city: $city, ')
          ..write('lat: $lat, ')
          ..write('lon: $lon, ')
          ..write('addedAt: $addedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class FavoritePoints extends Table
    with TableInfo<FavoritePoints, FavoritePointRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  FavoritePoints(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _listIdMeta = const VerificationMeta('listId');
  late final GeneratedColumn<int> listId = GeneratedColumn<int>(
    'list_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    $customConstraints:
        'NOT NULL REFERENCES favorite_lists(id)ON DELETE CASCADE',
  );
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  static const VerificationMeta _kindMeta = const VerificationMeta('kind');
  late final GeneratedColumn<String> kind = GeneratedColumn<String>(
    'kind',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  static const VerificationMeta _noteMeta = const VerificationMeta('note');
  late final GeneratedColumn<String> note = GeneratedColumn<String>(
    'note',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    $customConstraints: '',
  );
  static const VerificationMeta _addressMeta = const VerificationMeta(
    'address',
  );
  late final GeneratedColumn<String> address = GeneratedColumn<String>(
    'address',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    $customConstraints: '',
  );
  static const VerificationMeta _latMeta = const VerificationMeta('lat');
  late final GeneratedColumn<double> lat = GeneratedColumn<double>(
    'lat',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  static const VerificationMeta _lonMeta = const VerificationMeta('lon');
  late final GeneratedColumn<double> lon = GeneratedColumn<double>(
    'lon',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  static const VerificationMeta _poiIdMeta = const VerificationMeta('poiId');
  late final GeneratedColumn<String> poiId = GeneratedColumn<String>(
    'poi_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    $customConstraints: '',
  );
  static const VerificationMeta _poiKindMeta = const VerificationMeta(
    'poiKind',
  );
  late final GeneratedColumn<String> poiKind = GeneratedColumn<String>(
    'poi_kind',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    $customConstraints: '',
  );
  static const VerificationMeta _addedAtMeta = const VerificationMeta(
    'addedAt',
  );
  late final GeneratedColumn<int> addedAt = GeneratedColumn<int>(
    'added_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  @override
  List<GeneratedColumn> get $columns => [
    listId,
    id,
    kind,
    name,
    note,
    address,
    lat,
    lon,
    poiId,
    poiKind,
    addedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'favorite_points';
  @override
  VerificationContext validateIntegrity(
    Insertable<FavoritePointRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('list_id')) {
      context.handle(
        _listIdMeta,
        listId.isAcceptableOrUnknown(data['list_id']!, _listIdMeta),
      );
    } else if (isInserting) {
      context.missing(_listIdMeta);
    }
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('kind')) {
      context.handle(
        _kindMeta,
        kind.isAcceptableOrUnknown(data['kind']!, _kindMeta),
      );
    } else if (isInserting) {
      context.missing(_kindMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('note')) {
      context.handle(
        _noteMeta,
        note.isAcceptableOrUnknown(data['note']!, _noteMeta),
      );
    }
    if (data.containsKey('address')) {
      context.handle(
        _addressMeta,
        address.isAcceptableOrUnknown(data['address']!, _addressMeta),
      );
    }
    if (data.containsKey('lat')) {
      context.handle(
        _latMeta,
        lat.isAcceptableOrUnknown(data['lat']!, _latMeta),
      );
    } else if (isInserting) {
      context.missing(_latMeta);
    }
    if (data.containsKey('lon')) {
      context.handle(
        _lonMeta,
        lon.isAcceptableOrUnknown(data['lon']!, _lonMeta),
      );
    } else if (isInserting) {
      context.missing(_lonMeta);
    }
    if (data.containsKey('poi_id')) {
      context.handle(
        _poiIdMeta,
        poiId.isAcceptableOrUnknown(data['poi_id']!, _poiIdMeta),
      );
    }
    if (data.containsKey('poi_kind')) {
      context.handle(
        _poiKindMeta,
        poiKind.isAcceptableOrUnknown(data['poi_kind']!, _poiKindMeta),
      );
    }
    if (data.containsKey('added_at')) {
      context.handle(
        _addedAtMeta,
        addedAt.isAcceptableOrUnknown(data['added_at']!, _addedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_addedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {listId, id};
  @override
  FavoritePointRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return FavoritePointRow(
      listId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}list_id'],
      )!,
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      kind: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}kind'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      note: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}note'],
      ),
      address: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}address'],
      ),
      lat: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}lat'],
      )!,
      lon: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}lon'],
      )!,
      poiId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}poi_id'],
      ),
      poiKind: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}poi_kind'],
      ),
      addedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}added_at'],
      )!,
    );
  }

  @override
  FavoritePoints createAlias(String alias) {
    return FavoritePoints(attachedDatabase, alias);
  }

  @override
  List<String> get customConstraints => const ['PRIMARY KEY(list_id, id)'];
  @override
  bool get dontWriteConstraints => true;
}

class FavoritePointRow extends DataClass
    implements Insertable<FavoritePointRow> {
  final int listId;
  final String id;

  /// `SavedPointKind.wire`.
  final String kind;
  final String name;
  final String? note;
  final String? address;
  final double lat;
  final double lon;

  /// The point of interest, for a shop or a service (`PoiKind.code`).
  final String? poiId;
  final String? poiKind;
  final int addedAt;
  const FavoritePointRow({
    required this.listId,
    required this.id,
    required this.kind,
    required this.name,
    this.note,
    this.address,
    required this.lat,
    required this.lon,
    this.poiId,
    this.poiKind,
    required this.addedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['list_id'] = Variable<int>(listId);
    map['id'] = Variable<String>(id);
    map['kind'] = Variable<String>(kind);
    map['name'] = Variable<String>(name);
    if (!nullToAbsent || note != null) {
      map['note'] = Variable<String>(note);
    }
    if (!nullToAbsent || address != null) {
      map['address'] = Variable<String>(address);
    }
    map['lat'] = Variable<double>(lat);
    map['lon'] = Variable<double>(lon);
    if (!nullToAbsent || poiId != null) {
      map['poi_id'] = Variable<String>(poiId);
    }
    if (!nullToAbsent || poiKind != null) {
      map['poi_kind'] = Variable<String>(poiKind);
    }
    map['added_at'] = Variable<int>(addedAt);
    return map;
  }

  FavoritePointsCompanion toCompanion(bool nullToAbsent) {
    return FavoritePointsCompanion(
      listId: Value(listId),
      id: Value(id),
      kind: Value(kind),
      name: Value(name),
      note: note == null && nullToAbsent ? const Value.absent() : Value(note),
      address: address == null && nullToAbsent
          ? const Value.absent()
          : Value(address),
      lat: Value(lat),
      lon: Value(lon),
      poiId: poiId == null && nullToAbsent
          ? const Value.absent()
          : Value(poiId),
      poiKind: poiKind == null && nullToAbsent
          ? const Value.absent()
          : Value(poiKind),
      addedAt: Value(addedAt),
    );
  }

  factory FavoritePointRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return FavoritePointRow(
      listId: serializer.fromJson<int>(json['list_id']),
      id: serializer.fromJson<String>(json['id']),
      kind: serializer.fromJson<String>(json['kind']),
      name: serializer.fromJson<String>(json['name']),
      note: serializer.fromJson<String?>(json['note']),
      address: serializer.fromJson<String?>(json['address']),
      lat: serializer.fromJson<double>(json['lat']),
      lon: serializer.fromJson<double>(json['lon']),
      poiId: serializer.fromJson<String?>(json['poi_id']),
      poiKind: serializer.fromJson<String?>(json['poi_kind']),
      addedAt: serializer.fromJson<int>(json['added_at']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'list_id': serializer.toJson<int>(listId),
      'id': serializer.toJson<String>(id),
      'kind': serializer.toJson<String>(kind),
      'name': serializer.toJson<String>(name),
      'note': serializer.toJson<String?>(note),
      'address': serializer.toJson<String?>(address),
      'lat': serializer.toJson<double>(lat),
      'lon': serializer.toJson<double>(lon),
      'poi_id': serializer.toJson<String?>(poiId),
      'poi_kind': serializer.toJson<String?>(poiKind),
      'added_at': serializer.toJson<int>(addedAt),
    };
  }

  FavoritePointRow copyWith({
    int? listId,
    String? id,
    String? kind,
    String? name,
    Value<String?> note = const Value.absent(),
    Value<String?> address = const Value.absent(),
    double? lat,
    double? lon,
    Value<String?> poiId = const Value.absent(),
    Value<String?> poiKind = const Value.absent(),
    int? addedAt,
  }) => FavoritePointRow(
    listId: listId ?? this.listId,
    id: id ?? this.id,
    kind: kind ?? this.kind,
    name: name ?? this.name,
    note: note.present ? note.value : this.note,
    address: address.present ? address.value : this.address,
    lat: lat ?? this.lat,
    lon: lon ?? this.lon,
    poiId: poiId.present ? poiId.value : this.poiId,
    poiKind: poiKind.present ? poiKind.value : this.poiKind,
    addedAt: addedAt ?? this.addedAt,
  );
  FavoritePointRow copyWithCompanion(FavoritePointsCompanion data) {
    return FavoritePointRow(
      listId: data.listId.present ? data.listId.value : this.listId,
      id: data.id.present ? data.id.value : this.id,
      kind: data.kind.present ? data.kind.value : this.kind,
      name: data.name.present ? data.name.value : this.name,
      note: data.note.present ? data.note.value : this.note,
      address: data.address.present ? data.address.value : this.address,
      lat: data.lat.present ? data.lat.value : this.lat,
      lon: data.lon.present ? data.lon.value : this.lon,
      poiId: data.poiId.present ? data.poiId.value : this.poiId,
      poiKind: data.poiKind.present ? data.poiKind.value : this.poiKind,
      addedAt: data.addedAt.present ? data.addedAt.value : this.addedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('FavoritePointRow(')
          ..write('listId: $listId, ')
          ..write('id: $id, ')
          ..write('kind: $kind, ')
          ..write('name: $name, ')
          ..write('note: $note, ')
          ..write('address: $address, ')
          ..write('lat: $lat, ')
          ..write('lon: $lon, ')
          ..write('poiId: $poiId, ')
          ..write('poiKind: $poiKind, ')
          ..write('addedAt: $addedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    listId,
    id,
    kind,
    name,
    note,
    address,
    lat,
    lon,
    poiId,
    poiKind,
    addedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is FavoritePointRow &&
          other.listId == this.listId &&
          other.id == this.id &&
          other.kind == this.kind &&
          other.name == this.name &&
          other.note == this.note &&
          other.address == this.address &&
          other.lat == this.lat &&
          other.lon == this.lon &&
          other.poiId == this.poiId &&
          other.poiKind == this.poiKind &&
          other.addedAt == this.addedAt);
}

class FavoritePointsCompanion extends UpdateCompanion<FavoritePointRow> {
  final Value<int> listId;
  final Value<String> id;
  final Value<String> kind;
  final Value<String> name;
  final Value<String?> note;
  final Value<String?> address;
  final Value<double> lat;
  final Value<double> lon;
  final Value<String?> poiId;
  final Value<String?> poiKind;
  final Value<int> addedAt;
  final Value<int> rowid;
  const FavoritePointsCompanion({
    this.listId = const Value.absent(),
    this.id = const Value.absent(),
    this.kind = const Value.absent(),
    this.name = const Value.absent(),
    this.note = const Value.absent(),
    this.address = const Value.absent(),
    this.lat = const Value.absent(),
    this.lon = const Value.absent(),
    this.poiId = const Value.absent(),
    this.poiKind = const Value.absent(),
    this.addedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  FavoritePointsCompanion.insert({
    required int listId,
    required String id,
    required String kind,
    required String name,
    this.note = const Value.absent(),
    this.address = const Value.absent(),
    required double lat,
    required double lon,
    this.poiId = const Value.absent(),
    this.poiKind = const Value.absent(),
    required int addedAt,
    this.rowid = const Value.absent(),
  }) : listId = Value(listId),
       id = Value(id),
       kind = Value(kind),
       name = Value(name),
       lat = Value(lat),
       lon = Value(lon),
       addedAt = Value(addedAt);
  static Insertable<FavoritePointRow> custom({
    Expression<int>? listId,
    Expression<String>? id,
    Expression<String>? kind,
    Expression<String>? name,
    Expression<String>? note,
    Expression<String>? address,
    Expression<double>? lat,
    Expression<double>? lon,
    Expression<String>? poiId,
    Expression<String>? poiKind,
    Expression<int>? addedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (listId != null) 'list_id': listId,
      if (id != null) 'id': id,
      if (kind != null) 'kind': kind,
      if (name != null) 'name': name,
      if (note != null) 'note': note,
      if (address != null) 'address': address,
      if (lat != null) 'lat': lat,
      if (lon != null) 'lon': lon,
      if (poiId != null) 'poi_id': poiId,
      if (poiKind != null) 'poi_kind': poiKind,
      if (addedAt != null) 'added_at': addedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  FavoritePointsCompanion copyWith({
    Value<int>? listId,
    Value<String>? id,
    Value<String>? kind,
    Value<String>? name,
    Value<String?>? note,
    Value<String?>? address,
    Value<double>? lat,
    Value<double>? lon,
    Value<String?>? poiId,
    Value<String?>? poiKind,
    Value<int>? addedAt,
    Value<int>? rowid,
  }) {
    return FavoritePointsCompanion(
      listId: listId ?? this.listId,
      id: id ?? this.id,
      kind: kind ?? this.kind,
      name: name ?? this.name,
      note: note ?? this.note,
      address: address ?? this.address,
      lat: lat ?? this.lat,
      lon: lon ?? this.lon,
      poiId: poiId ?? this.poiId,
      poiKind: poiKind ?? this.poiKind,
      addedAt: addedAt ?? this.addedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (listId.present) {
      map['list_id'] = Variable<int>(listId.value);
    }
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (kind.present) {
      map['kind'] = Variable<String>(kind.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (note.present) {
      map['note'] = Variable<String>(note.value);
    }
    if (address.present) {
      map['address'] = Variable<String>(address.value);
    }
    if (lat.present) {
      map['lat'] = Variable<double>(lat.value);
    }
    if (lon.present) {
      map['lon'] = Variable<double>(lon.value);
    }
    if (poiId.present) {
      map['poi_id'] = Variable<String>(poiId.value);
    }
    if (poiKind.present) {
      map['poi_kind'] = Variable<String>(poiKind.value);
    }
    if (addedAt.present) {
      map['added_at'] = Variable<int>(addedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('FavoritePointsCompanion(')
          ..write('listId: $listId, ')
          ..write('id: $id, ')
          ..write('kind: $kind, ')
          ..write('name: $name, ')
          ..write('note: $note, ')
          ..write('address: $address, ')
          ..write('lat: $lat, ')
          ..write('lon: $lon, ')
          ..write('poiId: $poiId, ')
          ..write('poiKind: $poiKind, ')
          ..write('addedAt: $addedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class Vehicles extends Table with TableInfo<Vehicles, VehicleRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  Vehicles(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    $customConstraints: 'NOT NULL PRIMARY KEY CHECK (id = 1)',
  );
  static const VerificationMeta _typeMeta = const VerificationMeta('type');
  late final GeneratedColumn<String> type = GeneratedColumn<String>(
    'type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  static const VerificationMeta _towingMeta = const VerificationMeta('towing');
  late final GeneratedColumn<String> towing = GeneratedColumn<String>(
    'towing',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    $customConstraints: 'NOT NULL DEFAULT \'none\'',
    defaultValue: const CustomExpression('\'none\''),
  );
  static const VerificationMeta _heightMMeta = const VerificationMeta(
    'heightM',
  );
  late final GeneratedColumn<double> heightM = GeneratedColumn<double>(
    'height_m',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
    $customConstraints: '',
  );
  static const VerificationMeta _widthMMeta = const VerificationMeta('widthM');
  late final GeneratedColumn<double> widthM = GeneratedColumn<double>(
    'width_m',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
    $customConstraints: '',
  );
  static const VerificationMeta _lengthMMeta = const VerificationMeta(
    'lengthM',
  );
  late final GeneratedColumn<double> lengthM = GeneratedColumn<double>(
    'length_m',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
    $customConstraints: '',
  );
  static const VerificationMeta _weightTMeta = const VerificationMeta(
    'weightT',
  );
  late final GeneratedColumn<double> weightT = GeneratedColumn<double>(
    'weight_t',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
    $customConstraints: '',
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  late final GeneratedColumn<int> updatedAt = GeneratedColumn<int>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  static const VerificationMeta _fuelMeta = const VerificationMeta('fuel');
  late final GeneratedColumn<String> fuel = GeneratedColumn<String>(
    'fuel',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    $customConstraints: '',
  );
  static const VerificationMeta _consumptionL100Meta = const VerificationMeta(
    'consumptionL100',
  );
  late final GeneratedColumn<double> consumptionL100 = GeneratedColumn<double>(
    'consumption_l100',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
    $customConstraints: '',
  );
  static const VerificationMeta _lpgHeatingMeta = const VerificationMeta(
    'lpgHeating',
  );
  late final GeneratedColumn<bool> lpgHeating = GeneratedColumn<bool>(
    'lpg_heating',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    $customConstraints: 'NOT NULL DEFAULT FALSE',
    defaultValue: const CustomExpression('FALSE'),
  );
  static const VerificationMeta _cruiseSpeedKphMeta = const VerificationMeta(
    'cruiseSpeedKph',
  );
  late final GeneratedColumn<int> cruiseSpeedKph = GeneratedColumn<int>(
    'cruise_speed_kph',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    $customConstraints: '',
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    type,
    towing,
    heightM,
    widthM,
    lengthM,
    weightT,
    updatedAt,
    fuel,
    consumptionL100,
    lpgHeating,
    cruiseSpeedKph,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'vehicles';
  @override
  VerificationContext validateIntegrity(
    Insertable<VehicleRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('type')) {
      context.handle(
        _typeMeta,
        type.isAcceptableOrUnknown(data['type']!, _typeMeta),
      );
    } else if (isInserting) {
      context.missing(_typeMeta);
    }
    if (data.containsKey('towing')) {
      context.handle(
        _towingMeta,
        towing.isAcceptableOrUnknown(data['towing']!, _towingMeta),
      );
    }
    if (data.containsKey('height_m')) {
      context.handle(
        _heightMMeta,
        heightM.isAcceptableOrUnknown(data['height_m']!, _heightMMeta),
      );
    }
    if (data.containsKey('width_m')) {
      context.handle(
        _widthMMeta,
        widthM.isAcceptableOrUnknown(data['width_m']!, _widthMMeta),
      );
    }
    if (data.containsKey('length_m')) {
      context.handle(
        _lengthMMeta,
        lengthM.isAcceptableOrUnknown(data['length_m']!, _lengthMMeta),
      );
    }
    if (data.containsKey('weight_t')) {
      context.handle(
        _weightTMeta,
        weightT.isAcceptableOrUnknown(data['weight_t']!, _weightTMeta),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    if (data.containsKey('fuel')) {
      context.handle(
        _fuelMeta,
        fuel.isAcceptableOrUnknown(data['fuel']!, _fuelMeta),
      );
    }
    if (data.containsKey('consumption_l100')) {
      context.handle(
        _consumptionL100Meta,
        consumptionL100.isAcceptableOrUnknown(
          data['consumption_l100']!,
          _consumptionL100Meta,
        ),
      );
    }
    if (data.containsKey('lpg_heating')) {
      context.handle(
        _lpgHeatingMeta,
        lpgHeating.isAcceptableOrUnknown(data['lpg_heating']!, _lpgHeatingMeta),
      );
    }
    if (data.containsKey('cruise_speed_kph')) {
      context.handle(
        _cruiseSpeedKphMeta,
        cruiseSpeedKph.isAcceptableOrUnknown(
          data['cruise_speed_kph']!,
          _cruiseSpeedKphMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  VehicleRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return VehicleRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      type: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}type'],
      )!,
      towing: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}towing'],
      )!,
      heightM: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}height_m'],
      ),
      widthM: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}width_m'],
      ),
      lengthM: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}length_m'],
      ),
      weightT: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}weight_t'],
      ),
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}updated_at'],
      )!,
      fuel: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}fuel'],
      ),
      consumptionL100: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}consumption_l100'],
      ),
      lpgHeating: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}lpg_heating'],
      )!,
      cruiseSpeedKph: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}cruise_speed_kph'],
      ),
    );
  }

  @override
  Vehicles createAlias(String alias) {
    return Vehicles(attachedDatabase, alias);
  }

  @override
  bool get dontWriteConstraints => true;
}

class VehicleRow extends DataClass implements Insertable<VehicleRow> {
  final int id;
  final String type;
  final String towing;
  final double? heightM;
  final double? widthM;
  final double? lengthM;
  final double? weightT;
  final int updatedAt;

  /// The engine's fuel (`FuelType.wire`), the litres per 100 km and whether
  /// the living area heats on LPG (added in version 3).
  final String? fuel;
  final double? consumptionL100;
  final bool lpgHeating;

  /// The highest speed the driver keeps to, km/h; null for the router's
  /// usual speeds (added in version 4).
  final int? cruiseSpeedKph;
  const VehicleRow({
    required this.id,
    required this.type,
    required this.towing,
    this.heightM,
    this.widthM,
    this.lengthM,
    this.weightT,
    required this.updatedAt,
    this.fuel,
    this.consumptionL100,
    required this.lpgHeating,
    this.cruiseSpeedKph,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['type'] = Variable<String>(type);
    map['towing'] = Variable<String>(towing);
    if (!nullToAbsent || heightM != null) {
      map['height_m'] = Variable<double>(heightM);
    }
    if (!nullToAbsent || widthM != null) {
      map['width_m'] = Variable<double>(widthM);
    }
    if (!nullToAbsent || lengthM != null) {
      map['length_m'] = Variable<double>(lengthM);
    }
    if (!nullToAbsent || weightT != null) {
      map['weight_t'] = Variable<double>(weightT);
    }
    map['updated_at'] = Variable<int>(updatedAt);
    if (!nullToAbsent || fuel != null) {
      map['fuel'] = Variable<String>(fuel);
    }
    if (!nullToAbsent || consumptionL100 != null) {
      map['consumption_l100'] = Variable<double>(consumptionL100);
    }
    map['lpg_heating'] = Variable<bool>(lpgHeating);
    if (!nullToAbsent || cruiseSpeedKph != null) {
      map['cruise_speed_kph'] = Variable<int>(cruiseSpeedKph);
    }
    return map;
  }

  VehiclesCompanion toCompanion(bool nullToAbsent) {
    return VehiclesCompanion(
      id: Value(id),
      type: Value(type),
      towing: Value(towing),
      heightM: heightM == null && nullToAbsent
          ? const Value.absent()
          : Value(heightM),
      widthM: widthM == null && nullToAbsent
          ? const Value.absent()
          : Value(widthM),
      lengthM: lengthM == null && nullToAbsent
          ? const Value.absent()
          : Value(lengthM),
      weightT: weightT == null && nullToAbsent
          ? const Value.absent()
          : Value(weightT),
      updatedAt: Value(updatedAt),
      fuel: fuel == null && nullToAbsent ? const Value.absent() : Value(fuel),
      consumptionL100: consumptionL100 == null && nullToAbsent
          ? const Value.absent()
          : Value(consumptionL100),
      lpgHeating: Value(lpgHeating),
      cruiseSpeedKph: cruiseSpeedKph == null && nullToAbsent
          ? const Value.absent()
          : Value(cruiseSpeedKph),
    );
  }

  factory VehicleRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return VehicleRow(
      id: serializer.fromJson<int>(json['id']),
      type: serializer.fromJson<String>(json['type']),
      towing: serializer.fromJson<String>(json['towing']),
      heightM: serializer.fromJson<double?>(json['height_m']),
      widthM: serializer.fromJson<double?>(json['width_m']),
      lengthM: serializer.fromJson<double?>(json['length_m']),
      weightT: serializer.fromJson<double?>(json['weight_t']),
      updatedAt: serializer.fromJson<int>(json['updated_at']),
      fuel: serializer.fromJson<String?>(json['fuel']),
      consumptionL100: serializer.fromJson<double?>(json['consumption_l100']),
      lpgHeating: serializer.fromJson<bool>(json['lpg_heating']),
      cruiseSpeedKph: serializer.fromJson<int?>(json['cruise_speed_kph']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'type': serializer.toJson<String>(type),
      'towing': serializer.toJson<String>(towing),
      'height_m': serializer.toJson<double?>(heightM),
      'width_m': serializer.toJson<double?>(widthM),
      'length_m': serializer.toJson<double?>(lengthM),
      'weight_t': serializer.toJson<double?>(weightT),
      'updated_at': serializer.toJson<int>(updatedAt),
      'fuel': serializer.toJson<String?>(fuel),
      'consumption_l100': serializer.toJson<double?>(consumptionL100),
      'lpg_heating': serializer.toJson<bool>(lpgHeating),
      'cruise_speed_kph': serializer.toJson<int?>(cruiseSpeedKph),
    };
  }

  VehicleRow copyWith({
    int? id,
    String? type,
    String? towing,
    Value<double?> heightM = const Value.absent(),
    Value<double?> widthM = const Value.absent(),
    Value<double?> lengthM = const Value.absent(),
    Value<double?> weightT = const Value.absent(),
    int? updatedAt,
    Value<String?> fuel = const Value.absent(),
    Value<double?> consumptionL100 = const Value.absent(),
    bool? lpgHeating,
    Value<int?> cruiseSpeedKph = const Value.absent(),
  }) => VehicleRow(
    id: id ?? this.id,
    type: type ?? this.type,
    towing: towing ?? this.towing,
    heightM: heightM.present ? heightM.value : this.heightM,
    widthM: widthM.present ? widthM.value : this.widthM,
    lengthM: lengthM.present ? lengthM.value : this.lengthM,
    weightT: weightT.present ? weightT.value : this.weightT,
    updatedAt: updatedAt ?? this.updatedAt,
    fuel: fuel.present ? fuel.value : this.fuel,
    consumptionL100: consumptionL100.present
        ? consumptionL100.value
        : this.consumptionL100,
    lpgHeating: lpgHeating ?? this.lpgHeating,
    cruiseSpeedKph: cruiseSpeedKph.present
        ? cruiseSpeedKph.value
        : this.cruiseSpeedKph,
  );
  VehicleRow copyWithCompanion(VehiclesCompanion data) {
    return VehicleRow(
      id: data.id.present ? data.id.value : this.id,
      type: data.type.present ? data.type.value : this.type,
      towing: data.towing.present ? data.towing.value : this.towing,
      heightM: data.heightM.present ? data.heightM.value : this.heightM,
      widthM: data.widthM.present ? data.widthM.value : this.widthM,
      lengthM: data.lengthM.present ? data.lengthM.value : this.lengthM,
      weightT: data.weightT.present ? data.weightT.value : this.weightT,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      fuel: data.fuel.present ? data.fuel.value : this.fuel,
      consumptionL100: data.consumptionL100.present
          ? data.consumptionL100.value
          : this.consumptionL100,
      lpgHeating: data.lpgHeating.present
          ? data.lpgHeating.value
          : this.lpgHeating,
      cruiseSpeedKph: data.cruiseSpeedKph.present
          ? data.cruiseSpeedKph.value
          : this.cruiseSpeedKph,
    );
  }

  @override
  String toString() {
    return (StringBuffer('VehicleRow(')
          ..write('id: $id, ')
          ..write('type: $type, ')
          ..write('towing: $towing, ')
          ..write('heightM: $heightM, ')
          ..write('widthM: $widthM, ')
          ..write('lengthM: $lengthM, ')
          ..write('weightT: $weightT, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('fuel: $fuel, ')
          ..write('consumptionL100: $consumptionL100, ')
          ..write('lpgHeating: $lpgHeating, ')
          ..write('cruiseSpeedKph: $cruiseSpeedKph')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    type,
    towing,
    heightM,
    widthM,
    lengthM,
    weightT,
    updatedAt,
    fuel,
    consumptionL100,
    lpgHeating,
    cruiseSpeedKph,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is VehicleRow &&
          other.id == this.id &&
          other.type == this.type &&
          other.towing == this.towing &&
          other.heightM == this.heightM &&
          other.widthM == this.widthM &&
          other.lengthM == this.lengthM &&
          other.weightT == this.weightT &&
          other.updatedAt == this.updatedAt &&
          other.fuel == this.fuel &&
          other.consumptionL100 == this.consumptionL100 &&
          other.lpgHeating == this.lpgHeating &&
          other.cruiseSpeedKph == this.cruiseSpeedKph);
}

class VehiclesCompanion extends UpdateCompanion<VehicleRow> {
  final Value<int> id;
  final Value<String> type;
  final Value<String> towing;
  final Value<double?> heightM;
  final Value<double?> widthM;
  final Value<double?> lengthM;
  final Value<double?> weightT;
  final Value<int> updatedAt;
  final Value<String?> fuel;
  final Value<double?> consumptionL100;
  final Value<bool> lpgHeating;
  final Value<int?> cruiseSpeedKph;
  const VehiclesCompanion({
    this.id = const Value.absent(),
    this.type = const Value.absent(),
    this.towing = const Value.absent(),
    this.heightM = const Value.absent(),
    this.widthM = const Value.absent(),
    this.lengthM = const Value.absent(),
    this.weightT = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.fuel = const Value.absent(),
    this.consumptionL100 = const Value.absent(),
    this.lpgHeating = const Value.absent(),
    this.cruiseSpeedKph = const Value.absent(),
  });
  VehiclesCompanion.insert({
    this.id = const Value.absent(),
    required String type,
    this.towing = const Value.absent(),
    this.heightM = const Value.absent(),
    this.widthM = const Value.absent(),
    this.lengthM = const Value.absent(),
    this.weightT = const Value.absent(),
    required int updatedAt,
    this.fuel = const Value.absent(),
    this.consumptionL100 = const Value.absent(),
    this.lpgHeating = const Value.absent(),
    this.cruiseSpeedKph = const Value.absent(),
  }) : type = Value(type),
       updatedAt = Value(updatedAt);
  static Insertable<VehicleRow> custom({
    Expression<int>? id,
    Expression<String>? type,
    Expression<String>? towing,
    Expression<double>? heightM,
    Expression<double>? widthM,
    Expression<double>? lengthM,
    Expression<double>? weightT,
    Expression<int>? updatedAt,
    Expression<String>? fuel,
    Expression<double>? consumptionL100,
    Expression<bool>? lpgHeating,
    Expression<int>? cruiseSpeedKph,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (type != null) 'type': type,
      if (towing != null) 'towing': towing,
      if (heightM != null) 'height_m': heightM,
      if (widthM != null) 'width_m': widthM,
      if (lengthM != null) 'length_m': lengthM,
      if (weightT != null) 'weight_t': weightT,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (fuel != null) 'fuel': fuel,
      if (consumptionL100 != null) 'consumption_l100': consumptionL100,
      if (lpgHeating != null) 'lpg_heating': lpgHeating,
      if (cruiseSpeedKph != null) 'cruise_speed_kph': cruiseSpeedKph,
    });
  }

  VehiclesCompanion copyWith({
    Value<int>? id,
    Value<String>? type,
    Value<String>? towing,
    Value<double?>? heightM,
    Value<double?>? widthM,
    Value<double?>? lengthM,
    Value<double?>? weightT,
    Value<int>? updatedAt,
    Value<String?>? fuel,
    Value<double?>? consumptionL100,
    Value<bool>? lpgHeating,
    Value<int?>? cruiseSpeedKph,
  }) {
    return VehiclesCompanion(
      id: id ?? this.id,
      type: type ?? this.type,
      towing: towing ?? this.towing,
      heightM: heightM ?? this.heightM,
      widthM: widthM ?? this.widthM,
      lengthM: lengthM ?? this.lengthM,
      weightT: weightT ?? this.weightT,
      updatedAt: updatedAt ?? this.updatedAt,
      fuel: fuel ?? this.fuel,
      consumptionL100: consumptionL100 ?? this.consumptionL100,
      lpgHeating: lpgHeating ?? this.lpgHeating,
      cruiseSpeedKph: cruiseSpeedKph ?? this.cruiseSpeedKph,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (type.present) {
      map['type'] = Variable<String>(type.value);
    }
    if (towing.present) {
      map['towing'] = Variable<String>(towing.value);
    }
    if (heightM.present) {
      map['height_m'] = Variable<double>(heightM.value);
    }
    if (widthM.present) {
      map['width_m'] = Variable<double>(widthM.value);
    }
    if (lengthM.present) {
      map['length_m'] = Variable<double>(lengthM.value);
    }
    if (weightT.present) {
      map['weight_t'] = Variable<double>(weightT.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<int>(updatedAt.value);
    }
    if (fuel.present) {
      map['fuel'] = Variable<String>(fuel.value);
    }
    if (consumptionL100.present) {
      map['consumption_l100'] = Variable<double>(consumptionL100.value);
    }
    if (lpgHeating.present) {
      map['lpg_heating'] = Variable<bool>(lpgHeating.value);
    }
    if (cruiseSpeedKph.present) {
      map['cruise_speed_kph'] = Variable<int>(cruiseSpeedKph.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('VehiclesCompanion(')
          ..write('id: $id, ')
          ..write('type: $type, ')
          ..write('towing: $towing, ')
          ..write('heightM: $heightM, ')
          ..write('widthM: $widthM, ')
          ..write('lengthM: $lengthM, ')
          ..write('weightT: $weightT, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('fuel: $fuel, ')
          ..write('consumptionL100: $consumptionL100, ')
          ..write('lpgHeating: $lpgHeating, ')
          ..write('cruiseSpeedKph: $cruiseSpeedKph')
          ..write(')'))
        .toString();
  }
}

class FavoriteSyncBase extends Table
    with TableInfo<FavoriteSyncBase, FavoriteSyncBaseRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  FavoriteSyncBase(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _serverIdMeta = const VerificationMeta(
    'serverId',
  );
  late final GeneratedColumn<String> serverId = GeneratedColumn<String>(
    'server_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL PRIMARY KEY',
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  static const VerificationMeta _placeIdsMeta = const VerificationMeta(
    'placeIds',
  );
  late final GeneratedColumn<String> placeIds = GeneratedColumn<String>(
    'place_ids',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  static const VerificationMeta _localOnlyMeta = const VerificationMeta(
    'localOnly',
  );
  late final GeneratedColumn<String> localOnly = GeneratedColumn<String>(
    'local_only',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    $customConstraints: 'NOT NULL DEFAULT \'[]\'',
    defaultValue: const CustomExpression('\'[]\''),
  );
  static const VerificationMeta _pointsMeta = const VerificationMeta('points');
  late final GeneratedColumn<String> points = GeneratedColumn<String>(
    'points',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    $customConstraints: 'NOT NULL DEFAULT \'{}\'',
    defaultValue: const CustomExpression('\'{}\''),
  );
  static const VerificationMeta _localOnlyPointsMeta = const VerificationMeta(
    'localOnlyPoints',
  );
  late final GeneratedColumn<String> localOnlyPoints = GeneratedColumn<String>(
    'local_only_points',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    $customConstraints: 'NOT NULL DEFAULT \'{}\'',
    defaultValue: const CustomExpression('\'{}\''),
  );
  @override
  List<GeneratedColumn> get $columns => [
    serverId,
    name,
    placeIds,
    localOnly,
    points,
    localOnlyPoints,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'favorite_sync_base';
  @override
  VerificationContext validateIntegrity(
    Insertable<FavoriteSyncBaseRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('server_id')) {
      context.handle(
        _serverIdMeta,
        serverId.isAcceptableOrUnknown(data['server_id']!, _serverIdMeta),
      );
    } else if (isInserting) {
      context.missing(_serverIdMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('place_ids')) {
      context.handle(
        _placeIdsMeta,
        placeIds.isAcceptableOrUnknown(data['place_ids']!, _placeIdsMeta),
      );
    } else if (isInserting) {
      context.missing(_placeIdsMeta);
    }
    if (data.containsKey('local_only')) {
      context.handle(
        _localOnlyMeta,
        localOnly.isAcceptableOrUnknown(data['local_only']!, _localOnlyMeta),
      );
    }
    if (data.containsKey('points')) {
      context.handle(
        _pointsMeta,
        points.isAcceptableOrUnknown(data['points']!, _pointsMeta),
      );
    }
    if (data.containsKey('local_only_points')) {
      context.handle(
        _localOnlyPointsMeta,
        localOnlyPoints.isAcceptableOrUnknown(
          data['local_only_points']!,
          _localOnlyPointsMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {serverId};
  @override
  FavoriteSyncBaseRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return FavoriteSyncBaseRow(
      serverId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}server_id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      placeIds: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}place_ids'],
      )!,
      localOnly: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}local_only'],
      )!,
      points: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}points'],
      )!,
      localOnlyPoints: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}local_only_points'],
      )!,
    );
  }

  @override
  FavoriteSyncBase createAlias(String alias) {
    return FavoriteSyncBase(attachedDatabase, alias);
  }

  @override
  bool get dontWriteConstraints => true;
}

class FavoriteSyncBaseRow extends DataClass
    implements Insertable<FavoriteSyncBaseRow> {
  final String serverId;
  final String name;

  /// JSON array of place ids, sorted.
  final String placeIds;

  /// JSON array of the places of this list the server does not know (gone
  /// from the data since they were saved): kept on the device, never sent
  /// again.
  final String localOnly;

  /// The list's saved points as both sides held them: a JSON object of
  /// point id to `SavedPoint.fingerprint`, so a point renamed on one side
  /// since is told from one renamed on the other. Empty until an API that
  /// knows the points answered. Added in version 5.
  final String points;

  /// The saved points the server refused, a JSON object of point id to the
  /// fingerprint refused: kept on the device, sent again once changed here.
  /// Added in version 5.
  final String localOnlyPoints;
  const FavoriteSyncBaseRow({
    required this.serverId,
    required this.name,
    required this.placeIds,
    required this.localOnly,
    required this.points,
    required this.localOnlyPoints,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['server_id'] = Variable<String>(serverId);
    map['name'] = Variable<String>(name);
    map['place_ids'] = Variable<String>(placeIds);
    map['local_only'] = Variable<String>(localOnly);
    map['points'] = Variable<String>(points);
    map['local_only_points'] = Variable<String>(localOnlyPoints);
    return map;
  }

  FavoriteSyncBaseCompanion toCompanion(bool nullToAbsent) {
    return FavoriteSyncBaseCompanion(
      serverId: Value(serverId),
      name: Value(name),
      placeIds: Value(placeIds),
      localOnly: Value(localOnly),
      points: Value(points),
      localOnlyPoints: Value(localOnlyPoints),
    );
  }

  factory FavoriteSyncBaseRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return FavoriteSyncBaseRow(
      serverId: serializer.fromJson<String>(json['server_id']),
      name: serializer.fromJson<String>(json['name']),
      placeIds: serializer.fromJson<String>(json['place_ids']),
      localOnly: serializer.fromJson<String>(json['local_only']),
      points: serializer.fromJson<String>(json['points']),
      localOnlyPoints: serializer.fromJson<String>(json['local_only_points']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'server_id': serializer.toJson<String>(serverId),
      'name': serializer.toJson<String>(name),
      'place_ids': serializer.toJson<String>(placeIds),
      'local_only': serializer.toJson<String>(localOnly),
      'points': serializer.toJson<String>(points),
      'local_only_points': serializer.toJson<String>(localOnlyPoints),
    };
  }

  FavoriteSyncBaseRow copyWith({
    String? serverId,
    String? name,
    String? placeIds,
    String? localOnly,
    String? points,
    String? localOnlyPoints,
  }) => FavoriteSyncBaseRow(
    serverId: serverId ?? this.serverId,
    name: name ?? this.name,
    placeIds: placeIds ?? this.placeIds,
    localOnly: localOnly ?? this.localOnly,
    points: points ?? this.points,
    localOnlyPoints: localOnlyPoints ?? this.localOnlyPoints,
  );
  FavoriteSyncBaseRow copyWithCompanion(FavoriteSyncBaseCompanion data) {
    return FavoriteSyncBaseRow(
      serverId: data.serverId.present ? data.serverId.value : this.serverId,
      name: data.name.present ? data.name.value : this.name,
      placeIds: data.placeIds.present ? data.placeIds.value : this.placeIds,
      localOnly: data.localOnly.present ? data.localOnly.value : this.localOnly,
      points: data.points.present ? data.points.value : this.points,
      localOnlyPoints: data.localOnlyPoints.present
          ? data.localOnlyPoints.value
          : this.localOnlyPoints,
    );
  }

  @override
  String toString() {
    return (StringBuffer('FavoriteSyncBaseRow(')
          ..write('serverId: $serverId, ')
          ..write('name: $name, ')
          ..write('placeIds: $placeIds, ')
          ..write('localOnly: $localOnly, ')
          ..write('points: $points, ')
          ..write('localOnlyPoints: $localOnlyPoints')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(serverId, name, placeIds, localOnly, points, localOnlyPoints);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is FavoriteSyncBaseRow &&
          other.serverId == this.serverId &&
          other.name == this.name &&
          other.placeIds == this.placeIds &&
          other.localOnly == this.localOnly &&
          other.points == this.points &&
          other.localOnlyPoints == this.localOnlyPoints);
}

class FavoriteSyncBaseCompanion extends UpdateCompanion<FavoriteSyncBaseRow> {
  final Value<String> serverId;
  final Value<String> name;
  final Value<String> placeIds;
  final Value<String> localOnly;
  final Value<String> points;
  final Value<String> localOnlyPoints;
  final Value<int> rowid;
  const FavoriteSyncBaseCompanion({
    this.serverId = const Value.absent(),
    this.name = const Value.absent(),
    this.placeIds = const Value.absent(),
    this.localOnly = const Value.absent(),
    this.points = const Value.absent(),
    this.localOnlyPoints = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  FavoriteSyncBaseCompanion.insert({
    required String serverId,
    required String name,
    required String placeIds,
    this.localOnly = const Value.absent(),
    this.points = const Value.absent(),
    this.localOnlyPoints = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : serverId = Value(serverId),
       name = Value(name),
       placeIds = Value(placeIds);
  static Insertable<FavoriteSyncBaseRow> custom({
    Expression<String>? serverId,
    Expression<String>? name,
    Expression<String>? placeIds,
    Expression<String>? localOnly,
    Expression<String>? points,
    Expression<String>? localOnlyPoints,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (serverId != null) 'server_id': serverId,
      if (name != null) 'name': name,
      if (placeIds != null) 'place_ids': placeIds,
      if (localOnly != null) 'local_only': localOnly,
      if (points != null) 'points': points,
      if (localOnlyPoints != null) 'local_only_points': localOnlyPoints,
      if (rowid != null) 'rowid': rowid,
    });
  }

  FavoriteSyncBaseCompanion copyWith({
    Value<String>? serverId,
    Value<String>? name,
    Value<String>? placeIds,
    Value<String>? localOnly,
    Value<String>? points,
    Value<String>? localOnlyPoints,
    Value<int>? rowid,
  }) {
    return FavoriteSyncBaseCompanion(
      serverId: serverId ?? this.serverId,
      name: name ?? this.name,
      placeIds: placeIds ?? this.placeIds,
      localOnly: localOnly ?? this.localOnly,
      points: points ?? this.points,
      localOnlyPoints: localOnlyPoints ?? this.localOnlyPoints,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (serverId.present) {
      map['server_id'] = Variable<String>(serverId.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (placeIds.present) {
      map['place_ids'] = Variable<String>(placeIds.value);
    }
    if (localOnly.present) {
      map['local_only'] = Variable<String>(localOnly.value);
    }
    if (points.present) {
      map['points'] = Variable<String>(points.value);
    }
    if (localOnlyPoints.present) {
      map['local_only_points'] = Variable<String>(localOnlyPoints.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('FavoriteSyncBaseCompanion(')
          ..write('serverId: $serverId, ')
          ..write('name: $name, ')
          ..write('placeIds: $placeIds, ')
          ..write('localOnly: $localOnly, ')
          ..write('points: $points, ')
          ..write('localOnlyPoints: $localOnlyPoints, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class Outbox extends Table with TableInfo<Outbox, OutboxRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  Outbox(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL PRIMARY KEY',
  );
  static const VerificationMeta _kindMeta = const VerificationMeta('kind');
  late final GeneratedColumn<String> kind = GeneratedColumn<String>(
    'kind',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  static const VerificationMeta _placeIdMeta = const VerificationMeta(
    'placeId',
  );
  late final GeneratedColumn<String> placeId = GeneratedColumn<String>(
    'place_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    $customConstraints: '',
  );
  static const VerificationMeta _payloadMeta = const VerificationMeta(
    'payload',
  );
  late final GeneratedColumn<String> payload = GeneratedColumn<String>(
    'payload',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  static const VerificationMeta _fileIdMeta = const VerificationMeta('fileId');
  late final GeneratedColumn<String> fileId = GeneratedColumn<String>(
    'file_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    $customConstraints: '',
  );
  static const VerificationMeta _accountIdMeta = const VerificationMeta(
    'accountId',
  );
  late final GeneratedColumn<String> accountId = GeneratedColumn<String>(
    'account_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    $customConstraints: '',
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  late final GeneratedColumn<int> createdAt = GeneratedColumn<int>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  static const VerificationMeta _stateMeta = const VerificationMeta('state');
  late final GeneratedColumn<String> state = GeneratedColumn<String>(
    'state',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    $customConstraints: 'NOT NULL DEFAULT \'pending\'',
    defaultValue: const CustomExpression('\'pending\''),
  );
  static const VerificationMeta _uncertainMeta = const VerificationMeta(
    'uncertain',
  );
  late final GeneratedColumn<bool> uncertain = GeneratedColumn<bool>(
    'uncertain',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    $customConstraints: 'NOT NULL DEFAULT FALSE',
    defaultValue: const CustomExpression('FALSE'),
  );
  static const VerificationMeta _attemptsMeta = const VerificationMeta(
    'attempts',
  );
  late final GeneratedColumn<int> attempts = GeneratedColumn<int>(
    'attempts',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    $customConstraints: 'NOT NULL DEFAULT 0',
    defaultValue: const CustomExpression('0'),
  );
  static const VerificationMeta _nextAttemptAtMeta = const VerificationMeta(
    'nextAttemptAt',
  );
  late final GeneratedColumn<int> nextAttemptAt = GeneratedColumn<int>(
    'next_attempt_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    $customConstraints: 'NOT NULL DEFAULT 0',
    defaultValue: const CustomExpression('0'),
  );
  static const VerificationMeta _attemptStartedAtMeta = const VerificationMeta(
    'attemptStartedAt',
  );
  late final GeneratedColumn<int> attemptStartedAt = GeneratedColumn<int>(
    'attempt_started_at',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    $customConstraints: '',
  );
  static const VerificationMeta _errorCodeMeta = const VerificationMeta(
    'errorCode',
  );
  late final GeneratedColumn<String> errorCode = GeneratedColumn<String>(
    'error_code',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    $customConstraints: '',
  );
  static const VerificationMeta _errorDetailMeta = const VerificationMeta(
    'errorDetail',
  );
  late final GeneratedColumn<String> errorDetail = GeneratedColumn<String>(
    'error_detail',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    $customConstraints: '',
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    kind,
    placeId,
    payload,
    fileId,
    accountId,
    createdAt,
    state,
    uncertain,
    attempts,
    nextAttemptAt,
    attemptStartedAt,
    errorCode,
    errorDetail,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'outbox';
  @override
  VerificationContext validateIntegrity(
    Insertable<OutboxRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('kind')) {
      context.handle(
        _kindMeta,
        kind.isAcceptableOrUnknown(data['kind']!, _kindMeta),
      );
    } else if (isInserting) {
      context.missing(_kindMeta);
    }
    if (data.containsKey('place_id')) {
      context.handle(
        _placeIdMeta,
        placeId.isAcceptableOrUnknown(data['place_id']!, _placeIdMeta),
      );
    }
    if (data.containsKey('payload')) {
      context.handle(
        _payloadMeta,
        payload.isAcceptableOrUnknown(data['payload']!, _payloadMeta),
      );
    } else if (isInserting) {
      context.missing(_payloadMeta);
    }
    if (data.containsKey('file_id')) {
      context.handle(
        _fileIdMeta,
        fileId.isAcceptableOrUnknown(data['file_id']!, _fileIdMeta),
      );
    }
    if (data.containsKey('account_id')) {
      context.handle(
        _accountIdMeta,
        accountId.isAcceptableOrUnknown(data['account_id']!, _accountIdMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('state')) {
      context.handle(
        _stateMeta,
        state.isAcceptableOrUnknown(data['state']!, _stateMeta),
      );
    }
    if (data.containsKey('uncertain')) {
      context.handle(
        _uncertainMeta,
        uncertain.isAcceptableOrUnknown(data['uncertain']!, _uncertainMeta),
      );
    }
    if (data.containsKey('attempts')) {
      context.handle(
        _attemptsMeta,
        attempts.isAcceptableOrUnknown(data['attempts']!, _attemptsMeta),
      );
    }
    if (data.containsKey('next_attempt_at')) {
      context.handle(
        _nextAttemptAtMeta,
        nextAttemptAt.isAcceptableOrUnknown(
          data['next_attempt_at']!,
          _nextAttemptAtMeta,
        ),
      );
    }
    if (data.containsKey('attempt_started_at')) {
      context.handle(
        _attemptStartedAtMeta,
        attemptStartedAt.isAcceptableOrUnknown(
          data['attempt_started_at']!,
          _attemptStartedAtMeta,
        ),
      );
    }
    if (data.containsKey('error_code')) {
      context.handle(
        _errorCodeMeta,
        errorCode.isAcceptableOrUnknown(data['error_code']!, _errorCodeMeta),
      );
    }
    if (data.containsKey('error_detail')) {
      context.handle(
        _errorDetailMeta,
        errorDetail.isAcceptableOrUnknown(
          data['error_detail']!,
          _errorDetailMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  OutboxRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return OutboxRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      kind: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}kind'],
      )!,
      placeId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}place_id'],
      ),
      payload: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}payload'],
      )!,
      fileId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}file_id'],
      ),
      accountId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}account_id'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}created_at'],
      )!,
      state: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}state'],
      )!,
      uncertain: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}uncertain'],
      )!,
      attempts: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}attempts'],
      )!,
      nextAttemptAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}next_attempt_at'],
      )!,
      attemptStartedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}attempt_started_at'],
      ),
      errorCode: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}error_code'],
      ),
      errorDetail: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}error_detail'],
      ),
    );
  }

  @override
  Outbox createAlias(String alias) {
    return Outbox(attachedDatabase, alias);
  }

  @override
  bool get dontWriteConstraints => true;
}

class OutboxRow extends DataClass implements Insertable<OutboxRow> {
  final String id;
  final String kind;

  /// The place it is about, to show it on the place and to merge two
  /// ratings of one place into the last one.
  final String? placeId;

  /// The variables of the request, JSON.
  final String payload;

  /// A photo's bytes, in the pending files (outside this database).
  final String? fileId;

  /// The account it was made for; null when it was made before the account
  /// existed. A contribution of another account is never sent as this one.
  final String? accountId;
  final int createdAt;

  /// pending, sending (an attempt under way, or cut by the app's end), or
  /// failed (refused by the server: shown to the user, never resent alone).
  final String state;

  /// An attempt may have reached the server without its answer reaching
  /// the device: the next attempt looks for it first.
  final bool uncertain;
  final int attempts;
  final int nextAttemptAt;
  final int? attemptStartedAt;
  final String? errorCode;
  final String? errorDetail;
  const OutboxRow({
    required this.id,
    required this.kind,
    this.placeId,
    required this.payload,
    this.fileId,
    this.accountId,
    required this.createdAt,
    required this.state,
    required this.uncertain,
    required this.attempts,
    required this.nextAttemptAt,
    this.attemptStartedAt,
    this.errorCode,
    this.errorDetail,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['kind'] = Variable<String>(kind);
    if (!nullToAbsent || placeId != null) {
      map['place_id'] = Variable<String>(placeId);
    }
    map['payload'] = Variable<String>(payload);
    if (!nullToAbsent || fileId != null) {
      map['file_id'] = Variable<String>(fileId);
    }
    if (!nullToAbsent || accountId != null) {
      map['account_id'] = Variable<String>(accountId);
    }
    map['created_at'] = Variable<int>(createdAt);
    map['state'] = Variable<String>(state);
    map['uncertain'] = Variable<bool>(uncertain);
    map['attempts'] = Variable<int>(attempts);
    map['next_attempt_at'] = Variable<int>(nextAttemptAt);
    if (!nullToAbsent || attemptStartedAt != null) {
      map['attempt_started_at'] = Variable<int>(attemptStartedAt);
    }
    if (!nullToAbsent || errorCode != null) {
      map['error_code'] = Variable<String>(errorCode);
    }
    if (!nullToAbsent || errorDetail != null) {
      map['error_detail'] = Variable<String>(errorDetail);
    }
    return map;
  }

  OutboxCompanion toCompanion(bool nullToAbsent) {
    return OutboxCompanion(
      id: Value(id),
      kind: Value(kind),
      placeId: placeId == null && nullToAbsent
          ? const Value.absent()
          : Value(placeId),
      payload: Value(payload),
      fileId: fileId == null && nullToAbsent
          ? const Value.absent()
          : Value(fileId),
      accountId: accountId == null && nullToAbsent
          ? const Value.absent()
          : Value(accountId),
      createdAt: Value(createdAt),
      state: Value(state),
      uncertain: Value(uncertain),
      attempts: Value(attempts),
      nextAttemptAt: Value(nextAttemptAt),
      attemptStartedAt: attemptStartedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(attemptStartedAt),
      errorCode: errorCode == null && nullToAbsent
          ? const Value.absent()
          : Value(errorCode),
      errorDetail: errorDetail == null && nullToAbsent
          ? const Value.absent()
          : Value(errorDetail),
    );
  }

  factory OutboxRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return OutboxRow(
      id: serializer.fromJson<String>(json['id']),
      kind: serializer.fromJson<String>(json['kind']),
      placeId: serializer.fromJson<String?>(json['place_id']),
      payload: serializer.fromJson<String>(json['payload']),
      fileId: serializer.fromJson<String?>(json['file_id']),
      accountId: serializer.fromJson<String?>(json['account_id']),
      createdAt: serializer.fromJson<int>(json['created_at']),
      state: serializer.fromJson<String>(json['state']),
      uncertain: serializer.fromJson<bool>(json['uncertain']),
      attempts: serializer.fromJson<int>(json['attempts']),
      nextAttemptAt: serializer.fromJson<int>(json['next_attempt_at']),
      attemptStartedAt: serializer.fromJson<int?>(json['attempt_started_at']),
      errorCode: serializer.fromJson<String?>(json['error_code']),
      errorDetail: serializer.fromJson<String?>(json['error_detail']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'kind': serializer.toJson<String>(kind),
      'place_id': serializer.toJson<String?>(placeId),
      'payload': serializer.toJson<String>(payload),
      'file_id': serializer.toJson<String?>(fileId),
      'account_id': serializer.toJson<String?>(accountId),
      'created_at': serializer.toJson<int>(createdAt),
      'state': serializer.toJson<String>(state),
      'uncertain': serializer.toJson<bool>(uncertain),
      'attempts': serializer.toJson<int>(attempts),
      'next_attempt_at': serializer.toJson<int>(nextAttemptAt),
      'attempt_started_at': serializer.toJson<int?>(attemptStartedAt),
      'error_code': serializer.toJson<String?>(errorCode),
      'error_detail': serializer.toJson<String?>(errorDetail),
    };
  }

  OutboxRow copyWith({
    String? id,
    String? kind,
    Value<String?> placeId = const Value.absent(),
    String? payload,
    Value<String?> fileId = const Value.absent(),
    Value<String?> accountId = const Value.absent(),
    int? createdAt,
    String? state,
    bool? uncertain,
    int? attempts,
    int? nextAttemptAt,
    Value<int?> attemptStartedAt = const Value.absent(),
    Value<String?> errorCode = const Value.absent(),
    Value<String?> errorDetail = const Value.absent(),
  }) => OutboxRow(
    id: id ?? this.id,
    kind: kind ?? this.kind,
    placeId: placeId.present ? placeId.value : this.placeId,
    payload: payload ?? this.payload,
    fileId: fileId.present ? fileId.value : this.fileId,
    accountId: accountId.present ? accountId.value : this.accountId,
    createdAt: createdAt ?? this.createdAt,
    state: state ?? this.state,
    uncertain: uncertain ?? this.uncertain,
    attempts: attempts ?? this.attempts,
    nextAttemptAt: nextAttemptAt ?? this.nextAttemptAt,
    attemptStartedAt: attemptStartedAt.present
        ? attemptStartedAt.value
        : this.attemptStartedAt,
    errorCode: errorCode.present ? errorCode.value : this.errorCode,
    errorDetail: errorDetail.present ? errorDetail.value : this.errorDetail,
  );
  OutboxRow copyWithCompanion(OutboxCompanion data) {
    return OutboxRow(
      id: data.id.present ? data.id.value : this.id,
      kind: data.kind.present ? data.kind.value : this.kind,
      placeId: data.placeId.present ? data.placeId.value : this.placeId,
      payload: data.payload.present ? data.payload.value : this.payload,
      fileId: data.fileId.present ? data.fileId.value : this.fileId,
      accountId: data.accountId.present ? data.accountId.value : this.accountId,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      state: data.state.present ? data.state.value : this.state,
      uncertain: data.uncertain.present ? data.uncertain.value : this.uncertain,
      attempts: data.attempts.present ? data.attempts.value : this.attempts,
      nextAttemptAt: data.nextAttemptAt.present
          ? data.nextAttemptAt.value
          : this.nextAttemptAt,
      attemptStartedAt: data.attemptStartedAt.present
          ? data.attemptStartedAt.value
          : this.attemptStartedAt,
      errorCode: data.errorCode.present ? data.errorCode.value : this.errorCode,
      errorDetail: data.errorDetail.present
          ? data.errorDetail.value
          : this.errorDetail,
    );
  }

  @override
  String toString() {
    return (StringBuffer('OutboxRow(')
          ..write('id: $id, ')
          ..write('kind: $kind, ')
          ..write('placeId: $placeId, ')
          ..write('payload: $payload, ')
          ..write('fileId: $fileId, ')
          ..write('accountId: $accountId, ')
          ..write('createdAt: $createdAt, ')
          ..write('state: $state, ')
          ..write('uncertain: $uncertain, ')
          ..write('attempts: $attempts, ')
          ..write('nextAttemptAt: $nextAttemptAt, ')
          ..write('attemptStartedAt: $attemptStartedAt, ')
          ..write('errorCode: $errorCode, ')
          ..write('errorDetail: $errorDetail')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    kind,
    placeId,
    payload,
    fileId,
    accountId,
    createdAt,
    state,
    uncertain,
    attempts,
    nextAttemptAt,
    attemptStartedAt,
    errorCode,
    errorDetail,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is OutboxRow &&
          other.id == this.id &&
          other.kind == this.kind &&
          other.placeId == this.placeId &&
          other.payload == this.payload &&
          other.fileId == this.fileId &&
          other.accountId == this.accountId &&
          other.createdAt == this.createdAt &&
          other.state == this.state &&
          other.uncertain == this.uncertain &&
          other.attempts == this.attempts &&
          other.nextAttemptAt == this.nextAttemptAt &&
          other.attemptStartedAt == this.attemptStartedAt &&
          other.errorCode == this.errorCode &&
          other.errorDetail == this.errorDetail);
}

class OutboxCompanion extends UpdateCompanion<OutboxRow> {
  final Value<String> id;
  final Value<String> kind;
  final Value<String?> placeId;
  final Value<String> payload;
  final Value<String?> fileId;
  final Value<String?> accountId;
  final Value<int> createdAt;
  final Value<String> state;
  final Value<bool> uncertain;
  final Value<int> attempts;
  final Value<int> nextAttemptAt;
  final Value<int?> attemptStartedAt;
  final Value<String?> errorCode;
  final Value<String?> errorDetail;
  final Value<int> rowid;
  const OutboxCompanion({
    this.id = const Value.absent(),
    this.kind = const Value.absent(),
    this.placeId = const Value.absent(),
    this.payload = const Value.absent(),
    this.fileId = const Value.absent(),
    this.accountId = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.state = const Value.absent(),
    this.uncertain = const Value.absent(),
    this.attempts = const Value.absent(),
    this.nextAttemptAt = const Value.absent(),
    this.attemptStartedAt = const Value.absent(),
    this.errorCode = const Value.absent(),
    this.errorDetail = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  OutboxCompanion.insert({
    required String id,
    required String kind,
    this.placeId = const Value.absent(),
    required String payload,
    this.fileId = const Value.absent(),
    this.accountId = const Value.absent(),
    required int createdAt,
    this.state = const Value.absent(),
    this.uncertain = const Value.absent(),
    this.attempts = const Value.absent(),
    this.nextAttemptAt = const Value.absent(),
    this.attemptStartedAt = const Value.absent(),
    this.errorCode = const Value.absent(),
    this.errorDetail = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       kind = Value(kind),
       payload = Value(payload),
       createdAt = Value(createdAt);
  static Insertable<OutboxRow> custom({
    Expression<String>? id,
    Expression<String>? kind,
    Expression<String>? placeId,
    Expression<String>? payload,
    Expression<String>? fileId,
    Expression<String>? accountId,
    Expression<int>? createdAt,
    Expression<String>? state,
    Expression<bool>? uncertain,
    Expression<int>? attempts,
    Expression<int>? nextAttemptAt,
    Expression<int>? attemptStartedAt,
    Expression<String>? errorCode,
    Expression<String>? errorDetail,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (kind != null) 'kind': kind,
      if (placeId != null) 'place_id': placeId,
      if (payload != null) 'payload': payload,
      if (fileId != null) 'file_id': fileId,
      if (accountId != null) 'account_id': accountId,
      if (createdAt != null) 'created_at': createdAt,
      if (state != null) 'state': state,
      if (uncertain != null) 'uncertain': uncertain,
      if (attempts != null) 'attempts': attempts,
      if (nextAttemptAt != null) 'next_attempt_at': nextAttemptAt,
      if (attemptStartedAt != null) 'attempt_started_at': attemptStartedAt,
      if (errorCode != null) 'error_code': errorCode,
      if (errorDetail != null) 'error_detail': errorDetail,
      if (rowid != null) 'rowid': rowid,
    });
  }

  OutboxCompanion copyWith({
    Value<String>? id,
    Value<String>? kind,
    Value<String?>? placeId,
    Value<String>? payload,
    Value<String?>? fileId,
    Value<String?>? accountId,
    Value<int>? createdAt,
    Value<String>? state,
    Value<bool>? uncertain,
    Value<int>? attempts,
    Value<int>? nextAttemptAt,
    Value<int?>? attemptStartedAt,
    Value<String?>? errorCode,
    Value<String?>? errorDetail,
    Value<int>? rowid,
  }) {
    return OutboxCompanion(
      id: id ?? this.id,
      kind: kind ?? this.kind,
      placeId: placeId ?? this.placeId,
      payload: payload ?? this.payload,
      fileId: fileId ?? this.fileId,
      accountId: accountId ?? this.accountId,
      createdAt: createdAt ?? this.createdAt,
      state: state ?? this.state,
      uncertain: uncertain ?? this.uncertain,
      attempts: attempts ?? this.attempts,
      nextAttemptAt: nextAttemptAt ?? this.nextAttemptAt,
      attemptStartedAt: attemptStartedAt ?? this.attemptStartedAt,
      errorCode: errorCode ?? this.errorCode,
      errorDetail: errorDetail ?? this.errorDetail,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (kind.present) {
      map['kind'] = Variable<String>(kind.value);
    }
    if (placeId.present) {
      map['place_id'] = Variable<String>(placeId.value);
    }
    if (payload.present) {
      map['payload'] = Variable<String>(payload.value);
    }
    if (fileId.present) {
      map['file_id'] = Variable<String>(fileId.value);
    }
    if (accountId.present) {
      map['account_id'] = Variable<String>(accountId.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<int>(createdAt.value);
    }
    if (state.present) {
      map['state'] = Variable<String>(state.value);
    }
    if (uncertain.present) {
      map['uncertain'] = Variable<bool>(uncertain.value);
    }
    if (attempts.present) {
      map['attempts'] = Variable<int>(attempts.value);
    }
    if (nextAttemptAt.present) {
      map['next_attempt_at'] = Variable<int>(nextAttemptAt.value);
    }
    if (attemptStartedAt.present) {
      map['attempt_started_at'] = Variable<int>(attemptStartedAt.value);
    }
    if (errorCode.present) {
      map['error_code'] = Variable<String>(errorCode.value);
    }
    if (errorDetail.present) {
      map['error_detail'] = Variable<String>(errorDetail.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('OutboxCompanion(')
          ..write('id: $id, ')
          ..write('kind: $kind, ')
          ..write('placeId: $placeId, ')
          ..write('payload: $payload, ')
          ..write('fileId: $fileId, ')
          ..write('accountId: $accountId, ')
          ..write('createdAt: $createdAt, ')
          ..write('state: $state, ')
          ..write('uncertain: $uncertain, ')
          ..write('attempts: $attempts, ')
          ..write('nextAttemptAt: $nextAttemptAt, ')
          ..write('attemptStartedAt: $attemptStartedAt, ')
          ..write('errorCode: $errorCode, ')
          ..write('errorDetail: $errorDetail, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class OutboxFiles extends Table with TableInfo<OutboxFiles, OutboxFileRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  OutboxFiles(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL PRIMARY KEY',
  );
  static const VerificationMeta _bytesMeta = const VerificationMeta('bytes');
  late final GeneratedColumn<Uint8List> bytes = GeneratedColumn<Uint8List>(
    'bytes',
    aliasedName,
    false,
    type: DriftSqlType.blob,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  @override
  List<GeneratedColumn> get $columns => [id, bytes];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'outbox_files';
  @override
  VerificationContext validateIntegrity(
    Insertable<OutboxFileRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('bytes')) {
      context.handle(
        _bytesMeta,
        bytes.isAcceptableOrUnknown(data['bytes']!, _bytesMeta),
      );
    } else if (isInserting) {
      context.missing(_bytesMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  OutboxFileRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return OutboxFileRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      bytes: attachedDatabase.typeMapping.read(
        DriftSqlType.blob,
        data['${effectivePrefix}bytes'],
      )!,
    );
  }

  @override
  OutboxFiles createAlias(String alias) {
    return OutboxFiles(attachedDatabase, alias);
  }

  @override
  bool get dontWriteConstraints => true;
}

class OutboxFileRow extends DataClass implements Insertable<OutboxFileRow> {
  final String id;
  final Uint8List bytes;
  const OutboxFileRow({required this.id, required this.bytes});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['bytes'] = Variable<Uint8List>(bytes);
    return map;
  }

  OutboxFilesCompanion toCompanion(bool nullToAbsent) {
    return OutboxFilesCompanion(id: Value(id), bytes: Value(bytes));
  }

  factory OutboxFileRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return OutboxFileRow(
      id: serializer.fromJson<String>(json['id']),
      bytes: serializer.fromJson<Uint8List>(json['bytes']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'bytes': serializer.toJson<Uint8List>(bytes),
    };
  }

  OutboxFileRow copyWith({String? id, Uint8List? bytes}) =>
      OutboxFileRow(id: id ?? this.id, bytes: bytes ?? this.bytes);
  OutboxFileRow copyWithCompanion(OutboxFilesCompanion data) {
    return OutboxFileRow(
      id: data.id.present ? data.id.value : this.id,
      bytes: data.bytes.present ? data.bytes.value : this.bytes,
    );
  }

  @override
  String toString() {
    return (StringBuffer('OutboxFileRow(')
          ..write('id: $id, ')
          ..write('bytes: $bytes')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, $driftBlobEquality.hash(bytes));
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is OutboxFileRow &&
          other.id == this.id &&
          $driftBlobEquality.equals(other.bytes, this.bytes));
}

class OutboxFilesCompanion extends UpdateCompanion<OutboxFileRow> {
  final Value<String> id;
  final Value<Uint8List> bytes;
  final Value<int> rowid;
  const OutboxFilesCompanion({
    this.id = const Value.absent(),
    this.bytes = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  OutboxFilesCompanion.insert({
    required String id,
    required Uint8List bytes,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       bytes = Value(bytes);
  static Insertable<OutboxFileRow> custom({
    Expression<String>? id,
    Expression<Uint8List>? bytes,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (bytes != null) 'bytes': bytes,
      if (rowid != null) 'rowid': rowid,
    });
  }

  OutboxFilesCompanion copyWith({
    Value<String>? id,
    Value<Uint8List>? bytes,
    Value<int>? rowid,
  }) {
    return OutboxFilesCompanion(
      id: id ?? this.id,
      bytes: bytes ?? this.bytes,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (bytes.present) {
      map['bytes'] = Variable<Uint8List>(bytes.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('OutboxFilesCompanion(')
          ..write('id: $id, ')
          ..write('bytes: $bytes, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$UserDatabase extends GeneratedDatabase {
  _$UserDatabase(QueryExecutor e) : super(e);
  late final Settings settings = Settings(this);
  late final FavoriteLists favoriteLists = FavoriteLists(this);
  late final FavoriteItems favoriteItems = FavoriteItems(this);
  late final Index favoriteItemsPlace = Index(
    'favorite_items_place',
    'CREATE INDEX favorite_items_place ON favorite_items (place_id)',
  );
  late final FavoritePoints favoritePoints = FavoritePoints(this);
  late final Index favoritePointsId = Index(
    'favorite_points_id',
    'CREATE INDEX favorite_points_id ON favorite_points (id)',
  );
  late final Vehicles vehicles = Vehicles(this);
  late final FavoriteSyncBase favoriteSyncBase = FavoriteSyncBase(this);
  late final Outbox outbox = Outbox(this);
  late final Index outboxOrder = Index(
    'outbox_order',
    'CREATE INDEX outbox_order ON outbox (state, created_at)',
  );
  late final OutboxFiles outboxFiles = OutboxFiles(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    settings,
    favoriteLists,
    favoriteItems,
    favoriteItemsPlace,
    favoritePoints,
    favoritePointsId,
    vehicles,
    favoriteSyncBase,
    outbox,
    outboxOrder,
    outboxFiles,
  ];
  @override
  StreamQueryUpdateRules get streamUpdateRules => const StreamQueryUpdateRules([
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'favorite_lists',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('favorite_items', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'favorite_lists',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('favorite_points', kind: UpdateKind.delete)],
    ),
  ]);
}
