// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_db.dart';

// ignore_for_file: type=lint
class $CategoriesTable extends Categories
    with TableInfo<$CategoriesTable, CategoryRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CategoriesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _iconMeta = const VerificationMeta('icon');
  @override
  late final GeneratedColumn<int> icon = GeneratedColumn<int>(
    'icon',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _colorMeta = const VerificationMeta('color');
  @override
  late final GeneratedColumn<int> color = GeneratedColumn<int>(
    'color',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _budgetMeta = const VerificationMeta('budget');
  @override
  late final GeneratedColumn<double> budget = GeneratedColumn<double>(
    'budget',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sortOrderMeta = const VerificationMeta(
    'sortOrder',
  );
  @override
  late final GeneratedColumn<int> sortOrder = GeneratedColumn<int>(
    'sort_order',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _revMeta = const VerificationMeta('rev');
  @override
  late final GeneratedColumn<int> rev = GeneratedColumn<int>(
    'rev',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _revByMeta = const VerificationMeta('revBy');
  @override
  late final GeneratedColumn<String> revBy = GeneratedColumn<String>(
    'rev_by',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    name,
    icon,
    color,
    budget,
    sortOrder,
    rev,
    revBy,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'categories';
  @override
  VerificationContext validateIntegrity(
    Insertable<CategoryRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('icon')) {
      context.handle(
        _iconMeta,
        icon.isAcceptableOrUnknown(data['icon']!, _iconMeta),
      );
    } else if (isInserting) {
      context.missing(_iconMeta);
    }
    if (data.containsKey('color')) {
      context.handle(
        _colorMeta,
        color.isAcceptableOrUnknown(data['color']!, _colorMeta),
      );
    } else if (isInserting) {
      context.missing(_colorMeta);
    }
    if (data.containsKey('budget')) {
      context.handle(
        _budgetMeta,
        budget.isAcceptableOrUnknown(data['budget']!, _budgetMeta),
      );
    } else if (isInserting) {
      context.missing(_budgetMeta);
    }
    if (data.containsKey('sort_order')) {
      context.handle(
        _sortOrderMeta,
        sortOrder.isAcceptableOrUnknown(data['sort_order']!, _sortOrderMeta),
      );
    } else if (isInserting) {
      context.missing(_sortOrderMeta);
    }
    if (data.containsKey('rev')) {
      context.handle(
        _revMeta,
        rev.isAcceptableOrUnknown(data['rev']!, _revMeta),
      );
    }
    if (data.containsKey('rev_by')) {
      context.handle(
        _revByMeta,
        revBy.isAcceptableOrUnknown(data['rev_by']!, _revByMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  CategoryRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CategoryRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      icon: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}icon'],
      )!,
      color: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}color'],
      )!,
      budget: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}budget'],
      )!,
      sortOrder: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}sort_order'],
      )!,
      rev: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}rev'],
      )!,
      revBy: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}rev_by'],
      )!,
    );
  }

  @override
  $CategoriesTable createAlias(String alias) {
    return $CategoriesTable(attachedDatabase, alias);
  }
}

class CategoryRow extends DataClass implements Insertable<CategoryRow> {
  final String id;
  final String name;
  final int icon;
  final int color;
  final double budget;
  final int sortOrder;
  final int rev;
  final String revBy;
  const CategoryRow({
    required this.id,
    required this.name,
    required this.icon,
    required this.color,
    required this.budget,
    required this.sortOrder,
    required this.rev,
    required this.revBy,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['name'] = Variable<String>(name);
    map['icon'] = Variable<int>(icon);
    map['color'] = Variable<int>(color);
    map['budget'] = Variable<double>(budget);
    map['sort_order'] = Variable<int>(sortOrder);
    map['rev'] = Variable<int>(rev);
    map['rev_by'] = Variable<String>(revBy);
    return map;
  }

  CategoriesCompanion toCompanion(bool nullToAbsent) {
    return CategoriesCompanion(
      id: Value(id),
      name: Value(name),
      icon: Value(icon),
      color: Value(color),
      budget: Value(budget),
      sortOrder: Value(sortOrder),
      rev: Value(rev),
      revBy: Value(revBy),
    );
  }

  factory CategoryRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CategoryRow(
      id: serializer.fromJson<String>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      icon: serializer.fromJson<int>(json['icon']),
      color: serializer.fromJson<int>(json['color']),
      budget: serializer.fromJson<double>(json['budget']),
      sortOrder: serializer.fromJson<int>(json['sortOrder']),
      rev: serializer.fromJson<int>(json['rev']),
      revBy: serializer.fromJson<String>(json['revBy']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'name': serializer.toJson<String>(name),
      'icon': serializer.toJson<int>(icon),
      'color': serializer.toJson<int>(color),
      'budget': serializer.toJson<double>(budget),
      'sortOrder': serializer.toJson<int>(sortOrder),
      'rev': serializer.toJson<int>(rev),
      'revBy': serializer.toJson<String>(revBy),
    };
  }

  CategoryRow copyWith({
    String? id,
    String? name,
    int? icon,
    int? color,
    double? budget,
    int? sortOrder,
    int? rev,
    String? revBy,
  }) => CategoryRow(
    id: id ?? this.id,
    name: name ?? this.name,
    icon: icon ?? this.icon,
    color: color ?? this.color,
    budget: budget ?? this.budget,
    sortOrder: sortOrder ?? this.sortOrder,
    rev: rev ?? this.rev,
    revBy: revBy ?? this.revBy,
  );
  CategoryRow copyWithCompanion(CategoriesCompanion data) {
    return CategoryRow(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      icon: data.icon.present ? data.icon.value : this.icon,
      color: data.color.present ? data.color.value : this.color,
      budget: data.budget.present ? data.budget.value : this.budget,
      sortOrder: data.sortOrder.present ? data.sortOrder.value : this.sortOrder,
      rev: data.rev.present ? data.rev.value : this.rev,
      revBy: data.revBy.present ? data.revBy.value : this.revBy,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CategoryRow(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('icon: $icon, ')
          ..write('color: $color, ')
          ..write('budget: $budget, ')
          ..write('sortOrder: $sortOrder, ')
          ..write('rev: $rev, ')
          ..write('revBy: $revBy')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, name, icon, color, budget, sortOrder, rev, revBy);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CategoryRow &&
          other.id == this.id &&
          other.name == this.name &&
          other.icon == this.icon &&
          other.color == this.color &&
          other.budget == this.budget &&
          other.sortOrder == this.sortOrder &&
          other.rev == this.rev &&
          other.revBy == this.revBy);
}

class CategoriesCompanion extends UpdateCompanion<CategoryRow> {
  final Value<String> id;
  final Value<String> name;
  final Value<int> icon;
  final Value<int> color;
  final Value<double> budget;
  final Value<int> sortOrder;
  final Value<int> rev;
  final Value<String> revBy;
  final Value<int> rowid;
  const CategoriesCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.icon = const Value.absent(),
    this.color = const Value.absent(),
    this.budget = const Value.absent(),
    this.sortOrder = const Value.absent(),
    this.rev = const Value.absent(),
    this.revBy = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CategoriesCompanion.insert({
    required String id,
    required String name,
    required int icon,
    required int color,
    required double budget,
    required int sortOrder,
    this.rev = const Value.absent(),
    this.revBy = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       name = Value(name),
       icon = Value(icon),
       color = Value(color),
       budget = Value(budget),
       sortOrder = Value(sortOrder);
  static Insertable<CategoryRow> custom({
    Expression<String>? id,
    Expression<String>? name,
    Expression<int>? icon,
    Expression<int>? color,
    Expression<double>? budget,
    Expression<int>? sortOrder,
    Expression<int>? rev,
    Expression<String>? revBy,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (icon != null) 'icon': icon,
      if (color != null) 'color': color,
      if (budget != null) 'budget': budget,
      if (sortOrder != null) 'sort_order': sortOrder,
      if (rev != null) 'rev': rev,
      if (revBy != null) 'rev_by': revBy,
      if (rowid != null) 'rowid': rowid,
    });
  }

  CategoriesCompanion copyWith({
    Value<String>? id,
    Value<String>? name,
    Value<int>? icon,
    Value<int>? color,
    Value<double>? budget,
    Value<int>? sortOrder,
    Value<int>? rev,
    Value<String>? revBy,
    Value<int>? rowid,
  }) {
    return CategoriesCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      icon: icon ?? this.icon,
      color: color ?? this.color,
      budget: budget ?? this.budget,
      sortOrder: sortOrder ?? this.sortOrder,
      rev: rev ?? this.rev,
      revBy: revBy ?? this.revBy,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (icon.present) {
      map['icon'] = Variable<int>(icon.value);
    }
    if (color.present) {
      map['color'] = Variable<int>(color.value);
    }
    if (budget.present) {
      map['budget'] = Variable<double>(budget.value);
    }
    if (sortOrder.present) {
      map['sort_order'] = Variable<int>(sortOrder.value);
    }
    if (rev.present) {
      map['rev'] = Variable<int>(rev.value);
    }
    if (revBy.present) {
      map['rev_by'] = Variable<String>(revBy.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CategoriesCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('icon: $icon, ')
          ..write('color: $color, ')
          ..write('budget: $budget, ')
          ..write('sortOrder: $sortOrder, ')
          ..write('rev: $rev, ')
          ..write('revBy: $revBy, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $TransactionsTable extends Transactions
    with TableInfo<$TransactionsTable, TxnRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $TransactionsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _typeMeta = const VerificationMeta('type');
  @override
  late final GeneratedColumn<String> type = GeneratedColumn<String>(
    'type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _amountMeta = const VerificationMeta('amount');
  @override
  late final GeneratedColumn<double> amount = GeneratedColumn<double>(
    'amount',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _categoryIdMeta = const VerificationMeta(
    'categoryId',
  );
  @override
  late final GeneratedColumn<String> categoryId = GeneratedColumn<String>(
    'category_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES categories (id)',
    ),
  );
  static const VerificationMeta _dateMeta = const VerificationMeta('date');
  @override
  late final GeneratedColumn<int> date = GeneratedColumn<int>(
    'date',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _noteMeta = const VerificationMeta('note');
  @override
  late final GeneratedColumn<String> note = GeneratedColumn<String>(
    'note',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _modeMeta = const VerificationMeta('mode');
  @override
  late final GeneratedColumn<String> mode = GeneratedColumn<String>(
    'mode',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _projectIdMeta = const VerificationMeta(
    'projectId',
  );
  @override
  late final GeneratedColumn<String> projectId = GeneratedColumn<String>(
    'project_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _revMeta = const VerificationMeta('rev');
  @override
  late final GeneratedColumn<int> rev = GeneratedColumn<int>(
    'rev',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _revByMeta = const VerificationMeta('revBy');
  @override
  late final GeneratedColumn<String> revBy = GeneratedColumn<String>(
    'rev_by',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    type,
    amount,
    categoryId,
    date,
    note,
    mode,
    projectId,
    rev,
    revBy,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'transactions';
  @override
  VerificationContext validateIntegrity(
    Insertable<TxnRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('type')) {
      context.handle(
        _typeMeta,
        type.isAcceptableOrUnknown(data['type']!, _typeMeta),
      );
    } else if (isInserting) {
      context.missing(_typeMeta);
    }
    if (data.containsKey('amount')) {
      context.handle(
        _amountMeta,
        amount.isAcceptableOrUnknown(data['amount']!, _amountMeta),
      );
    } else if (isInserting) {
      context.missing(_amountMeta);
    }
    if (data.containsKey('category_id')) {
      context.handle(
        _categoryIdMeta,
        categoryId.isAcceptableOrUnknown(data['category_id']!, _categoryIdMeta),
      );
    } else if (isInserting) {
      context.missing(_categoryIdMeta);
    }
    if (data.containsKey('date')) {
      context.handle(
        _dateMeta,
        date.isAcceptableOrUnknown(data['date']!, _dateMeta),
      );
    } else if (isInserting) {
      context.missing(_dateMeta);
    }
    if (data.containsKey('note')) {
      context.handle(
        _noteMeta,
        note.isAcceptableOrUnknown(data['note']!, _noteMeta),
      );
    } else if (isInserting) {
      context.missing(_noteMeta);
    }
    if (data.containsKey('mode')) {
      context.handle(
        _modeMeta,
        mode.isAcceptableOrUnknown(data['mode']!, _modeMeta),
      );
    } else if (isInserting) {
      context.missing(_modeMeta);
    }
    if (data.containsKey('project_id')) {
      context.handle(
        _projectIdMeta,
        projectId.isAcceptableOrUnknown(data['project_id']!, _projectIdMeta),
      );
    } else if (isInserting) {
      context.missing(_projectIdMeta);
    }
    if (data.containsKey('rev')) {
      context.handle(
        _revMeta,
        rev.isAcceptableOrUnknown(data['rev']!, _revMeta),
      );
    }
    if (data.containsKey('rev_by')) {
      context.handle(
        _revByMeta,
        revBy.isAcceptableOrUnknown(data['rev_by']!, _revByMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  TxnRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return TxnRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      type: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}type'],
      )!,
      amount: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}amount'],
      )!,
      categoryId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}category_id'],
      )!,
      date: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}date'],
      )!,
      note: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}note'],
      )!,
      mode: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}mode'],
      )!,
      projectId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}project_id'],
      )!,
      rev: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}rev'],
      )!,
      revBy: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}rev_by'],
      )!,
    );
  }

  @override
  $TransactionsTable createAlias(String alias) {
    return $TransactionsTable(attachedDatabase, alias);
  }
}

