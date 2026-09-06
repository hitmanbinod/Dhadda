import 'dart:convert';

import 'package:flutter/material.dart';

/// Currency shown across the app. Single-user MVP: one fixed symbol.
const kCurrencySymbol = '\u20B9';

/// Snapshot file-format version. Bump if fields change incompatibly.
const kSnapshotVersion = 1;

/// Icon + color palettes users can pick from (categories & events).
/// All const IconData so display never constructs fonts at runtime.
const kIconChoices = [
  Icons.restaurant,
  Icons.directions_bus,
  Icons.local_gas_station,
  Icons.home,
  Icons.shopping_bag,
  Icons.receipt_long,
  Icons.favorite,
  Icons.category,
  Icons.flight,
  Icons.hotel,
  Icons.coffee,
  Icons.shopping_cart,
  Icons.directions_car,
  Icons.train,
  Icons.local_hospital,
  Icons.school,
  Icons.sports_soccer,
  Icons.movie,
  Icons.music_note,
  Icons.pets,
  Icons.fitness_center,
  Icons.work,
  Icons.savings,
  Icons.celebration,
];

const kColorChoices = [
  0xFFEF6C00,
  0xFF1565C0,
  0xFF6A1B9A,
  0xFFC2185B,
  0xFF2E7D32,
  0xFF009688,
  0xFFC62828,
  0xFFFFA000,
  0xFF795548,
  0xFF3949AB,
  0xFF827717,
  0xFF607D8B,
];

class Category {
  final String id;
  final String name;
  final int icon;
  final int color;
  final double budget;

  const Category({
    required this.id,
    required this.name,
    required this.icon,
    required this.color,
    this.budget = 0,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'icon': icon,
        'color': color,
        'budget': budget,
      };

  factory Category.fromJson(Map<String, dynamic> json) => Category(
        id: '${json['id'] ?? ''}',
        name: '${json['name'] ?? 'Other'}',
        icon: json['icon'] is int
            ? json['icon'] as int
            : Icons.category.codePoint,
        color:
            json['color'] is int ? json['color'] as int : 0xFF607D8B,
        budget: json['budget'] is num
            ? (json['budget'] as num).toDouble()
            : 0,
      );

  /// Display icon: the stored pick wins, legacy ids fall back
  /// to their original icon.
  IconData get iconData {
    for (final i in kIconChoices) {
      if (i.codePoint == icon) return i;
    }
    switch (id) {
      case 'food':
        return Icons.restaurant;
      case 'travel':
        return Icons.directions_bus;
      case 'rent':
        return Icons.home;
      case 'shopping':
        return Icons.shopping_bag;
      case 'bills':
        return Icons.receipt_long;
      case 'health':
        return Icons.favorite;
      default:
        return Icons.category;
    }
  }

  Color get colorValue => Color(color);
}

/// Added after v1.0: existing installs receive it via migration in load().
Category fuelDefault() => Category(
      id: 'fuel',
      name: 'Fuel',
      icon: Icons.local_gas_station.codePoint,
      color: 0xFF795548,
    );

List<Category> defaultCategories() => [
      Category(
          id: 'food',
          name: 'Food',
          icon: Icons.restaurant.codePoint,
          color: 0xFFEF6C00),
      Category(
          id: 'travel',
          name: 'Travel',
          icon: Icons.directions_bus.codePoint,
          color: 0xFF1565C0),
      fuelDefault(),
      Category(
          id: 'rent',
          name: 'Rent',
          icon: Icons.home.codePoint,
          color: 0xFF6A1B9A),
      Category(
          id: 'shopping',
          name: 'Shopping',
          icon: Icons.shopping_bag.codePoint,
          color: 0xFFC2185B),
      Category(
          id: 'bills',
          name: 'Bills',
          icon: Icons.receipt_long.codePoint,
          color: 0xFF00838F),
      Category(
          id: 'health',
          name: 'Health',
          icon: Icons.favorite.codePoint,
          color: 0xFF2E7D32),
      Category(
          id: 'other',
          name: 'Other',
          icon: Icons.category.codePoint,
          color: 0xFF607D8B),
    ];

class Txn {
  final String id;
  final String type; // 'expense' | 'income'
  final double amount;
  final String categoryId;
  final int date; // epoch millis
  final String note;
  final String mode; // cash | bank | card | ewallet
  final String projectId; // '' = none

