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
  @override
  List<GeneratedColumn> get $columns => [id, name, isDefault, createdAt];
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
  const FavoriteListRow({
    required this.id,
    this.name,
    required this.isDefault,
    required this.createdAt,
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
    return map;
  }

  FavoriteListsCompanion toCompanion(bool nullToAbsent) {
    return FavoriteListsCompanion(
      id: Value(id),
      name: name == null && nullToAbsent ? const Value.absent() : Value(name),
      isDefault: Value(isDefault),
      createdAt: Value(createdAt),
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
    };
  }

  FavoriteListRow copyWith({
    int? id,
    Value<String?> name = const Value.absent(),
    bool? isDefault,
    int? createdAt,
  }) => FavoriteListRow(
    id: id ?? this.id,
    name: name.present ? name.value : this.name,
    isDefault: isDefault ?? this.isDefault,
    createdAt: createdAt ?? this.createdAt,
  );
  FavoriteListRow copyWithCompanion(FavoriteListsCompanion data) {
    return FavoriteListRow(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      isDefault: data.isDefault.present ? data.isDefault.value : this.isDefault,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('FavoriteListRow(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('isDefault: $isDefault, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, name, isDefault, createdAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is FavoriteListRow &&
          other.id == this.id &&
          other.name == this.name &&
          other.isDefault == this.isDefault &&
          other.createdAt == this.createdAt);
}

class FavoriteListsCompanion extends UpdateCompanion<FavoriteListRow> {
  final Value<int> id;
  final Value<String?> name;
  final Value<bool> isDefault;
  final Value<int> createdAt;
  const FavoriteListsCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.isDefault = const Value.absent(),
    this.createdAt = const Value.absent(),
  });
  FavoriteListsCompanion.insert({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.isDefault = const Value.absent(),
    required int createdAt,
  }) : createdAt = Value(createdAt);
  static Insertable<FavoriteListRow> custom({
    Expression<int>? id,
    Expression<String>? name,
    Expression<bool>? isDefault,
    Expression<int>? createdAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (isDefault != null) 'is_default': isDefault,
      if (createdAt != null) 'created_at': createdAt,
    });
  }

  FavoriteListsCompanion copyWith({
    Value<int>? id,
    Value<String?>? name,
    Value<bool>? isDefault,
    Value<int>? createdAt,
  }) {
    return FavoriteListsCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      isDefault: isDefault ?? this.isDefault,
      createdAt: createdAt ?? this.createdAt,
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
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('FavoriteListsCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('isDefault: $isDefault, ')
          ..write('createdAt: $createdAt')
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
  const VehicleRow({
    required this.id,
    required this.type,
    required this.towing,
    this.heightM,
    this.widthM,
    this.lengthM,
    this.weightT,
    required this.updatedAt,
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
  }) => VehicleRow(
    id: id ?? this.id,
    type: type ?? this.type,
    towing: towing ?? this.towing,
    heightM: heightM.present ? heightM.value : this.heightM,
    widthM: widthM.present ? widthM.value : this.widthM,
    lengthM: lengthM.present ? lengthM.value : this.lengthM,
    weightT: weightT.present ? weightT.value : this.weightT,
    updatedAt: updatedAt ?? this.updatedAt,
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
          ..write('updatedAt: $updatedAt')
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
          other.updatedAt == this.updatedAt);
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
  const VehiclesCompanion({
    this.id = const Value.absent(),
    this.type = const Value.absent(),
    this.towing = const Value.absent(),
    this.heightM = const Value.absent(),
    this.widthM = const Value.absent(),
    this.lengthM = const Value.absent(),
    this.weightT = const Value.absent(),
    this.updatedAt = const Value.absent(),
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
          ..write('updatedAt: $updatedAt')
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
  late final Vehicles vehicles = Vehicles(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    settings,
    favoriteLists,
    favoriteItems,
    favoriteItemsPlace,
    vehicles,
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
  ]);
}