class TxnRow extends DataClass implements Insertable<TxnRow> {
  final String id;
  final String type;
  final double amount;
  final String categoryId;
  final int date;
  final String note;
  final String mode;
  final String projectId;
  final int rev;
  final String revBy;
  const TxnRow({
    required this.id,
    required this.type,
    required this.amount,
    required this.categoryId,
    required this.date,
    required this.note,
    required this.mode,
    required this.projectId,
    required this.rev,
    required this.revBy,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['type'] = Variable<String>(type);
    map['amount'] = Variable<double>(amount);
    map['category_id'] = Variable<String>(categoryId);
    map['date'] = Variable<int>(date);
    map['note'] = Variable<String>(note);
    map['mode'] = Variable<String>(mode);
    map['project_id'] = Variable<String>(projectId);
    map['rev'] = Variable<int>(rev);
    map['rev_by'] = Variable<String>(revBy);
    return map;
  }

  TransactionsCompanion toCompanion(bool nullToAbsent) {
    return TransactionsCompanion(
      id: Value(id),
      type: Value(type),
      amount: Value(amount),
      categoryId: Value(categoryId),
      date: Value(date),
      note: Value(note),
      mode: Value(mode),
      projectId: Value(projectId),
      rev: Value(rev),
      revBy: Value(revBy),
    );
  }

  factory TxnRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return TxnRow(
      id: serializer.fromJson<String>(json['id']),
      type: serializer.fromJson<String>(json['type']),
      amount: serializer.fromJson<double>(json['amount']),
      categoryId: serializer.fromJson<String>(json['categoryId']),
      date: serializer.fromJson<int>(json['date']),
      note: serializer.fromJson<String>(json['note']),
      mode: serializer.fromJson<String>(json['mode']),
      projectId: serializer.fromJson<String>(json['projectId']),
      rev: serializer.fromJson<int>(json['rev']),
      revBy: serializer.fromJson<String>(json['revBy']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'type': serializer.toJson<String>(type),
      'amount': serializer.toJson<double>(amount),
      'categoryId': serializer.toJson<String>(categoryId),
      'date': serializer.toJson<int>(date),
      'note': serializer.toJson<String>(note),
      'mode': serializer.toJson<String>(mode),
      'projectId': serializer.toJson<String>(projectId),
      'rev': serializer.toJson<int>(rev),
      'revBy': serializer.toJson<String>(revBy),
    };
  }

  TxnRow copyWith({
    String? id,
    String? type,
    double? amount,
    String? categoryId,
    int? date,
    String? note,
    String? mode,
    String? projectId,
    int? rev,
    String? revBy,
  }) => TxnRow(
    id: id ?? this.id,
    type: type ?? this.type,
    amount: amount ?? this.amount,
    categoryId: categoryId ?? this.categoryId,
    date: date ?? this.date,
    note: note ?? this.note,
    mode: mode ?? this.mode,
    projectId: projectId ?? this.projectId,
    rev: rev ?? this.rev,
    revBy: revBy ?? this.revBy,
  );
  TxnRow copyWithCompanion(TransactionsCompanion data) {
    return TxnRow(
      id: data.id.present ? data.id.value : this.id,
      type: data.type.present ? data.type.value : this.type,
      amount: data.amount.present ? data.amount.value : this.amount,
      categoryId: data.categoryId.present
          ? data.categoryId.value
          : this.categoryId,
      date: data.date.present ? data.date.value : this.date,
      note: data.note.present ? data.note.value : this.note,
      mode: data.mode.present ? data.mode.value : this.mode,
      projectId: data.projectId.present ? data.projectId.value : this.projectId,
      rev: data.rev.present ? data.rev.value : this.rev,
      revBy: data.revBy.present ? data.revBy.value : this.revBy,
    );
  }

  @override
  String toString() {
    return (StringBuffer('TxnRow(')
          ..write('id: $id, ')
          ..write('type: $type, ')
          ..write('amount: $amount, ')
          ..write('categoryId: $categoryId, ')
          ..write('date: $date, ')
          ..write('note: $note, ')
          ..write('mode: $mode, ')
          ..write('projectId: $projectId, ')
          ..write('rev: $rev, ')
          ..write('revBy: $revBy')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    type,
    amount,
    categoryId,
    date,
    note,
    mode,
    projectId,
    rev,
    revBy,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is TxnRow &&
          other.id == this.id &&
          other.type == this.type &&
          other.amount == this.amount &&
          other.categoryId == this.categoryId &&
          other.date == this.date &&
          other.note == this.note &&
          other.mode == this.mode &&
          other.projectId == this.projectId &&
          other.rev == this.rev &&
          other.revBy == this.revBy);
}

class TransactionsCompanion extends UpdateCompanion<TxnRow> {
  final Value<String> id;
  final Value<String> type;
  final Value<double> amount;
  final Value<String> categoryId;
  final Value<int> date;
  final Value<String> note;
  final Value<String> mode;
  final Value<String> projectId;
  final Value<int> rev;
  final Value<String> revBy;
  final Value<int> rowid;
  const TransactionsCompanion({
    this.id = const Value.absent(),
    this.type = const Value.absent(),
    this.amount = const Value.absent(),
    this.categoryId = const Value.absent(),
    this.date = const Value.absent(),
    this.note = const Value.absent(),
    this.mode = const Value.absent(),
    this.projectId = const Value.absent(),
    this.rev = const Value.absent(),
    this.revBy = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  TransactionsCompanion.insert({
    required String id,
    required String type,
    required double amount,
    required String categoryId,
    required int date,
    required String note,
    required String mode,
    required String projectId,
    this.rev = const Value.absent(),
    this.revBy = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       type = Value(type),
       amount = Value(amount),
       categoryId = Value(categoryId),
       date = Value(date),
       note = Value(note),
       mode = Value(mode),
       projectId = Value(projectId);
  static Insertable<TxnRow> custom({
    Expression<String>? id,
    Expression<String>? type,
    Expression<double>? amount,
    Expression<String>? categoryId,
    Expression<int>? date,
    Expression<String>? note,
    Expression<String>? mode,
    Expression<String>? projectId,
    Expression<int>? rev,
    Expression<String>? revBy,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (type != null) 'type': type,
      if (amount != null) 'amount': amount,
      if (categoryId != null) 'category_id': categoryId,
      if (date != null) 'date': date,
      if (note != null) 'note': note,
      if (mode != null) 'mode': mode,
      if (projectId != null) 'project_id': projectId,
      if (rev != null) 'rev': rev,
      if (revBy != null) 'rev_by': revBy,
      if (rowid != null) 'rowid': rowid,
    });
  }

  TransactionsCompanion copyWith({
    Value<String>? id,
    Value<String>? type,
    Value<double>? amount,
    Value<String>? categoryId,
    Value<int>? date,
    Value<String>? note,
    Value<String>? mode,
    Value<String>? projectId,
    Value<int>? rev,
    Value<String>? revBy,
    Value<int>? rowid,
  }) {
    return TransactionsCompanion(
      id: id ?? this.id,
      type: type ?? this.type,
      amount: amount ?? this.amount,
      categoryId: categoryId ?? this.categoryId,
      date: date ?? this.date,
      note: note ?? this.note,
      mode: mode ?? this.mode,
      projectId: projectId ?? this.projectId,
      rev: rev ?? this.rev,
      revBy: revBy ?? this.revBy,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (type.present) {
      map['type'] = Variable<String>(type.value);
    }
    if (amount.present) {
      map['amount'] = Variable<double>(amount.value);
    }
    if (categoryId.present) {
      map['category_id'] = Variable<String>(categoryId.value);
    }
    if (date.present) {
      map['date'] = Variable<int>(date.value);
    }
    if (note.present) {
      map['note'] = Variable<String>(note.value);
    }
    if (mode.present) {
      map['mode'] = Variable<String>(mode.value);
    }
    if (projectId.present) {
      map['project_id'] = Variable<String>(projectId.value);
    }
    if (rev.present) {
      map['rev'] = Variable<int>(rev.value);
    }
    if (revBy.present) {
      map['rev_by'] = Variable<String>(revBy.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('TransactionsCompanion(')
          ..write('id: $id, ')
          ..write('type: $type, ')
          ..write('amount: $amount, ')
          ..write('categoryId: $categoryId, ')
          ..write('date: $date, ')
          ..write('note: $note, ')
          ..write('mode: $mode, ')
          ..write('projectId: $projectId, ')
          ..write('rev: $rev, ')
          ..write('revBy: $revBy, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ProjectsTable extends Projects
    with TableInfo<$ProjectsTable, ProjectRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ProjectsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _noteMeta = const VerificationMeta('note');
  @override
  late final GeneratedColumn<String> note = GeneratedColumn<String>(
    'note',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _createdMeta = const VerificationMeta(
    'created',
  );
  @override
  late final GeneratedColumn<int> created = GeneratedColumn<int>(
    'created',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _iconMeta = const VerificationMeta('icon');
  @override
  late final GeneratedColumn<int> icon = GeneratedColumn<int>(
    'icon',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _colorMeta = const VerificationMeta('color');
  @override
  late final GeneratedColumn<int> color = GeneratedColumn<int>(
    'color',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _revMeta = const VerificationMeta('rev');
  @override
  late final GeneratedColumn<int> rev = GeneratedColumn<int>(
    'rev',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _revByMeta = const VerificationMeta('revBy');
  @override
  late final GeneratedColumn<String> revBy = GeneratedColumn<String>(
    'rev_by',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    name,
    note,
    created,
    icon,
    color,
    rev,
    revBy,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'projects';
  @override
  VerificationContext validateIntegrity(
    Insertable<ProjectRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
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
    } else if (isInserting) {
      context.missing(_noteMeta);
    }
    if (data.containsKey('created')) {
      context.handle(
        _createdMeta,
        created.isAcceptableOrUnknown(data['created']!, _createdMeta),
      );
    } else if (isInserting) {
      context.missing(_createdMeta);
    }
    if (data.containsKey('icon')) {
      context.handle(
        _iconMeta,
        icon.isAcceptableOrUnknown(data['icon']!, _iconMeta),
      );
    } else if (isInserting) {
      context.missing(_iconMeta);
    }
    if (data.containsKey('color')) {
      context.handle(
        _colorMeta,
        color.isAcceptableOrUnknown(data['color']!, _colorMeta),
      );
    } else if (isInserting) {
      context.missing(_colorMeta);
    }
    if (data.containsKey('rev')) {
      context.handle(
        _revMeta,
        rev.isAcceptableOrUnknown(data['rev']!, _revMeta),
      );
    }
    if (data.containsKey('rev_by')) {
      context.handle(
        _revByMeta,
        revBy.isAcceptableOrUnknown(data['rev_by']!, _revByMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  ProjectRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ProjectRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      note: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}note'],
      )!,
      created: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}created'],
      )!,
      icon: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}icon'],
      )!,
      color: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}color'],
      )!,
      rev: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}rev'],
      )!,
      revBy: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}rev_by'],
      )!,
    );
  }

  @override
  $ProjectsTable createAlias(String alias) {
    return $ProjectsTable(attachedDatabase, alias);
  }
}

class ProjectRow extends DataClass implements Insertable<ProjectRow> {
  final String id;
  final String name;
  final String note;
  final int created;
  final int icon;
  final int color;
  final int rev;
  final String revBy;
  const ProjectRow({
    required this.id,
    required this.name,
    required this.note,
    required this.created,
    required this.icon,
    required this.color,
    required this.rev,
    required this.revBy,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['name'] = Variable<String>(name);
    map['note'] = Variable<String>(note);
    map['created'] = Variable<int>(created);
    map['icon'] = Variable<int>(icon);
    map['color'] = Variable<int>(color);
    map['rev'] = Variable<int>(rev);
    map['rev_by'] = Variable<String>(revBy);
    return map;
  }

  ProjectsCompanion toCompanion(bool nullToAbsent) {
    return ProjectsCompanion(
      id: Value(id),
      name: Value(name),
      note: Value(note),
      created: Value(created),
      icon: Value(icon),
      color: Value(color),
      rev: Value(rev),
      revBy: Value(revBy),
    );
  }

  factory ProjectRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ProjectRow(
      id: serializer.fromJson<String>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      note: serializer.fromJson<String>(json['note']),
      created: serializer.fromJson<int>(json['created']),
      icon: serializer.fromJson<int>(json['icon']),
      color: serializer.fromJson<int>(json['color']),
      rev: serializer.fromJson<int>(json['rev']),
      revBy: serializer.fromJson<String>(json['revBy']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'name': serializer.toJson<String>(name),
      'note': serializer.toJson<String>(note),
      'created': serializer.toJson<int>(created),
      'icon': serializer.toJson<int>(icon),
      'color': serializer.toJson<int>(color),
      'rev': serializer.toJson<int>(rev),
      'revBy': serializer.toJson<String>(revBy),
    };
  }

  ProjectRow copyWith({
    String? id,
    String? name,
    String? note,
    int? created,
    int? icon,
    int? color,
    int? rev,
    String? revBy,
  }) => ProjectRow(
    id: id ?? this.id,
    name: name ?? this.name,
    note: note ?? this.note,
    created: created ?? this.created,
    icon: icon ?? this.icon,
    color: color ?? this.color,
    rev: rev ?? this.rev,
    revBy: revBy ?? this.revBy,
  );
  ProjectRow copyWithCompanion(ProjectsCompanion data) {
    return ProjectRow(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      note: data.note.present ? data.note.value : this.note,
      created: data.created.present ? data.created.value : this.created,
      icon: data.icon.present ? data.icon.value : this.icon,
      color: data.color.present ? data.color.value : this.color,
      rev: data.rev.present ? data.rev.value : this.rev,
      revBy: data.revBy.present ? data.revBy.value : this.revBy,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ProjectRow(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('note: $note, ')
          ..write('created: $created, ')
          ..write('icon: $icon, ')
          ..write('color: $color, ')
          ..write('rev: $rev, ')
          ..write('revBy: $revBy')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, name, note, created, icon, color, rev, revBy);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ProjectRow &&
          other.id == this.id &&
          other.name == this.name &&
          other.note == this.note &&
          other.created == this.created &&
          other.icon == this.icon &&
          other.color == this.color &&
          other.rev == this.rev &&
          other.revBy == this.revBy);
}

class ProjectsCompanion extends UpdateCompanion<ProjectRow> {
  final Value<String> id;
  final Value<String> name;
  final Value<String> note;
  final Value<int> created;
  final Value<int> icon;
  final Value<int> color;
  final Value<int> rev;
  final Value<String> revBy;
  final Value<int> rowid;
  const ProjectsCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.note = const Value.absent(),
    this.created = const Value.absent(),
    this.icon = const Value.absent(),
    this.color = const Value.absent(),
    this.rev = const Value.absent(),
    this.revBy = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ProjectsCompanion.insert({
    required String id,
    required String name,
    required String note,
    required int created,
    required int icon,
    required int color,
    this.rev = const Value.absent(),
    this.revBy = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       name = Value(name),
       note = Value(note),
       created = Value(created),
       icon = Value(icon),
       color = Value(color);
  static Insertable<ProjectRow> custom({
    Expression<String>? id,
    Expression<String>? name,
    Expression<String>? note,
    Expression<int>? created,
    Expression<int>? icon,
    Expression<int>? color,
    Expression<int>? rev,
    Expression<String>? revBy,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (note != null) 'note': note,
      if (created != null) 'created': created,
      if (icon != null) 'icon': icon,
      if (color != null) 'color': color,
      if (rev != null) 'rev': rev,
      if (revBy != null) 'rev_by': revBy,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ProjectsCompanion copyWith({
    Value<String>? id,
    Value<String>? name,
    Value<String>? note,
    Value<int>? created,
    Value<int>? icon,
    Value<int>? color,
    Value<int>? rev,
    Value<String>? revBy,
    Value<int>? rowid,
  }) {
    return ProjectsCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      note: note ?? this.note,
      created: created ?? this.created,
      icon: icon ?? this.icon,
      color: color ?? this.color,
      rev: rev ?? this.rev,
      revBy: revBy ?? this.revBy,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (note.present) {
      map['note'] = Variable<String>(note.value);
    }
    if (created.present) {
      map['created'] = Variable<int>(created.value);
    }
    if (icon.present) {
      map['icon'] = Variable<int>(icon.value);
    }
    if (color.present) {
      map['color'] = Variable<int>(color.value);
    }
    if (rev.present) {
      map['rev'] = Variable<int>(rev.value);
    }
    if (revBy.present) {
      map['rev_by'] = Variable<String>(revBy.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ProjectsCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('note: $note, ')
          ..write('created: $created, ')
          ..write('icon: $icon, ')
          ..write('color: $color, ')
          ..write('rev: $rev, ')
          ..write('revBy: $revBy, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $LoansTable extends Loans with TableInfo<$LoansTable, LoanRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $LoansTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _personMeta = const VerificationMeta('person');
  @override
  late final GeneratedColumn<String> person = GeneratedColumn<String>(
    'person',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _kindMeta = const VerificationMeta('kind');
  @override
  late final GeneratedColumn<String> kind = GeneratedColumn<String>(
    'kind',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _principalMeta = const VerificationMeta(
    'principal',
  );
  @override
  late final GeneratedColumn<double> principal = GeneratedColumn<double>(
    'principal',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _dateLentMeta = const VerificationMeta(
    'dateLent',
  );
  @override
  late final GeneratedColumn<int> dateLent = GeneratedColumn<int>(
    'date_lent',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _dueDateMeta = const VerificationMeta(
    'dueDate',
  );
  @override
  late final GeneratedColumn<int> dueDate = GeneratedColumn<int>(
    'due_date',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _noteMeta = const VerificationMeta('note');
  @override
  late final GeneratedColumn<String> note = GeneratedColumn<String>(
    'note',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _remindAtMeta = const VerificationMeta(
    'remindAt',
  );
  @override
  late final GeneratedColumn<int> remindAt = GeneratedColumn<int>(
    'remind_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _revMeta = const VerificationMeta('rev');
  @override
  late final GeneratedColumn<int> rev = GeneratedColumn<int>(
    'rev',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _revByMeta = const VerificationMeta('revBy');
  @override
  late final GeneratedColumn<String> revBy = GeneratedColumn<String>(
    'rev_by',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    person,
    kind,
    principal,
    dateLent,
    dueDate,
    note,
    remindAt,
    rev,
    revBy,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'loans';
  @override
  VerificationContext validateIntegrity(
    Insertable<LoanRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('person')) {
      context.handle(
        _personMeta,
        person.isAcceptableOrUnknown(data['person']!, _personMeta),
      );
    } else if (isInserting) {
      context.missing(_personMeta);
    }
    if (data.containsKey('kind')) {
      context.handle(
        _kindMeta,
        kind.isAcceptableOrUnknown(data['kind']!, _kindMeta),
      );
    } else if (isInserting) {
      context.missing(_kindMeta);
    }
    if (data.containsKey('principal')) {
      context.handle(
        _principalMeta,
        principal.isAcceptableOrUnknown(data['principal']!, _principalMeta),
      );
    } else if (isInserting) {
      context.missing(_principalMeta);
    }
    if (data.containsKey('date_lent')) {
      context.handle(
        _dateLentMeta,
        dateLent.isAcceptableOrUnknown(data['date_lent']!, _dateLentMeta),
      );
    } else if (isInserting) {
      context.missing(_dateLentMeta);
    }
    if (data.containsKey('due_date')) {
      context.handle(
        _dueDateMeta,
        dueDate.isAcceptableOrUnknown(data['due_date']!, _dueDateMeta),
      );
    }
    if (data.containsKey('note')) {
      context.handle(
        _noteMeta,
        note.isAcceptableOrUnknown(data['note']!, _noteMeta),
      );
    } else if (isInserting) {
      context.missing(_noteMeta);
    }
    if (data.containsKey('remind_at')) {
      context.handle(
        _remindAtMeta,
        remindAt.isAcceptableOrUnknown(data['remind_at']!, _remindAtMeta),
      );
    } else if (isInserting) {
      context.missing(_remindAtMeta);
    }
    if (data.containsKey('rev')) {
      context.handle(
        _revMeta,
        rev.isAcceptableOrUnknown(data['rev']!, _revMeta),
      );
    }
    if (data.containsKey('rev_by')) {
      context.handle(
        _revByMeta,
        revBy.isAcceptableOrUnknown(data['rev_by']!, _revByMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  LoanRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return LoanRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      person: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}person'],
      )!,
      kind: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}kind'],
      )!,
      principal: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}principal'],
      )!,
      dateLent: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}date_lent'],
      )!,
      dueDate: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}due_date'],
      ),
      note: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}note'],
      )!,
      remindAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}remind_at'],
      )!,
      rev: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}rev'],
      )!,
      revBy: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}rev_by'],
      )!,
    );
  }

  @override
  $LoansTable createAlias(String alias) {
    return $LoansTable(attachedDatabase, alias);
  }
}

class LoanRow extends DataClass implements Insertable<LoanRow> {
  final String id;
  final String person;
  final String kind;
  final double principal;
  final int dateLent;
  final int? dueDate;
  final String note;
  final int remindAt;
  final int rev;
  final String revBy;
  const LoanRow({
    required this.id,
    required this.person,
    required this.kind,
    required this.principal,
    required this.dateLent,
    this.dueDate,
    required this.note,
    required this.remindAt,
    required this.rev,
    required this.revBy,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['person'] = Variable<String>(person);
    map['kind'] = Variable<String>(kind);
    map['principal'] = Variable<double>(principal);
    map['date_lent'] = Variable<int>(dateLent);
    if (!nullToAbsent || dueDate != null) {
      map['due_date'] = Variable<int>(dueDate);
    }
    map['note'] = Variable<String>(note);
    map['remind_at'] = Variable<int>(remindAt);
    map['rev'] = Variable<int>(rev);
    map['rev_by'] = Variable<String>(revBy);
    return map;
  }

  LoansCompanion toCompanion(bool nullToAbsent) {
    return LoansCompanion(
      id: Value(id),
      person: Value(person),
      kind: Value(kind),
      principal: Value(principal),
      dateLent: Value(dateLent),
      dueDate: dueDate == null && nullToAbsent
          ? const Value.absent()
          : Value(dueDate),
      note: Value(note),
      remindAt: Value(remindAt),
      rev: Value(rev),
      revBy: Value(revBy),
    );
  }

  factory LoanRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return LoanRow(
      id: serializer.fromJson<String>(json['id']),
      person: serializer.fromJson<String>(json['person']),
      kind: serializer.fromJson<String>(json['kind']),
      principal: serializer.fromJson<double>(json['principal']),
      dateLent: serializer.fromJson<int>(json['dateLent']),
      dueDate: serializer.fromJson<int?>(json['dueDate']),
      note: serializer.fromJson<String>(json['note']),
      remindAt: serializer.fromJson<int>(json['remindAt']),
      rev: serializer.fromJson<int>(json['rev']),
      revBy: serializer.fromJson<String>(json['revBy']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'person': serializer.toJson<String>(person),
      'kind': serializer.toJson<String>(kind),
      'principal': serializer.toJson<double>(principal),
      'dateLent': serializer.toJson<int>(dateLent),
      'dueDate': serializer.toJson<int?>(dueDate),
      'note': serializer.toJson<String>(note),
      'remindAt': serializer.toJson<int>(remindAt),
      'rev': serializer.toJson<int>(rev),
      'revBy': serializer.toJson<String>(revBy),
    };
  }

  LoanRow copyWith({
    String? id,
    String? person,
    String? kind,
    double? principal,
    int? dateLent,
    Value<int?> dueDate = const Value.absent(),
    String? note,
    int? remindAt,
    int? rev,
    String? revBy,
  }) => LoanRow(
    id: id ?? this.id,
    person: person ?? this.person,
    kind: kind ?? this.kind,
    principal: principal ?? this.principal,
    dateLent: dateLent ?? this.dateLent,
    dueDate: dueDate.present ? dueDate.value : this.dueDate,
    note: note ?? this.note,
    remindAt: remindAt ?? this.remindAt,
    rev: rev ?? this.rev,
    revBy: revBy ?? this.revBy,
  );
  LoanRow copyWithCompanion(LoansCompanion data) {
    return LoanRow(
      id: data.id.present ? data.id.value : this.id,
      person: data.person.present ? data.person.value : this.person,
      kind: data.kind.present ? data.kind.value : this.kind,
      principal: data.principal.present ? data.principal.value : this.principal,
      dateLent: data.dateLent.present ? data.dateLent.value : this.dateLent,
      dueDate: data.dueDate.present ? data.dueDate.value : this.dueDate,
      note: data.note.present ? data.note.value : this.note,
      remindAt: data.remindAt.present ? data.remindAt.value : this.remindAt,
      rev: data.rev.present ? data.rev.value : this.rev,
      revBy: data.revBy.present ? data.revBy.value : this.revBy,
    );
  }

  @override
  String toString() {
    return (StringBuffer('LoanRow(')
          ..write('id: $id, ')
          ..write('person: $person, ')
          ..write('kind: $kind, ')
          ..write('principal: $principal, ')
          ..write('dateLent: $dateLent, ')
          ..write('dueDate: $dueDate, ')
          ..write('note: $note, ')
          ..write('remindAt: $remindAt, ')
          ..write('rev: $rev, ')
          ..write('revBy: $revBy')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    person,
    kind,
    principal,
    dateLent,
    dueDate,
    note,
    remindAt,
    rev,
    revBy,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is LoanRow &&
          other.id == this.id &&
          other.person == this.person &&
          other.kind == this.kind &&
          other.principal == this.principal &&
          other.dateLent == this.dateLent &&
          other.dueDate == this.dueDate &&
          other.note == this.note &&
          other.remindAt == this.remindAt &&
          other.rev == this.rev &&
          other.revBy == this.revBy);
}

class LoansCompanion extends UpdateCompanion<LoanRow> {
  final Value<String> id;
  final Value<String> person;
  final Value<String> kind;
  final Value<double> principal;
  final Value<int> dateLent;
  final Value<int?> dueDate;
  final Value<String> note;
  final Value<int> remindAt;
  final Value<int> rev;
  final Value<String> revBy;
  final Value<int> rowid;
  const LoansCompanion({
    this.id = const Value.absent(),
    this.person = const Value.absent(),
    this.kind = const Value.absent(),
    this.principal = const Value.absent(),
    this.dateLent = const Value.absent(),
    this.dueDate = const Value.absent(),
    this.note = const Value.absent(),
    this.remindAt = const Value.absent(),
    this.rev = const Value.absent(),
    this.revBy = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  LoansCompanion.insert({
    required String id,
    required String person,
    required String kind,
    required double principal,
    required int dateLent,
    this.dueDate = const Value.absent(),
    required String note,
    required int remindAt,
    this.rev = const Value.absent(),
    this.revBy = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       person = Value(person),
       kind = Value(kind),
       principal = Value(principal),
       dateLent = Value(dateLent),
       note = Value(note),
       remindAt = Value(remindAt);
  static Insertable<LoanRow> custom({
    Expression<String>? id,
    Expression<String>? person,
    Expression<String>? kind,
    Expression<double>? principal,
    Expression<int>? dateLent,
    Expression<int>? dueDate,
    Expression<String>? note,
    Expression<int>? remindAt,
    Expression<int>? rev,
    Expression<String>? revBy,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (person != null) 'person': person,
      if (kind != null) 'kind': kind,
      if (principal != null) 'principal': principal,
      if (dateLent != null) 'date_lent': dateLent,
      if (dueDate != null) 'due_date': dueDate,
      if (note != null) 'note': note,
      if (remindAt != null) 'remind_at': remindAt,
      if (rev != null) 'rev': rev,
      if (revBy != null) 'rev_by': revBy,
      if (rowid != null) 'rowid': rowid,
    });
  }

  LoansCompanion copyWith({
    Value<String>? id,
    Value<String>? person,
    Value<String>? kind,
    Value<double>? principal,
    Value<int>? dateLent,
    Value<int?>? dueDate,
    Value<String>? note,
    Value<int>? remindAt,
    Value<int>? rev,
    Value<String>? revBy,
    Value<int>? rowid,
  }) {
    return LoansCompanion(
      id: id ?? this.id,
      person: person ?? this.person,
      kind: kind ?? this.kind,
      principal: principal ?? this.principal,
      dateLent: dateLent ?? this.dateLent,
      dueDate: dueDate ?? this.dueDate,
      note: note ?? this.note,
      remindAt: remindAt ?? this.remindAt,
      rev: rev ?? this.rev,
      revBy: revBy ?? this.revBy,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (person.present) {
      map['person'] = Variable<String>(person.value);
    }
    if (kind.present) {
      map['kind'] = Variable<String>(kind.value);
    }
    if (principal.present) {
      map['principal'] = Variable<double>(principal.value);
    }
    if (dateLent.present) {
      map['date_lent'] = Variable<int>(dateLent.value);
    }
    if (dueDate.present) {
      map['due_date'] = Variable<int>(dueDate.value);
    }
    if (note.present) {
      map['note'] = Variable<String>(note.value);
    }
    if (remindAt.present) {
      map['remind_at'] = Variable<int>(remindAt.value);
    }
    if (rev.present) {
      map['rev'] = Variable<int>(rev.value);
    }
    if (revBy.present) {
      map['rev_by'] = Variable<String>(revBy.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('LoansCompanion(')
          ..write('id: $id, ')
          ..write('person: $person, ')
          ..write('kind: $kind, ')
          ..write('principal: $principal, ')
          ..write('dateLent: $dateLent, ')
          ..write('dueDate: $dueDate, ')
          ..write('note: $note, ')
          ..write('remindAt: $remindAt, ')
          ..write('rev: $rev, ')
          ..write('revBy: $revBy, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $LoanTopupsTable extends LoanTopups
    with TableInfo<$LoanTopupsTable, TopupRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $LoanTopupsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _loanIdMeta = const VerificationMeta('loanId');
  @override
  late final GeneratedColumn<String> loanId = GeneratedColumn<String>(
    'loan_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES loans (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _amountMeta = const VerificationMeta('amount');
  @override
  late final GeneratedColumn<double> amount = GeneratedColumn<double>(
    'amount',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _dateMeta = const VerificationMeta('date');
  @override
  late final GeneratedColumn<int> date = GeneratedColumn<int>(
    'date',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _noteMeta = const VerificationMeta('note');
  @override
  late final GeneratedColumn<String> note = GeneratedColumn<String>(
    'note',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _revMeta = const VerificationMeta('rev');
  @override
  late final GeneratedColumn<int> rev = GeneratedColumn<int>(
    'rev',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _revByMeta = const VerificationMeta('revBy');
  @override
  late final GeneratedColumn<String> revBy = GeneratedColumn<String>(
    'rev_by',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    loanId,
    amount,
    date,
    note,
    rev,
    revBy,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'loan_topups';
  @override
  VerificationContext validateIntegrity(
    Insertable<TopupRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('loan_id')) {
      context.handle(
        _loanIdMeta,
        loanId.isAcceptableOrUnknown(data['loan_id']!, _loanIdMeta),
      );
    } else if (isInserting) {
      context.missing(_loanIdMeta);
    }
    if (data.containsKey('amount')) {
      context.handle(
        _amountMeta,
        amount.isAcceptableOrUnknown(data['amount']!, _amountMeta),
      );
    } else if (isInserting) {
      context.missing(_amountMeta);
    }
    if (data.containsKey('date')) {
      context.handle(
        _dateMeta,
        date.isAcceptableOrUnknown(data['date']!, _dateMeta),
      );
    } else if (isInserting) {
      context.missing(_dateMeta);
    }
    if (data.containsKey('note')) {
      context.handle(
        _noteMeta,
        note.isAcceptableOrUnknown(data['note']!, _noteMeta),
      );
    } else if (isInserting) {
      context.missing(_noteMeta);
    }
    if (data.containsKey('rev')) {
      context.handle(
        _revMeta,
        rev.isAcceptableOrUnknown(data['rev']!, _revMeta),
      );
    }
    if (data.containsKey('rev_by')) {
      context.handle(
        _revByMeta,
        revBy.isAcceptableOrUnknown(data['rev_by']!, _revByMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  TopupRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return TopupRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      loanId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}loan_id'],
      )!,
      amount: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}amount'],
      )!,
      date: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}date'],
      )!,
      note: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}note'],
      )!,
      rev: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}rev'],
      )!,
      revBy: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}rev_by'],
      )!,
    );
  }

  @override
  $LoanTopupsTable createAlias(String alias) {
    return $LoanTopupsTable(attachedDatabase, alias);
  }
}

class TopupRow extends DataClass implements Insertable<TopupRow> {
  final String id;
  final String loanId;
  final double amount;
  final int date;
  final String note;
  final int rev;
  final String revBy;
  const TopupRow({
    required this.id,
    required this.loanId,
    required this.amount,
    required this.date,
    required this.note,
    required this.rev,
    required this.revBy,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['loan_id'] = Variable<String>(loanId);
    map['amount'] = Variable<double>(amount);
    map['date'] = Variable<int>(date);
    map['note'] = Variable<String>(note);
    map['rev'] = Variable<int>(rev);
    map['rev_by'] = Variable<String>(revBy);
    return map;
  }

  LoanTopupsCompanion toCompanion(bool nullToAbsent) {
    return LoanTopupsCompanion(
      id: Value(id),
      loanId: Value(loanId),
      amount: Value(amount),
      date: Value(date),
      note: Value(note),
      rev: Value(rev),
      revBy: Value(revBy),
    );
  }

  factory TopupRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return TopupRow(
      id: serializer.fromJson<String>(json['id']),
      loanId: serializer.fromJson<String>(json['loanId']),
      amount: serializer.fromJson<double>(json['amount']),
      date: serializer.fromJson<int>(json['date']),
      note: serializer.fromJson<String>(json['note']),
      rev: serializer.fromJson<int>(json['rev']),
      revBy: serializer.fromJson<String>(json['revBy']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'loanId': serializer.toJson<String>(loanId),
      'amount': serializer.toJson<double>(amount),
      'date': serializer.toJson<int>(date),
      'note': serializer.toJson<String>(note),
      'rev': serializer.toJson<int>(rev),
      'revBy': serializer.toJson<String>(revBy),
    };
  }

  TopupRow copyWith({
    String? id,
    String? loanId,
    double? amount,
    int? date,
    String? note,
    int? rev,
    String? revBy,
  }) => TopupRow(
    id: id ?? this.id,
    loanId: loanId ?? this.loanId,
    amount: amount ?? this.amount,
    date: date ?? this.date,
    note: note ?? this.note,
    rev: rev ?? this.rev,
    revBy: revBy ?? this.revBy,
  );
  TopupRow copyWithCompanion(LoanTopupsCompanion data) {
    return TopupRow(
      id: data.id.present ? data.id.value : this.id,
      loanId: data.loanId.present ? data.loanId.value : this.loanId,
      amount: data.amount.present ? data.amount.value : this.amount,
      date: data.date.present ? data.date.value : this.date,
      note: data.note.present ? data.note.value : this.note,
      rev: data.rev.present ? data.rev.value : this.rev,
      revBy: data.revBy.present ? data.revBy.value : this.revBy,
    );
  }

  @override
  String toString() {
    return (StringBuffer('TopupRow(')
          ..write('id: $id, ')
          ..write('loanId: $loanId, ')
          ..write('amount: $amount, ')
          ..write('date: $date, ')
          ..write('note: $note, ')
          ..write('rev: $rev, ')
          ..write('revBy: $revBy')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, loanId, amount, date, note, rev, revBy);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is TopupRow &&
          other.id == this.id &&
          other.loanId == this.loanId &&
          other.amount == this.amount &&
          other.date == this.date &&
          other.note == this.note &&
          other.rev == this.rev &&
          other.revBy == this.revBy);
}

class LoanTopupsCompanion extends UpdateCompanion<TopupRow> {
  final Value<String> id;
  final Value<String> loanId;
  final Value<double> amount;
  final Value<int> date;
  final Value<String> note;
  final Value<int> rev;
  final Value<String> revBy;
  final Value<int> rowid;
  const LoanTopupsCompanion({
    this.id = const Value.absent(),
    this.loanId = const Value.absent(),
    this.amount = const Value.absent(),
    this.date = const Value.absent(),
    this.note = const Value.absent(),
    this.rev = const Value.absent(),
    this.revBy = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  LoanTopupsCompanion.insert({
    required String id,
    required String loanId,
    required double amount,
    required int date,
    required String note,
    this.rev = const Value.absent(),
    this.revBy = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       loanId = Value(loanId),
       amount = Value(amount),
       date = Value(date),
       note = Value(note);
  static Insertable<TopupRow> custom({
    Expression<String>? id,
    Expression<String>? loanId,
    Expression<double>? amount,
    Expression<int>? date,
    Expression<String>? note,
    Expression<int>? rev,
    Expression<String>? revBy,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (loanId != null) 'loan_id': loanId,
      if (amount != null) 'amount': amount,
      if (date != null) 'date': date,
      if (note != null) 'note': note,
      if (rev != null) 'rev': rev,
      if (revBy != null) 'rev_by': revBy,
      if (rowid != null) 'rowid': rowid,
    });
  }

  LoanTopupsCompanion copyWith({
    Value<String>? id,
    Value<String>? loanId,
    Value<double>? amount,
    Value<int>? date,
    Value<String>? note,
    Value<int>? rev,
    Value<String>? revBy,
    Value<int>? rowid,
  }) {
    return LoanTopupsCompanion(
      id: id ?? this.id,
      loanId: loanId ?? this.loanId,
      amount: amount ?? this.amount,
      date: date ?? this.date,
      note: note ?? this.note,
      rev: rev ?? this.rev,
      revBy: revBy ?? this.revBy,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (loanId.present) {
      map['loan_id'] = Variable<String>(loanId.value);
    }
    if (amount.present) {
      map['amount'] = Variable<double>(amount.value);
    }
    if (date.present) {
      map['date'] = Variable<int>(date.value);
    }
    if (note.present) {
      map['note'] = Variable<String>(note.value);
    }
    if (rev.present) {
      map['rev'] = Variable<int>(rev.value);
    }
    if (revBy.present) {
      map['rev_by'] = Variable<String>(revBy.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('LoanTopupsCompanion(')
          ..write('id: $id, ')
          ..write('loanId: $loanId, ')
          ..write('amount: $amount, ')
          ..write('date: $date, ')
          ..write('note: $note, ')
          ..write('rev: $rev, ')
          ..write('revBy: $revBy, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $LoanRepaymentsTable extends LoanRepayments
    with TableInfo<$LoanRepaymentsTable, RepaymentRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $LoanRepaymentsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _loanIdMeta = const VerificationMeta('loanId');
  @override
  late final GeneratedColumn<String> loanId = GeneratedColumn<String>(
    'loan_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES loans (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _amountMeta = const VerificationMeta('amount');
  @override
  late final GeneratedColumn<double> amount = GeneratedColumn<double>(
    'amount',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _dateMeta = const VerificationMeta('date');
  @override
  late final GeneratedColumn<int> date = GeneratedColumn<int>(
    'date',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _noteMeta = const VerificationMeta('note');
  @override
  late final GeneratedColumn<String> note = GeneratedColumn<String>(
    'note',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _revMeta = const VerificationMeta('rev');
  @override
  late final GeneratedColumn<int> rev = GeneratedColumn<int>(
    'rev',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _revByMeta = const VerificationMeta('revBy');
  @override
  late final GeneratedColumn<String> revBy = GeneratedColumn<String>(
    'rev_by',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    loanId,
    amount,
    date,
    note,
    rev,
    revBy,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'loan_repayments';
  @override
  VerificationContext validateIntegrity(
    Insertable<RepaymentRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('loan_id')) {
      context.handle(
        _loanIdMeta,
        loanId.isAcceptableOrUnknown(data['loan_id']!, _loanIdMeta),
      );
    } else if (isInserting) {
      context.missing(_loanIdMeta);
    }
    if (data.containsKey('amount')) {
      context.handle(
        _amountMeta,
        amount.isAcceptableOrUnknown(data['amount']!, _amountMeta),
      );
    } else if (isInserting) {
      context.missing(_amountMeta);
    }
    if (data.containsKey('date')) {
      context.handle(
        _dateMeta,
        date.isAcceptableOrUnknown(data['date']!, _dateMeta),
      );
    } else if (isInserting) {
      context.missing(_dateMeta);
    }
    if (data.containsKey('note')) {
      context.handle(
        _noteMeta,
        note.isAcceptableOrUnknown(data['note']!, _noteMeta),
      );
    } else if (isInserting) {
      context.missing(_noteMeta);
    }
    if (data.containsKey('rev')) {
      context.handle(
        _revMeta,
        rev.isAcceptableOrUnknown(data['rev']!, _revMeta),
      );
    }
    if (data.containsKey('rev_by')) {
      context.handle(
        _revByMeta,
        revBy.isAcceptableOrUnknown(data['rev_by']!, _revByMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  RepaymentRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return RepaymentRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      loanId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}loan_id'],
      )!,
      amount: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}amount'],
      )!,
      date: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}date'],
      )!,
      note: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}note'],
      )!,
      rev: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}rev'],
      )!,
      revBy: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}rev_by'],
      )!,
    );
  }

  @override
  $LoanRepaymentsTable createAlias(String alias) {
    return $LoanRepaymentsTable(attachedDatabase, alias);
  }
}

class RepaymentRow extends DataClass implements Insertable<RepaymentRow> {
  final String id;
  final String loanId;
  final double amount;
  final int date;
  final String note;
  final int rev;
  final String revBy;
  const RepaymentRow({
    required this.id,
    required this.loanId,
    required this.amount,
    required this.date,
    required this.note,
    required this.rev,
    required this.revBy,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['loan_id'] = Variable<String>(loanId);
    map['amount'] = Variable<double>(amount);
    map['date'] = Variable<int>(date);
    map['note'] = Variable<String>(note);
    map['rev'] = Variable<int>(rev);
    map['rev_by'] = Variable<String>(revBy);
    return map;
  }

  LoanRepaymentsCompanion toCompanion(bool nullToAbsent) {
    return LoanRepaymentsCompanion(
      id: Value(id),
      loanId: Value(loanId),
      amount: Value(amount),
      date: Value(date),
      note: Value(note),
      rev: Value(rev),
      revBy: Value(revBy),
    );
  }

  factory RepaymentRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return RepaymentRow(
      id: serializer.fromJson<String>(json['id']),
      loanId: serializer.fromJson<String>(json['loanId']),
      amount: serializer.fromJson<double>(json['amount']),
      date: serializer.fromJson<int>(json['date']),
      note: serializer.fromJson<String>(json['note']),
      rev: serializer.fromJson<int>(json['rev']),
      revBy: serializer.fromJson<String>(json['revBy']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'loanId': serializer.toJson<String>(loanId),
      'amount': serializer.toJson<double>(amount),
      'date': serializer.toJson<int>(date),
      'note': serializer.toJson<String>(note),
      'rev': serializer.toJson<int>(rev),
      'revBy': serializer.toJson<String>(revBy),
    };
  }

  RepaymentRow copyWith({
    String? id,
    String? loanId,
    double? amount,
    int? date,
    String? note,
    int? rev,
    String? revBy,
  }) => RepaymentRow(
    id: id ?? this.id,
    loanId: loanId ?? this.loanId,
    amount: amount ?? this.amount,
    date: date ?? this.date,
    note: note ?? this.note,
    rev: rev ?? this.rev,
    revBy: revBy ?? this.revBy,
  );
  RepaymentRow copyWithCompanion(LoanRepaymentsCompanion data) {
    return RepaymentRow(
      id: data.id.present ? data.id.value : this.id,
      loanId: data.loanId.present ? data.loanId.value : this.loanId,
      amount: data.amount.present ? data.amount.value : this.amount,
      date: data.date.present ? data.date.value : this.date,
      note: data.note.present ? data.note.value : this.note,
      rev: data.rev.present ? data.rev.value : this.rev,
      revBy: data.revBy.present ? data.revBy.value : this.revBy,
    );
  }

  @override
  String toString() {
    return (StringBuffer('RepaymentRow(')
          ..write('id: $id, ')
          ..write('loanId: $loanId, ')
          ..write('amount: $amount, ')
          ..write('date: $date, ')
          ..write('note: $note, ')
          ..write('rev: $rev, ')
          ..write('revBy: $revBy')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, loanId, amount, date, note, rev, revBy);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is RepaymentRow &&
          other.id == this.id &&
          other.loanId == this.loanId &&
          other.amount == this.amount &&
          other.date == this.date &&
          other.note == this.note &&
          other.rev == this.rev &&
          other.revBy == this.revBy);
}

class LoanRepaymentsCompanion extends UpdateCompanion<RepaymentRow> {
  final Value<String> id;
  final Value<String> loanId;
  final Value<double> amount;
  final Value<int> date;
  final Value<String> note;
  final Value<int> rev;
  final Value<String> revBy;
  final Value<int> rowid;
  const LoanRepaymentsCompanion({
    this.id = const Value.absent(),
    this.loanId = const Value.absent(),
    this.amount = const Value.absent(),
    this.date = const Value.absent(),
    this.note = const Value.absent(),
    this.rev = const Value.absent(),
    this.revBy = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  LoanRepaymentsCompanion.insert({
    required String id,
    required String loanId,
    required double amount,
    required int date,
    required String note,
    this.rev = const Value.absent(),
    this.revBy = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       loanId = Value(loanId),
       amount = Value(amount),
       date = Value(date),
       note = Value(note);
  static Insertable<RepaymentRow> custom({
    Expression<String>? id,
    Expression<String>? loanId,
    Expression<double>? amount,
    Expression<int>? date,
    Expression<String>? note,
    Expression<int>? rev,
    Expression<String>? revBy,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (loanId != null) 'loan_id': loanId,
      if (amount != null) 'amount': amount,
      if (date != null) 'date': date,
      if (note != null) 'note': note,
      if (rev != null) 'rev': rev,
      if (revBy != null) 'rev_by': revBy,
      if (rowid != null) 'rowid': rowid,
    });
  }

  LoanRepaymentsCompanion copyWith({
    Value<String>? id,
    Value<String>? loanId,
    Value<double>? amount,
    Value<int>? date,
    Value<String>? note,
    Value<int>? rev,
    Value<String>? revBy,
    Value<int>? rowid,
  }) {
    return LoanRepaymentsCompanion(
      id: id ?? this.id,
      loanId: loanId ?? this.loanId,
      amount: amount ?? this.amount,
      date: date ?? this.date,
      note: note ?? this.note,
      rev: rev ?? this.rev,
      revBy: revBy ?? this.revBy,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (loanId.present) {
      map['loan_id'] = Variable<String>(loanId.value);
    }
    if (amount.present) {
      map['amount'] = Variable<double>(amount.value);
    }
    if (date.present) {
      map['date'] = Variable<int>(date.value);
    }
    if (note.present) {
      map['note'] = Variable<String>(note.value);
    }
    if (rev.present) {
      map['rev'] = Variable<int>(rev.value);
    }
    if (revBy.present) {
      map['rev_by'] = Variable<String>(revBy.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('LoanRepaymentsCompanion(')
          ..write('id: $id, ')
          ..write('loanId: $loanId, ')
          ..write('amount: $amount, ')
          ..write('date: $date, ')
          ..write('note: $note, ')
          ..write('rev: $rev, ')
          ..write('revBy: $revBy, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $TombstonesTable extends Tombstones
    with TableInfo<$TombstonesTable, TombstoneRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $TombstonesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _typeMeta = const VerificationMeta('type');
  @override
  late final GeneratedColumn<String> type = GeneratedColumn<String>(
    'type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _recordIdMeta = const VerificationMeta(
    'recordId',
  );
  @override
  late final GeneratedColumn<String> recordId = GeneratedColumn<String>(
    'record_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _revMeta = const VerificationMeta('rev');
  @override
  late final GeneratedColumn<int> rev = GeneratedColumn<int>(
    'rev',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _revByMeta = const VerificationMeta('revBy');
  @override
  late final GeneratedColumn<String> revBy = GeneratedColumn<String>(
    'rev_by',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [type, recordId, rev, revBy];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'tombstones';
  @override
  VerificationContext validateIntegrity(
    Insertable<TombstoneRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('type')) {
      context.handle(
        _typeMeta,
        type.isAcceptableOrUnknown(data['type']!, _typeMeta),
      );
    } else if (isInserting) {
      context.missing(_typeMeta);
    }
    if (data.containsKey('record_id')) {
      context.handle(
        _recordIdMeta,
        recordId.isAcceptableOrUnknown(data['record_id']!, _recordIdMeta),
      );
    } else if (isInserting) {
      context.missing(_recordIdMeta);
    }
    if (data.containsKey('rev')) {
      context.handle(
        _revMeta,
        rev.isAcceptableOrUnknown(data['rev']!, _revMeta),
      );
    } else if (isInserting) {
      context.missing(_revMeta);
    }
    if (data.containsKey('rev_by')) {
      context.handle(
        _revByMeta,
        revBy.isAcceptableOrUnknown(data['rev_by']!, _revByMeta),
      );
    } else if (isInserting) {
      context.missing(_revByMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {type, recordId};
  @override
  TombstoneRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return TombstoneRow(
      type: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}type'],
      )!,
      recordId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}record_id'],
      )!,
      rev: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}rev'],
      )!,
      revBy: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}rev_by'],
      )!,
    );
  }

  @override
  $TombstonesTable createAlias(String alias) {
    return $TombstonesTable(attachedDatabase, alias);
  }
}

class TombstoneRow extends DataClass implements Insertable<TombstoneRow> {
  final String type;
  final String recordId;
  final int rev;
  final String revBy;
  const TombstoneRow({
    required this.type,
    required this.recordId,
    required this.rev,
    required this.revBy,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['type'] = Variable<String>(type);
    map['record_id'] = Variable<String>(recordId);
    map['rev'] = Variable<int>(rev);
    map['rev_by'] = Variable<String>(revBy);
    return map;
  }

  TombstonesCompanion toCompanion(bool nullToAbsent) {
    return TombstonesCompanion(
      type: Value(type),
      recordId: Value(recordId),
      rev: Value(rev),
      revBy: Value(revBy),
    );
  }

  factory TombstoneRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return TombstoneRow(
      type: serializer.fromJson<String>(json['type']),
      recordId: serializer.fromJson<String>(json['recordId']),
      rev: serializer.fromJson<int>(json['rev']),
      revBy: serializer.fromJson<String>(json['revBy']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'type': serializer.toJson<String>(type),
      'recordId': serializer.toJson<String>(recordId),
      'rev': serializer.toJson<int>(rev),
      'revBy': serializer.toJson<String>(revBy),
    };
  }

  TombstoneRow copyWith({
    String? type,
    String? recordId,
    int? rev,
    String? revBy,
  }) => TombstoneRow(
    type: type ?? this.type,
    recordId: recordId ?? this.recordId,
    rev: rev ?? this.rev,
    revBy: revBy ?? this.revBy,
  );
  TombstoneRow copyWithCompanion(TombstonesCompanion data) {
    return TombstoneRow(
      type: data.type.present ? data.type.value : this.type,
      recordId: data.recordId.present ? data.recordId.value : this.recordId,
      rev: data.rev.present ? data.rev.value : this.rev,
      revBy: data.revBy.present ? data.revBy.value : this.revBy,
    );
  }

  @override
  String toString() {
    return (StringBuffer('TombstoneRow(')
          ..write('type: $type, ')
          ..write('recordId: $recordId, ')
          ..write('rev: $rev, ')
          ..write('revBy: $revBy')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(type, recordId, rev, revBy);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is TombstoneRow &&
          other.type == this.type &&
          other.recordId == this.recordId &&
          other.rev == this.rev &&
          other.revBy == this.revBy);
}

class TombstonesCompanion extends UpdateCompanion<TombstoneRow> {
  final Value<String> type;
  final Value<String> recordId;
  final Value<int> rev;
  final Value<String> revBy;
  final Value<int> rowid;
  const TombstonesCompanion({
    this.type = const Value.absent(),
    this.recordId = const Value.absent(),
    this.rev = const Value.absent(),
    this.revBy = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  TombstonesCompanion.insert({
    required String type,
    required String recordId,
    required int rev,
    required String revBy,
    this.rowid = const Value.absent(),
  }) : type = Value(type),
       recordId = Value(recordId),
       rev = Value(rev),
       revBy = Value(revBy);
  static Insertable<TombstoneRow> custom({
    Expression<String>? type,
    Expression<String>? recordId,
    Expression<int>? rev,
    Expression<String>? revBy,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (type != null) 'type': type,
      if (recordId != null) 'record_id': recordId,
      if (rev != null) 'rev': rev,
      if (revBy != null) 'rev_by': revBy,
      if (rowid != null) 'rowid': rowid,
    });
  }

  TombstonesCompanion copyWith({
    Value<String>? type,
    Value<String>? recordId,
    Value<int>? rev,
    Value<String>? revBy,
    Value<int>? rowid,
  }) {
    return TombstonesCompanion(
      type: type ?? this.type,
      recordId: recordId ?? this.recordId,
      rev: rev ?? this.rev,
      revBy: revBy ?? this.revBy,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (type.present) {
      map['type'] = Variable<String>(type.value);
    }
    if (recordId.present) {
      map['record_id'] = Variable<String>(recordId.value);
    }
    if (rev.present) {
      map['rev'] = Variable<int>(rev.value);
    }
    if (revBy.present) {
      map['rev_by'] = Variable<String>(revBy.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('TombstonesCompanion(')
          ..write('type: $type, ')
          ..write('recordId: $recordId, ')
          ..write('rev: $rev, ')
          ..write('revBy: $revBy, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDb extends GeneratedDatabase {
  _$AppDb(QueryExecutor e) : super(e);
  $AppDbManager get managers => $AppDbManager(this);
  late final $CategoriesTable categories = $CategoriesTable(this);
  late final $TransactionsTable transactions = $TransactionsTable(this);
  late final $ProjectsTable projects = $ProjectsTable(this);
  late final $LoansTable loans = $LoansTable(this);
  late final $LoanTopupsTable loanTopups = $LoanTopupsTable(this);
  late final $LoanRepaymentsTable loanRepayments = $LoanRepaymentsTable(this);
  late final $TombstonesTable tombstones = $TombstonesTable(this);
  late final Index idxTransactionsDate = Index(
    'idx_transactions_date',
    'CREATE INDEX idx_transactions_date ON transactions (date)',
  );
  late final Index idxTransactionsCategory = Index(
    'idx_transactions_category',
    'CREATE INDEX idx_transactions_category ON transactions (category_id)',
  );
  late final Index idxTransactionsProject = Index(
    'idx_transactions_project',
    'CREATE INDEX idx_transactions_project ON transactions (project_id)',
  );
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    categories,
    transactions,
    projects,
    loans,
    loanTopups,
    loanRepayments,
    tombstones,
    idxTransactionsDate,
    idxTransactionsCategory,
    idxTransactionsProject,
  ];
  @override
  StreamQueryUpdateRules get streamUpdateRules => const StreamQueryUpdateRules([
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'loans',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('loan_topups', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'loans',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('loan_repayments', kind: UpdateKind.delete)],
    ),
  ]);
}

typedef $$CategoriesTableCreateCompanionBuilder = CategoriesCompanion Function({
  required String id,
  required String name,
  required int icon,
  required int color,
  required double budget,
  required int sortOrder,
  Value<int> rev,
  Value<String> revBy,
  Value<int> rowid,
});
typedef $$CategoriesTableUpdateCompanionBuilder = CategoriesCompanion Function({
  Value<String> id,
  Value<String> name,
  Value<int> icon,
  Value<int> color,
  Value<double> budget,
  Value<int> sortOrder,
  Value<int> rev,
  Value<String> revBy,
  Value<int> rowid,
});

final class $$CategoriesTableReferences
    extends BaseReferences<_$AppDb, $CategoriesTable, CategoryRow> {
  $$CategoriesTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static MultiTypedResultKey<$TransactionsTable, List<TxnRow>>
  _transactionsRefsTable(_$AppDb db) => MultiTypedResultKey.fromTable(
    db.transactions,
    aliasName: 'categories__id__transactions__category_id',
  );

  $$TransactionsTableProcessedTableManager get transactionsRefs {
    final manager = $$TransactionsTableTableManager(
      $_db,
      $_db.transactions,
    ).filter((f) => f.categoryId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_transactionsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$CategoriesTableFilterComposer
    extends Composer<_$AppDb, $CategoriesTable> {
  $$CategoriesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get icon => $composableBuilder(
    column: $table.icon,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get color => $composableBuilder(
    column: $table.color,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get budget => $composableBuilder(
    column: $table.budget,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get sortOrder => $composableBuilder(
    column: $table.sortOrder,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get rev => $composableBuilder(
    column: $table.rev,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get revBy => $composableBuilder(
    column: $table.revBy,
    builder: (column) => ColumnFilters(column),
  );

  Expression<bool> transactionsRefs(
    Expression<bool> Function($$TransactionsTableFilterComposer f) f,
  ) {
    final $$TransactionsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.transactions,
      getReferencedColumn: (t) => t.categoryId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$TransactionsTableFilterComposer(
            $db: $db,
            $table: $db.transactions,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$CategoriesTableOrderingComposer
    extends Composer<_$AppDb, $CategoriesTable> {
  $$CategoriesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get icon => $composableBuilder(
    column: $table.icon,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get color => $composableBuilder(
    column: $table.color,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get budget => $composableBuilder(
    column: $table.budget,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get sortOrder => $composableBuilder(
    column: $table.sortOrder,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get rev => $composableBuilder(
    column: $table.rev,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get revBy => $composableBuilder(
    column: $table.revBy,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$CategoriesTableAnnotationComposer
    extends Composer<_$AppDb, $CategoriesTable> {
  $$CategoriesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<int> get icon =>
      $composableBuilder(column: $table.icon, builder: (column) => column);

  GeneratedColumn<int> get color =>
      $composableBuilder(column: $table.color, builder: (column) => column);

  GeneratedColumn<double> get budget =>
      $composableBuilder(column: $table.budget, builder: (column) => column);

  GeneratedColumn<int> get sortOrder =>
      $composableBuilder(column: $table.sortOrder, builder: (column) => column);

  GeneratedColumn<int> get rev =>
      $composableBuilder(column: $table.rev, builder: (column) => column);

  GeneratedColumn<String> get revBy =>
      $composableBuilder(column: $table.revBy, builder: (column) => column);

  Expression<T> transactionsRefs<T extends Object>(
    Expression<T> Function($$TransactionsTableAnnotationComposer a) f,
  ) {
    final $$TransactionsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.transactions,
      getReferencedColumn: (t) => t.categoryId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$TransactionsTableAnnotationComposer(
            $db: $db,
            $table: $db.transactions,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$CategoriesTableTableManager
    extends
        RootTableManager<
          _$AppDb,
          $CategoriesTable,
          CategoryRow,
          $$CategoriesTableFilterComposer,
          $$CategoriesTableOrderingComposer,
          $$CategoriesTableAnnotationComposer,
          $$CategoriesTableCreateCompanionBuilder,
          $$CategoriesTableUpdateCompanionBuilder,
          (CategoryRow, $$CategoriesTableReferences),
          CategoryRow,
          PrefetchHooks Function({bool transactionsRefs})
        > {
  $$CategoriesTableTableManager(_$AppDb db, $CategoriesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CategoriesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CategoriesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$CategoriesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<int> icon = const Value.absent(),
                Value<int> color = const Value.absent(),
                Value<double> budget = const Value.absent(),
                Value<int> sortOrder = const Value.absent(),
                Value<int> rev = const Value.absent(),
                Value<String> revBy = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CategoriesCompanion(
                id: id,
                name: name,
                icon: icon,
                color: color,
                budget: budget,
                sortOrder: sortOrder,
                rev: rev,
                revBy: revBy,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String name,
                required int icon,
                required int color,
                required double budget,
                required int sortOrder,
                Value<int> rev = const Value.absent(),
                Value<String> revBy = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CategoriesCompanion.insert(
                id: id,
                name: name,
                icon: icon,
                color: color,
                budget: budget,
                sortOrder: sortOrder,
                rev: rev,
                revBy: revBy,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$CategoriesTable, CategoryRow>(table),
                  $$CategoriesTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({transactionsRefs = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [if (transactionsRefs) db.transactions],
              addJoins: null,
              getPrefetchedDataCallback: (items) async {
                return [
                  if (transactionsRefs)
                    await $_getPrefetchedData<
                      CategoryRow,
                      $CategoriesTable,
                      TxnRow
                    >(
                      currentTable: table,
                      referencedTable: $$CategoriesTableReferences
                          ._transactionsRefsTable(db),
                      managerFromTypedResult: (p0) =>
                          $$CategoriesTableReferences(
                            db,
                            table,
                            p0,
                          ).transactionsRefs,
                      referencedItemsForCurrentItem: (item, referencedItems) =>
                          referencedItems.where((e) => e.categoryId == item.id),
                      typedResults: items,
                    ),
                ];
              },
            );
          },
        ),
      );
}

typedef $$CategoriesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDb,
      $CategoriesTable,
      CategoryRow,
      $$CategoriesTableFilterComposer,
      $$CategoriesTableOrderingComposer,
      $$CategoriesTableAnnotationComposer,
      $$CategoriesTableCreateCompanionBuilder,
      $$CategoriesTableUpdateCompanionBuilder,
      (CategoryRow, $$CategoriesTableReferences),
      CategoryRow,
      PrefetchHooks Function({bool transactionsRefs})
    >;
typedef $$TransactionsTableCreateCompanionBuilder =
    TransactionsCompanion Function({
      required String id,
      required String type,
      required double amount,
      required String categoryId,
      required int date,
      required String note,
      required String mode,
      required String projectId,
      Value<int> rev,
      Value<String> revBy,
      Value<int> rowid,
    });
typedef $$TransactionsTableUpdateCompanionBuilder =
    TransactionsCompanion Function({
      Value<String> id,
      Value<String> type,
      Value<double> amount,
      Value<String> categoryId,
      Value<int> date,
      Value<String> note,
      Value<String> mode,
      Value<String> projectId,
      Value<int> rev,
      Value<String> revBy,
      Value<int> rowid,
    });

final class $$TransactionsTableReferences
    extends BaseReferences<_$AppDb, $TransactionsTable, TxnRow> {
  $$TransactionsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $CategoriesTable _categoryIdTable(_$AppDb db) =>
      db.categories.createAlias('transactions__category_id__categories__id');

  $$CategoriesTableProcessedTableManager get categoryId {
    final $_column = $_itemColumn<String>('category_id')!;

    final manager = $$CategoriesTableTableManager(
      $_db,
      $_db.categories,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_categoryIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$TransactionsTableFilterComposer
    extends Composer<_$AppDb, $TransactionsTable> {
  $$TransactionsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get type => $composableBuilder(
    column: $table.type,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get amount => $composableBuilder(
    column: $table.amount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get date => $composableBuilder(
    column: $table.date,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get note => $composableBuilder(
    column: $table.note,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get mode => $composableBuilder(
    column: $table.mode,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get projectId => $composableBuilder(
    column: $table.projectId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get rev => $composableBuilder(
    column: $table.rev,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get revBy => $composableBuilder(
    column: $table.revBy,
    builder: (column) => ColumnFilters(column),
  );

  $$CategoriesTableFilterComposer get categoryId {
    final $$CategoriesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.categoryId,
      referencedTable: $db.categories,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$CategoriesTableFilterComposer(
            $db: $db,
            $table: $db.categories,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$TransactionsTableOrderingComposer
    extends Composer<_$AppDb, $TransactionsTable> {
  $$TransactionsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get type => $composableBuilder(
    column: $table.type,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get amount => $composableBuilder(
    column: $table.amount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get date => $composableBuilder(
    column: $table.date,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get note => $composableBuilder(
    column: $table.note,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get mode => $composableBuilder(
    column: $table.mode,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get projectId => $composableBuilder(
    column: $table.projectId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get rev => $composableBuilder(
    column: $table.rev,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get revBy => $composableBuilder(
    column: $table.revBy,
    builder: (column) => ColumnOrderings(column),
  );

  $$CategoriesTableOrderingComposer get categoryId {
    final $$CategoriesTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.categoryId,
      referencedTable: $db.categories,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$CategoriesTableOrderingComposer(
            $db: $db,
            $table: $db.categories,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$TransactionsTableAnnotationComposer
    extends Composer<_$AppDb, $TransactionsTable> {
  $$TransactionsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get type =>
      $composableBuilder(column: $table.type, builder: (column) => column);

  GeneratedColumn<double> get amount =>
      $composableBuilder(column: $table.amount, builder: (column) => column);

  GeneratedColumn<int> get date =>
      $composableBuilder(column: $table.date, builder: (column) => column);

  GeneratedColumn<String> get note =>
      $composableBuilder(column: $table.note, builder: (column) => column);

  GeneratedColumn<String> get mode =>
      $composableBuilder(column: $table.mode, builder: (column) => column);

  GeneratedColumn<String> get projectId =>
      $composableBuilder(column: $table.projectId, builder: (column) => column);

  GeneratedColumn<int> get rev =>
      $composableBuilder(column: $table.rev, builder: (column) => column);

  GeneratedColumn<String> get revBy =>
      $composableBuilder(column: $table.revBy, builder: (column) => column);

  $$CategoriesTableAnnotationComposer get categoryId {
    final $$CategoriesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.categoryId,
      referencedTable: $db.categories,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$CategoriesTableAnnotationComposer(
            $db: $db,
            $table: $db.categories,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$TransactionsTableTableManager
    extends
        RootTableManager<
          _$AppDb,
          $TransactionsTable,
          TxnRow,
          $$TransactionsTableFilterComposer,
          $$TransactionsTableOrderingComposer,
          $$TransactionsTableAnnotationComposer,
          $$TransactionsTableCreateCompanionBuilder,
          $$TransactionsTableUpdateCompanionBuilder,
          (TxnRow, $$TransactionsTableReferences),
          TxnRow,
          PrefetchHooks Function({bool categoryId})
        > {
  $$TransactionsTableTableManager(_$AppDb db, $TransactionsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$TransactionsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$TransactionsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$TransactionsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> type = const Value.absent(),
                Value<double> amount = const Value.absent(),
                Value<String> categoryId = const Value.absent(),
                Value<int> date = const Value.absent(),
                Value<String> note = const Value.absent(),
                Value<String> mode = const Value.absent(),
                Value<String> projectId = const Value.absent(),
                Value<int> rev = const Value.absent(),
                Value<String> revBy = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => TransactionsCompanion(
                id: id,
                type: type,
                amount: amount,
                categoryId: categoryId,
                date: date,
                note: note,
                mode: mode,
                projectId: projectId,
                rev: rev,
                revBy: revBy,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String type,
                required double amount,
                required String categoryId,
                required int date,
                required String note,
                required String mode,
                required String projectId,
                Value<int> rev = const Value.absent(),
                Value<String> revBy = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => TransactionsCompanion.insert(
                id: id,
                type: type,
                amount: amount,
                categoryId: categoryId,
                date: date,
                note: note,
                mode: mode,
                projectId: projectId,
                rev: rev,
                revBy: revBy,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$TransactionsTable, TxnRow>(table),
                  $$TransactionsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({categoryId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (categoryId) {
                      state = state.withJoin(
                        currentTable: table,
                        currentColumn: table.categoryId,
                        referencedTable: $$TransactionsTableReferences
                            ._categoryIdTable(db),
                        referencedColumn: $$TransactionsTableReferences
                            ._categoryIdTable(db)
                            .id,
                      ) as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$TransactionsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDb,
      $TransactionsTable,
      TxnRow,
      $$TransactionsTableFilterComposer,
      $$TransactionsTableOrderingComposer,
      $$TransactionsTableAnnotationComposer,
      $$TransactionsTableCreateCompanionBuilder,
      $$TransactionsTableUpdateCompanionBuilder,
      (TxnRow, $$TransactionsTableReferences),
      TxnRow,
      PrefetchHooks Function({bool categoryId})
    >;
typedef $$ProjectsTableCreateCompanionBuilder = ProjectsCompanion Function({
  required String id,
  required String name,
  required String note,
  required int created,
  required int icon,
  required int color,
  Value<int> rev,
  Value<String> revBy,
  Value<int> rowid,
});
typedef $$ProjectsTableUpdateCompanionBuilder = ProjectsCompanion Function({
  Value<String> id,
  Value<String> name,
  Value<String> note,
  Value<int> created,
  Value<int> icon,
  Value<int> color,
  Value<int> rev,
  Value<String> revBy,
  Value<int> rowid,
});

class $$ProjectsTableFilterComposer extends Composer<_$AppDb, $ProjectsTable> {
  $$ProjectsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get note => $composableBuilder(
    column: $table.note,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get created => $composableBuilder(
    column: $table.created,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get icon => $composableBuilder(
    column: $table.icon,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get color => $composableBuilder(
    column: $table.color,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get rev => $composableBuilder(
    column: $table.rev,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get revBy => $composableBuilder(
    column: $table.revBy,
    builder: (column) => ColumnFilters(column),
  );
}

class $$ProjectsTableOrderingComposer
    extends Composer<_$AppDb, $ProjectsTable> {
  $$ProjectsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get note => $composableBuilder(
    column: $table.note,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get created => $composableBuilder(
    column: $table.created,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get icon => $composableBuilder(
    column: $table.icon,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get color => $composableBuilder(
    column: $table.color,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get rev => $composableBuilder(
    column: $table.rev,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get revBy => $composableBuilder(
    column: $table.revBy,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ProjectsTableAnnotationComposer
    extends Composer<_$AppDb, $ProjectsTable> {
  $$ProjectsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get note =>
      $composableBuilder(column: $table.note, builder: (column) => column);

  GeneratedColumn<int> get created =>
      $composableBuilder(column: $table.created, builder: (column) => column);

  GeneratedColumn<int> get icon =>
      $composableBuilder(column: $table.icon, builder: (column) => column);

  GeneratedColumn<int> get color =>
      $composableBuilder(column: $table.color, builder: (column) => column);

  GeneratedColumn<int> get rev =>
      $composableBuilder(column: $table.rev, builder: (column) => column);

  GeneratedColumn<String> get revBy =>
      $composableBuilder(column: $table.revBy, builder: (column) => column);
}

class $$ProjectsTableTableManager
    extends
        RootTableManager<
          _$AppDb,
          $ProjectsTable,
          ProjectRow,
          $$ProjectsTableFilterComposer,
          $$ProjectsTableOrderingComposer,
          $$ProjectsTableAnnotationComposer,
          $$ProjectsTableCreateCompanionBuilder,
          $$ProjectsTableUpdateCompanionBuilder,
          (ProjectRow, BaseReferences<_$AppDb, $ProjectsTable, ProjectRow>),
          ProjectRow,
          PrefetchHooks Function()
        > {
  $$ProjectsTableTableManager(_$AppDb db, $ProjectsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ProjectsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ProjectsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ProjectsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String> note = const Value.absent(),
                Value<int> created = const Value.absent(),
                Value<int> icon = const Value.absent(),
                Value<int> color = const Value.absent(),
                Value<int> rev = const Value.absent(),
                Value<String> revBy = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ProjectsCompanion(
                id: id,
                name: name,
                note: note,
                created: created,
                icon: icon,
                color: color,
                rev: rev,
                revBy: revBy,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String name,
                required String note,
                required int created,
                required int icon,
                required int color,
                Value<int> rev = const Value.absent(),
                Value<String> revBy = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ProjectsCompanion.insert(
                id: id,
                name: name,
                note: note,
                created: created,
                icon: icon,
                color: color,
                rev: rev,
                revBy: revBy,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$ProjectsTable, ProjectRow>(table),
                  BaseReferences<_$AppDb, $ProjectsTable, ProjectRow>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$ProjectsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDb,
      $ProjectsTable,
      ProjectRow,
      $$ProjectsTableFilterComposer,
      $$ProjectsTableOrderingComposer,
      $$ProjectsTableAnnotationComposer,
      $$ProjectsTableCreateCompanionBuilder,
      $$ProjectsTableUpdateCompanionBuilder,
      (ProjectRow, BaseReferences<_$AppDb, $ProjectsTable, ProjectRow>),
      ProjectRow,
      PrefetchHooks Function()
    >;
typedef $$LoansTableCreateCompanionBuilder = LoansCompanion Function({
  required String id,
  required String person,
  required String kind,
  required double principal,
  required int dateLent,
  Value<int?> dueDate,
  required String note,
  required int remindAt,
  Value<int> rev,
  Value<String> revBy,
  Value<int> rowid,
});
typedef $$LoansTableUpdateCompanionBuilder = LoansCompanion Function({
  Value<String> id,
  Value<String> person,
  Value<String> kind,
  Value<double> principal,
  Value<int> dateLent,
  Value<int?> dueDate,
  Value<String> note,
  Value<int> remindAt,
  Value<int> rev,
  Value<String> revBy,
  Value<int> rowid,
});

final class $$LoansTableReferences
    extends BaseReferences<_$AppDb, $LoansTable, LoanRow> {
  $$LoansTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static MultiTypedResultKey<$LoanTopupsTable, List<TopupRow>>
  _loanTopupsRefsTable(_$AppDb db) => MultiTypedResultKey.fromTable(
    db.loanTopups,
    aliasName: 'loans__id__loan_topups__loan_id',
  );

  $$LoanTopupsTableProcessedTableManager get loanTopupsRefs {
    final manager = $$LoanTopupsTableTableManager(
      $_db,
      $_db.loanTopups,
    ).filter((f) => f.loanId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_loanTopupsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$LoanRepaymentsTable, List<RepaymentRow>>
  _loanRepaymentsRefsTable(_$AppDb db) => MultiTypedResultKey.fromTable(
    db.loanRepayments,
    aliasName: 'loans__id__loan_repayments__loan_id',
  );

  $$LoanRepaymentsTableProcessedTableManager get loanRepaymentsRefs {
    final manager = $$LoanRepaymentsTableTableManager(
      $_db,
      $_db.loanRepayments,
    ).filter((f) => f.loanId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_loanRepaymentsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$LoansTableFilterComposer extends Composer<_$AppDb, $LoansTable> {
  $$LoansTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get person => $composableBuilder(
    column: $table.person,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get principal => $composableBuilder(
    column: $table.principal,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get dateLent => $composableBuilder(
    column: $table.dateLent,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get dueDate => $composableBuilder(
    column: $table.dueDate,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get note => $composableBuilder(
    column: $table.note,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get remindAt => $composableBuilder(
    column: $table.remindAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get rev => $composableBuilder(
    column: $table.rev,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get revBy => $composableBuilder(
    column: $table.revBy,
    builder: (column) => ColumnFilters(column),
  );

  Expression<bool> loanTopupsRefs(
    Expression<bool> Function($$LoanTopupsTableFilterComposer f) f,
  ) {
    final $$LoanTopupsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.loanTopups,
      getReferencedColumn: (t) => t.loanId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$LoanTopupsTableFilterComposer(
            $db: $db,
            $table: $db.loanTopups,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> loanRepaymentsRefs(
    Expression<bool> Function($$LoanRepaymentsTableFilterComposer f) f,
  ) {
    final $$LoanRepaymentsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.loanRepayments,
      getReferencedColumn: (t) => t.loanId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$LoanRepaymentsTableFilterComposer(
            $db: $db,
            $table: $db.loanRepayments,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$LoansTableOrderingComposer extends Composer<_$AppDb, $LoansTable> {
  $$LoansTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get person => $composableBuilder(
    column: $table.person,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get principal => $composableBuilder(
    column: $table.principal,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get dateLent => $composableBuilder(
    column: $table.dateLent,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get dueDate => $composableBuilder(
    column: $table.dueDate,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get note => $composableBuilder(
    column: $table.note,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get remindAt => $composableBuilder(
    column: $table.remindAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get rev => $composableBuilder(
    column: $table.rev,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get revBy => $composableBuilder(
    column: $table.revBy,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$LoansTableAnnotationComposer extends Composer<_$AppDb, $LoansTable> {
  $$LoansTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get person =>
      $composableBuilder(column: $table.person, builder: (column) => column);

  GeneratedColumn<String> get kind =>
      $composableBuilder(column: $table.kind, builder: (column) => column);

  GeneratedColumn<double> get principal =>
      $composableBuilder(column: $table.principal, builder: (column) => column);

  GeneratedColumn<int> get dateLent =>
      $composableBuilder(column: $table.dateLent, builder: (column) => column);

  GeneratedColumn<int> get dueDate =>
      $composableBuilder(column: $table.dueDate, builder: (column) => column);

  GeneratedColumn<String> get note =>
      $composableBuilder(column: $table.note, builder: (column) => column);

  GeneratedColumn<int> get remindAt =>
      $composableBuilder(column: $table.remindAt, builder: (column) => column);

  GeneratedColumn<int> get rev =>
      $composableBuilder(column: $table.rev, builder: (column) => column);

  GeneratedColumn<String> get revBy =>
      $composableBuilder(column: $table.revBy, builder: (column) => column);

  Expression<T> loanTopupsRefs<T extends Object>(
    Expression<T> Function($$LoanTopupsTableAnnotationComposer a) f,
  ) {
    final $$LoanTopupsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.loanTopups,
      getReferencedColumn: (t) => t.loanId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$LoanTopupsTableAnnotationComposer(
            $db: $db,
            $table: $db.loanTopups,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> loanRepaymentsRefs<T extends Object>(
    Expression<T> Function($$LoanRepaymentsTableAnnotationComposer a) f,
  ) {
    final $$LoanRepaymentsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.loanRepayments,
      getReferencedColumn: (t) => t.loanId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$LoanRepaymentsTableAnnotationComposer(
            $db: $db,
            $table: $db.loanRepayments,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$LoansTableTableManager
    extends
        RootTableManager<
          _$AppDb,
          $LoansTable,
          LoanRow,
          $$LoansTableFilterComposer,
          $$LoansTableOrderingComposer,
          $$LoansTableAnnotationComposer,
          $$LoansTableCreateCompanionBuilder,
          $$LoansTableUpdateCompanionBuilder,
          (LoanRow, $$LoansTableReferences),
          LoanRow,
          PrefetchHooks Function({bool loanTopupsRefs, bool loanRepaymentsRefs})
        > {
  $$LoansTableTableManager(_$AppDb db, $LoansTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$LoansTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$LoansTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$LoansTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> person = const Value.absent(),
                Value<String> kind = const Value.absent(),
                Value<double> principal = const Value.absent(),
                Value<int> dateLent = const Value.absent(),
                Value<int?> dueDate = const Value.absent(),
                Value<String> note = const Value.absent(),
                Value<int> remindAt = const Value.absent(),
                Value<int> rev = const Value.absent(),
                Value<String> revBy = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => LoansCompanion(
                id: id,
                person: person,
                kind: kind,
                principal: principal,
                dateLent: dateLent,
                dueDate: dueDate,
                note: note,
                remindAt: remindAt,
                rev: rev,
                revBy: revBy,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String person,
                required String kind,
                required double principal,
                required int dateLent,
                Value<int?> dueDate = const Value.absent(),
                required String note,
                required int remindAt,
                Value<int> rev = const Value.absent(),
                Value<String> revBy = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => LoansCompanion.insert(
                id: id,
                person: person,
                kind: kind,
                principal: principal,
                dateLent: dateLent,
                dueDate: dueDate,
                note: note,
                remindAt: remindAt,
                rev: rev,
                revBy: revBy,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$LoansTable, LoanRow>(table),
                  $$LoansTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback:
              ({loanTopupsRefs = false, loanRepaymentsRefs = false}) {
                return PrefetchHooks(
                  db: db,
                  explicitlyWatchedTables: [
                    if (loanTopupsRefs) db.loanTopups,
                    if (loanRepaymentsRefs) db.loanRepayments,
                  ],
                  addJoins: null,
                  getPrefetchedDataCallback: (items) async {
                    return [
                      if (loanTopupsRefs)
                        await $_getPrefetchedData<
                          LoanRow,
                          $LoansTable,
                          TopupRow
                        >(
                          currentTable: table,
                          referencedTable: $$LoansTableReferences
                              ._loanTopupsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$LoansTableReferences(
                                db,
                                table,
                                p0,
                              ).loanTopupsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.loanId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (loanRepaymentsRefs)
                        await $_getPrefetchedData<
                          LoanRow,
                          $LoansTable,
                          RepaymentRow
                        >(
                          currentTable: table,
                          referencedTable: $$LoansTableReferences
                              ._loanRepaymentsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$LoansTableReferences(
                                db,
                                table,
                                p0,
                              ).loanRepaymentsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.loanId == item.id,
                              ),
                          typedResults: items,
                        ),
                    ];
                  },
                );
              },
        ),
      );
}

typedef $$LoansTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDb,
      $LoansTable,
      LoanRow,
      $$LoansTableFilterComposer,
      $$LoansTableOrderingComposer,
      $$LoansTableAnnotationComposer,
      $$LoansTableCreateCompanionBuilder,
      $$LoansTableUpdateCompanionBuilder,
      (LoanRow, $$LoansTableReferences),
      LoanRow,
      PrefetchHooks Function({bool loanTopupsRefs, bool loanRepaymentsRefs})
    >;
typedef $$LoanTopupsTableCreateCompanionBuilder = LoanTopupsCompanion Function({
  required String id,
  required String loanId,
  required double amount,
  required int date,
  required String note,
  Value<int> rev,
  Value<String> revBy,
  Value<int> rowid,
});
typedef $$LoanTopupsTableUpdateCompanionBuilder = LoanTopupsCompanion Function({
  Value<String> id,
  Value<String> loanId,
  Value<double> amount,
  Value<int> date,
  Value<String> note,
  Value<int> rev,
  Value<String> revBy,
  Value<int> rowid,
});

final class $$LoanTopupsTableReferences
    extends BaseReferences<_$AppDb, $LoanTopupsTable, TopupRow> {
  $$LoanTopupsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $LoansTable _loanIdTable(_$AppDb db) =>
      db.loans.createAlias('loan_topups__loan_id__loans__id');

  $$LoansTableProcessedTableManager get loanId {
    final $_column = $_itemColumn<String>('loan_id')!;

    final manager = $$LoansTableTableManager(
      $_db,
      $_db.loans,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_loanIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$LoanTopupsTableFilterComposer
    extends Composer<_$AppDb, $LoanTopupsTable> {
  $$LoanTopupsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get amount => $composableBuilder(
    column: $table.amount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get date => $composableBuilder(
    column: $table.date,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get note => $composableBuilder(
    column: $table.note,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get rev => $composableBuilder(
    column: $table.rev,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get revBy => $composableBuilder(
    column: $table.revBy,
    builder: (column) => ColumnFilters(column),
  );

  $$LoansTableFilterComposer get loanId {
    final $$LoansTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.loanId,
      referencedTable: $db.loans,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$LoansTableFilterComposer(
            $db: $db,
            $table: $db.loans,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$LoanTopupsTableOrderingComposer
    extends Composer<_$AppDb, $LoanTopupsTable> {
  $$LoanTopupsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get amount => $composableBuilder(
    column: $table.amount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get date => $composableBuilder(
    column: $table.date,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get note => $composableBuilder(
    column: $table.note,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get rev => $composableBuilder(
    column: $table.rev,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get revBy => $composableBuilder(
    column: $table.revBy,
    builder: (column) => ColumnOrderings(column),
  );

  $$LoansTableOrderingComposer get loanId {
    final $$LoansTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.loanId,
      referencedTable: $db.loans,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$LoansTableOrderingComposer(
            $db: $db,
            $table: $db.loans,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$LoanTopupsTableAnnotationComposer
    extends Composer<_$AppDb, $LoanTopupsTable> {
  $$LoanTopupsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<double> get amount =>
      $composableBuilder(column: $table.amount, builder: (column) => column);

  GeneratedColumn<int> get date =>
      $composableBuilder(column: $table.date, builder: (column) => column);

  GeneratedColumn<String> get note =>
      $composableBuilder(column: $table.note, builder: (column) => column);

  GeneratedColumn<int> get rev =>
      $composableBuilder(column: $table.rev, builder: (column) => column);

  GeneratedColumn<String> get revBy =>
      $composableBuilder(column: $table.revBy, builder: (column) => column);

  $$LoansTableAnnotationComposer get loanId {
    final $$LoansTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.loanId,
      referencedTable: $db.loans,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$LoansTableAnnotationComposer(
            $db: $db,
            $table: $db.loans,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$LoanTopupsTableTableManager
    extends
        RootTableManager<
          _$AppDb,
          $LoanTopupsTable,
          TopupRow,
          $$LoanTopupsTableFilterComposer,
          $$LoanTopupsTableOrderingComposer,
          $$LoanTopupsTableAnnotationComposer,
          $$LoanTopupsTableCreateCompanionBuilder,
          $$LoanTopupsTableUpdateCompanionBuilder,
          (TopupRow, $$LoanTopupsTableReferences),
          TopupRow,
          PrefetchHooks Function({bool loanId})
        > {
  $$LoanTopupsTableTableManager(_$AppDb db, $LoanTopupsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$LoanTopupsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$LoanTopupsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$LoanTopupsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> loanId = const Value.absent(),
                Value<double> amount = const Value.absent(),
                Value<int> date = const Value.absent(),
                Value<String> note = const Value.absent(),
                Value<int> rev = const Value.absent(),
                Value<String> revBy = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => LoanTopupsCompanion(
                id: id,
                loanId: loanId,
                amount: amount,
                date: date,
                note: note,
                rev: rev,
                revBy: revBy,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String loanId,
                required double amount,
                required int date,
                required String note,
                Value<int> rev = const Value.absent(),
                Value<String> revBy = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => LoanTopupsCompanion.insert(
                id: id,
                loanId: loanId,
                amount: amount,
                date: date,
                note: note,
                rev: rev,
                revBy: revBy,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$LoanTopupsTable, TopupRow>(table),
                  $$LoanTopupsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({loanId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (loanId) {
                      state = state.withJoin(
                        currentTable: table,
                        currentColumn: table.loanId,
                        referencedTable: $$LoanTopupsTableReferences
                            ._loanIdTable(db),
                        referencedColumn: $$LoanTopupsTableReferences
                            ._loanIdTable(db)
                            .id,
                      ) as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$LoanTopupsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDb,
      $LoanTopupsTable,
      TopupRow,
      $$LoanTopupsTableFilterComposer,
      $$LoanTopupsTableOrderingComposer,
      $$LoanTopupsTableAnnotationComposer,
      $$LoanTopupsTableCreateCompanionBuilder,
      $$LoanTopupsTableUpdateCompanionBuilder,
      (TopupRow, $$LoanTopupsTableReferences),
      TopupRow,
      PrefetchHooks Function({bool loanId})
    >;
typedef $$LoanRepaymentsTableCreateCompanionBuilder =
    LoanRepaymentsCompanion Function({
      required String id,
      required String loanId,
      required double amount,
      required int date,
      required String note,
      Value<int> rev,
      Value<String> revBy,
      Value<int> rowid,
    });
typedef $$LoanRepaymentsTableUpdateCompanionBuilder =
    LoanRepaymentsCompanion Function({
      Value<String> id,
      Value<String> loanId,
      Value<double> amount,
      Value<int> date,
      Value<String> note,
      Value<int> rev,
      Value<String> revBy,
      Value<int> rowid,
    });

final class $$LoanRepaymentsTableReferences
    extends BaseReferences<_$AppDb, $LoanRepaymentsTable, RepaymentRow> {
  $$LoanRepaymentsTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $LoansTable _loanIdTable(_$AppDb db) =>
      db.loans.createAlias('loan_repayments__loan_id__loans__id');

  $$LoansTableProcessedTableManager get loanId {
    final $_column = $_itemColumn<String>('loan_id')!;

    final manager = $$LoansTableTableManager(
      $_db,
      $_db.loans,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_loanIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$LoanRepaymentsTableFilterComposer
    extends Composer<_$AppDb, $LoanRepaymentsTable> {
  $$LoanRepaymentsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get amount => $composableBuilder(
    column: $table.amount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get date => $composableBuilder(
    column: $table.date,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get note => $composableBuilder(
    column: $table.note,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get rev => $composableBuilder(
    column: $table.rev,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get revBy => $composableBuilder(
    column: $table.revBy,
    builder: (column) => ColumnFilters(column),
  );

  $$LoansTableFilterComposer get loanId {
    final $$LoansTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.loanId,
      referencedTable: $db.loans,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$LoansTableFilterComposer(
            $db: $db,
            $table: $db.loans,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$LoanRepaymentsTableOrderingComposer
    extends Composer<_$AppDb, $LoanRepaymentsTable> {
  $$LoanRepaymentsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get amount => $composableBuilder(
    column: $table.amount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get date => $composableBuilder(
    column: $table.date,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get note => $composableBuilder(
    column: $table.note,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get rev => $composableBuilder(
    column: $table.rev,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get revBy => $composableBuilder(
    column: $table.revBy,
    builder: (column) => ColumnOrderings(column),
  );

  $$LoansTableOrderingComposer get loanId {
    final $$LoansTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.loanId,
      referencedTable: $db.loans,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$LoansTableOrderingComposer(
            $db: $db,
            $table: $db.loans,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$LoanRepaymentsTableAnnotationComposer
    extends Composer<_$AppDb, $LoanRepaymentsTable> {
  $$LoanRepaymentsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<double> get amount =>
      $composableBuilder(column: $table.amount, builder: (column) => column);

  GeneratedColumn<int> get date =>
      $composableBuilder(column: $table.date, builder: (column) => column);

  GeneratedColumn<String> get note =>
      $composableBuilder(column: $table.note, builder: (column) => column);

  GeneratedColumn<int> get rev =>
      $composableBuilder(column: $table.rev, builder: (column) => column);

  GeneratedColumn<String> get revBy =>
      $composableBuilder(column: $table.revBy, builder: (column) => column);

  $$LoansTableAnnotationComposer get loanId {
    final $$LoansTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.loanId,
      referencedTable: $db.loans,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$LoansTableAnnotationComposer(
            $db: $db,
            $table: $db.loans,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$LoanRepaymentsTableTableManager
    extends
        RootTableManager<
          _$AppDb,
          $LoanRepaymentsTable,
          RepaymentRow,
          $$LoanRepaymentsTableFilterComposer,
          $$LoanRepaymentsTableOrderingComposer,
          $$LoanRepaymentsTableAnnotationComposer,
          $$LoanRepaymentsTableCreateCompanionBuilder,
          $$LoanRepaymentsTableUpdateCompanionBuilder,
          (RepaymentRow, $$LoanRepaymentsTableReferences),
          RepaymentRow,
          PrefetchHooks Function({bool loanId})
        > {
  $$LoanRepaymentsTableTableManager(_$AppDb db, $LoanRepaymentsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$LoanRepaymentsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$LoanRepaymentsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$LoanRepaymentsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> loanId = const Value.absent(),
                Value<double> amount = const Value.absent(),
                Value<int> date = const Value.absent(),
                Value<String> note = const Value.absent(),
                Value<int> rev = const Value.absent(),
                Value<String> revBy = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => LoanRepaymentsCompanion(
                id: id,
                loanId: loanId,
                amount: amount,
                date: date,
                note: note,
                rev: rev,
                revBy: revBy,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String loanId,
                required double amount,
                required int date,
                required String note,
                Value<int> rev = const Value.absent(),
                Value<String> revBy = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => LoanRepaymentsCompanion.insert(
                id: id,
                loanId: loanId,
                amount: amount,
                date: date,
                note: note,
                rev: rev,
                revBy: revBy,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$LoanRepaymentsTable, RepaymentRow>(table),
                  $$LoanRepaymentsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({loanId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (loanId) {
                      state = state.withJoin(
                        currentTable: table,
                        currentColumn: table.loanId,
                        referencedTable: $$LoanRepaymentsTableReferences
                            ._loanIdTable(db),
                        referencedColumn: $$LoanRepaymentsTableReferences
                            ._loanIdTable(db)
                            .id,
                      ) as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$LoanRepaymentsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDb,
      $LoanRepaymentsTable,
      RepaymentRow,
      $$LoanRepaymentsTableFilterComposer,
      $$LoanRepaymentsTableOrderingComposer,
      $$LoanRepaymentsTableAnnotationComposer,
      $$LoanRepaymentsTableCreateCompanionBuilder,
      $$LoanRepaymentsTableUpdateCompanionBuilder,
      (RepaymentRow, $$LoanRepaymentsTableReferences),
      RepaymentRow,
      PrefetchHooks Function({bool loanId})
    >;
typedef $$TombstonesTableCreateCompanionBuilder = TombstonesCompanion Function({
  required String type,
  required String recordId,
  required int rev,
  required String revBy,
  Value<int> rowid,
});
typedef $$TombstonesTableUpdateCompanionBuilder = TombstonesCompanion Function({
  Value<String> type,
  Value<String> recordId,
  Value<int> rev,
  Value<String> revBy,
  Value<int> rowid,
});

class $$TombstonesTableFilterComposer
    extends Composer<_$AppDb, $TombstonesTable> {
  $$TombstonesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get type => $composableBuilder(
    column: $table.type,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get recordId => $composableBuilder(
    column: $table.recordId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get rev => $composableBuilder(
    column: $table.rev,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get revBy => $composableBuilder(
    column: $table.revBy,
    builder: (column) => ColumnFilters(column),
  );
}

class $$TombstonesTableOrderingComposer
    extends Composer<_$AppDb, $TombstonesTable> {
  $$TombstonesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get type => $composableBuilder(
    column: $table.type,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get recordId => $composableBuilder(
    column: $table.recordId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get rev => $composableBuilder(
    column: $table.rev,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get revBy => $composableBuilder(
    column: $table.revBy,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$TombstonesTableAnnotationComposer
    extends Composer<_$AppDb, $TombstonesTable> {
  $$TombstonesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get type =>
      $composableBuilder(column: $table.type, builder: (column) => column);

  GeneratedColumn<String> get recordId =>
      $composableBuilder(column: $table.recordId, builder: (column) => column);

  GeneratedColumn<int> get rev =>
      $composableBuilder(column: $table.rev, builder: (column) => column);

  GeneratedColumn<String> get revBy =>
      $composableBuilder(column: $table.revBy, builder: (column) => column);
}

class $$TombstonesTableTableManager
    extends
        RootTableManager<
          _$AppDb,
          $TombstonesTable,
          TombstoneRow,
          $$TombstonesTableFilterComposer,
          $$TombstonesTableOrderingComposer,
          $$TombstonesTableAnnotationComposer,
          $$TombstonesTableCreateCompanionBuilder,
          $$TombstonesTableUpdateCompanionBuilder,
          (
            TombstoneRow,
            BaseReferences<_$AppDb, $TombstonesTable, TombstoneRow>,
          ),
          TombstoneRow,
          PrefetchHooks Function()
        > {
  $$TombstonesTableTableManager(_$AppDb db, $TombstonesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$TombstonesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$TombstonesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$TombstonesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> type = const Value.absent(),
                Value<String> recordId = const Value.absent(),
                Value<int> rev = const Value.absent(),
                Value<String> revBy = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => TombstonesCompanion(
                type: type,
                recordId: recordId,
                rev: rev,
                revBy: revBy,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String type,
                required String recordId,
                required int rev,
                required String revBy,
                Value<int> rowid = const Value.absent(),
              }) => TombstonesCompanion.insert(
                type: type,
                recordId: recordId,
                rev: rev,
                revBy: revBy,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$TombstonesTable, TombstoneRow>(table),
                  BaseReferences<_$AppDb, $TombstonesTable, TombstoneRow>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$TombstonesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDb,
      $TombstonesTable,
      TombstoneRow,
      $$TombstonesTableFilterComposer,
      $$TombstonesTableOrderingComposer,
      $$TombstonesTableAnnotationComposer,
      $$TombstonesTableCreateCompanionBuilder,
      $$TombstonesTableUpdateCompanionBuilder,
      (TombstoneRow, BaseReferences<_$AppDb, $TombstonesTable, TombstoneRow>),
      TombstoneRow,
      PrefetchHooks Function()
    >;

class $AppDbManager {
  final _$AppDb _db;
  $AppDbManager(this._db);
  $$CategoriesTableTableManager get categories =>
      $$CategoriesTableTableManager(_db, _db.categories);
  $$TransactionsTableTableManager get transactions =>
      $$TransactionsTableTableManager(_db, _db.transactions);
  $$ProjectsTableTableManager get projects =>
      $$ProjectsTableTableManager(_db, _db.projects);
  $$LoansTableTableManager get loans =>
      $$LoansTableTableManager(_db, _db.loans);
  $$LoanTopupsTableTableManager get loanTopups =>
      $$LoanTopupsTableTableManager(_db, _db.loanTopups);
  $$LoanRepaymentsTableTableManager get loanRepayments =>
      $$LoanRepaymentsTableTableManager(_db, _db.loanRepayments);
  $$TombstonesTableTableManager get tombstones =>
      $$TombstonesTableTableManager(_db, _db.tombstones);
}