  const Txn({
    required this.id,
    required this.type,
    required this.amount,
    required this.categoryId,
    required this.date,
    this.note = '',
    this.mode = 'cash',
    this.projectId = '',
  });

  bool get isExpense => type == 'expense';
  DateTime get dateTime => DateTime.fromMillisecondsSinceEpoch(date);

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type,
        'amount': amount,
        'categoryId': categoryId,
        'date': date,
        'note': note,
        'mode': mode,
        'projectId': projectId,
      };

  factory Txn.fromJson(Map<String, dynamic> json) => Txn(
        id: '${json['id'] ?? ''}',
        type: json['type'] == 'income' ? 'income' : 'expense',
        amount:
            json['amount'] is num ? (json['amount'] as num).toDouble() : 0,
        categoryId: '${json['categoryId'] ?? 'other'}',
        date: json['date'] is int
            ? json['date'] as int
            : DateTime.now().millisecondsSinceEpoch,
        note: '${json['note'] ?? ''}',
        mode: '${json['mode'] ?? 'cash'}',
        projectId: '${json['projectId'] ?? ''}',
      );
}

class Repayment {
  final String id;
  final double amount;
  final int date;
  final String note;

  const Repayment({
    required this.id,
    required this.amount,
    required this.date,
    this.note = '',
  });

  Map<String, dynamic> toJson() =>
      {'id': id, 'amount': amount, 'date': date, 'note': note};

  factory Repayment.fromJson(Map<String, dynamic> json) => Repayment(
        id: '${json['id'] ?? ''}',
        amount:
            json['amount'] is num ? (json['amount'] as num).toDouble() : 0,
        date: json['date'] is int
            ? json['date'] as int
            : DateTime.now().millisecondsSinceEpoch,
        note: '${json['note'] ?? ''}',
      );
}

/// Extra money lent later to the same person (top-up).
/// Same shape as a repayment, opposite direction.
class Topup {
  final String id;
  final double amount;
  final int date;
  final String note;

  const Topup({
    required this.id,
    required this.amount,
    required this.date,
    this.note = '',
  });

  Map<String, dynamic> toJson() =>
      {'id': id, 'amount': amount, 'date': date, 'note': note};

  factory Topup.fromJson(Map<String, dynamic> json) => Topup(
        id: '${json['id'] ?? ''}',
        amount:
            json['amount'] is num ? (json['amount'] as num).toDouble() : 0,
        date: json['date'] is int
            ? json['date'] as int
            : DateTime.now().millisecondsSinceEpoch,
        note: '${json['note'] ?? ''}',
      );
}

/// One-time nudge for a lent/borrowed entry, as epoch millis.
/// 0 (or missing) means off. Pre-one-time versions stored repeating
/// schedules ('daily' etc) - those are honored once, tomorrow at 9 AM.
int _legacyRemindAt(Object? v) {
  if (v != 'daily' && v != 'weekly' && v != 'monthly') return 0;
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day, 9)
      .add(const Duration(days: 1))
      .millisecondsSinceEpoch;
}

class Loan {
  final String id;
  final String person;
  final double lent;
  final int dateLent;
  final int? dueDate;
  final String note;
  final List<Repayment> repayments;
  final List<Topup> topups;
  /// 'lent' (you gave) or 'borrowed' (you took). Same math both ways:
  /// pending = principal - repaid.
  final String kind;
  /// One-time reminder moment as epoch millis. 0 = off.
  final int remindAt;

  const Loan({
    required this.id,
    required this.person,
    required this.lent,
    required this.dateLent,
    this.dueDate,
    this.note = '',
    this.repayments = const [],
    this.topups = const [],
    this.kind = 'lent',
    this.remindAt = 0,
  });

  bool get isBorrowed => kind == 'borrowed';

  double get returned =>
      repayments.fold(0, (sum, r) => sum + r.amount);
  double get extraLent =>
      topups.fold(0, (sum, t) => sum + t.amount);
  double get totalLent => lent + extraLent;
  double get pending => totalLent - returned;
  bool get settled => pending <= 0.005;

  Map<String, dynamic> toJson() => {
        'id': id,
        'person': person,
        'lent': lent,
        'dateLent': dateLent,
        'dueDate': dueDate,
        'note': note,
        'repayments': repayments.map((r) => r.toJson()).toList(),
        'topups': topups.map((t) => t.toJson()).toList(),
        'kind': kind,
        'remindAt': remindAt,
      };

  factory Loan.fromJson(Map<String, dynamic> json) => Loan(
        id: '${json['id'] ?? ''}',
        person: '${json['person'] ?? ''}',
        lent: json['lent'] is num ? (json['lent'] as num).toDouble() : 0,
        dateLent: json['dateLent'] is int
            ? json['dateLent'] as int
            : DateTime.now().millisecondsSinceEpoch,
        dueDate: json['dueDate'] is int ? json['dueDate'] as int : null,
        note: '${json['note'] ?? ''}',
        kind: json['kind'] == 'borrowed' ? 'borrowed' : 'lent',
        remindAt: json['remindAt'] is int
            ? json['remindAt'] as int
            : _legacyRemindAt(json['remindFreq']),
        repayments: json['repayments'] is List
            ? (json['repayments'] as List)
                .whereType<Map<String, dynamic>>()
                .map(Repayment.fromJson)
                .toList()
            : const [],
        topups: json['topups'] is List
            ? (json['topups'] as List)
                .whereType<Map<String, dynamic>>()
                .map(Topup.fromJson)
                .toList()
            : const [],
      );
}

/// An event pot (trekking, outing...). Expenses can be tagged with one
/// to see what a whole trip cost.
class Project {
  final String id;
  final String name;
  final String note;
  final int created;
  final int icon;
  final int color;

  const Project({
    required this.id,
    required this.name,
    this.note = '',
    required this.created,
    this.icon = 0,
    this.color = 0xFF009688,
  });

  IconData get iconData {
    for (final i in kIconChoices) {
      if (i.codePoint == icon) return i;
    }
    return Icons.event;
  }

  Color get colorValue => Color(color);

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'note': note,
        'created': created,
        'icon': icon,
        'color': color,
      };

  factory Project.fromJson(Map<String, dynamic> json) => Project(
        id: '${json['id'] ?? ''}',
        name: '${json['name'] ?? 'Event'}',
        note: '${json['note'] ?? ''}',
        created: json['created'] is int
            ? json['created'] as int
            : DateTime.now().millisecondsSinceEpoch,
        icon: json['icon'] is int ? json['icon'] as int : 0,
        color: json['color'] is int
            ? json['color'] as int
            : 0xFF009688,
      );
}

/// Whole database as one portable JSON document.
/// Sync (file or WiFi) always exchanges a Snapshot, never the live DB.
class Snapshot {
  final int version;
  final String updatedAt; // ISO-8601 UTC
  final String deviceId;
  final String deviceName;
  final List<Category> categories;
  final List<Txn> transactions;
  final List<Loan> loans;
  final List<Project> projects;

  const Snapshot({
    required this.version,
    required this.updatedAt,
    required this.deviceId,
    required this.deviceName,
    required this.categories,
    required this.transactions,
    required this.loans,
    required this.projects,
  });

  Map<String, dynamic> toJson() => {
        'version': version,
        'updatedAt': updatedAt,
        'deviceId': deviceId,
        'deviceName': deviceName,
        'categories': categories.map((c) => c.toJson()).toList(),
        'transactions': transactions.map((t) => t.toJson()).toList(),
        'loans': loans.map((l) => l.toJson()).toList(),
        'projects': projects.map((p) => p.toJson()).toList(),
      };

  factory Snapshot.fromJson(Map<String, dynamic> json) {
    List<T> listOf<T>(Object? v, T Function(Map<String, dynamic>) f) {
      if (v is! List) return <T>[];
      return v.whereType<Map<String, dynamic>>().map(f).toList();
    }

    return Snapshot(
      version: json['version'] is int ? json['version'] as int : 1,
      updatedAt: '${json['updatedAt'] ?? ''}',
      deviceId: '${json['deviceId'] ?? ''}',
      deviceName: '${json['deviceName'] ?? 'device'}',
      categories: listOf(json['categories'], Category.fromJson),
      transactions: listOf(json['transactions'], Txn.fromJson),
      loans: listOf(json['loans'], Loan.fromJson),
      projects: listOf(json['projects'], Project.fromJson),
    );
  }

  String encode() => jsonEncode(toJson());

  static Snapshot decode(String raw) =>
      Snapshot.fromJson(jsonDecode(raw) as Map<String, dynamic>);

  DateTime get updatedAtTime =>
      DateTime.tryParse(updatedAt) ??
      DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
}