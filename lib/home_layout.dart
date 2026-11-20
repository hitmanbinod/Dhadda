import 'dart:convert';

/// Sections the Home dashboard can show, in the order they appear by
/// default. The profile header and month title are fixed and never part of
/// this list; Balance is locked to the top.
enum HomeSection {
  balance,
  stats,
  categories,
  budgets,
  events,
  recent,
  todayRing,
  rhythm,
  forecast,
}

/// Section copy and defaults used by Home and the Edit Home screen.
extension HomeSectionInfo on HomeSection {
  String get id => switch (this) {
    HomeSection.balance => 'balance',
    HomeSection.stats => 'stats',
    HomeSection.categories => 'categories',
    HomeSection.budgets => 'budgets',
    HomeSection.events => 'events',
    HomeSection.recent => 'recent',
    HomeSection.todayRing => 'todayRing',
    HomeSection.rhythm => 'rhythm',
    HomeSection.forecast => 'forecast',
  };

  String get title => switch (this) {
    HomeSection.balance => 'Balance',
    HomeSection.stats => 'Stats',
    HomeSection.categories => 'Categories',
    HomeSection.budgets => 'Budgets',
    HomeSection.events => 'Events',
    HomeSection.recent => 'Recent',
    HomeSection.todayRing => 'Today',
    HomeSection.rhythm => 'Daily rhythm',
    HomeSection.forecast => 'Forecast',
  };

  String get description => switch (this) {
    HomeSection.balance => 'Your month balance, with the hide eye.',
    HomeSection.stats => 'Spent, income and lent out at a glance.',
    HomeSection.categories => 'Stacked bar and category breakdown.',
    HomeSection.budgets => 'Only appears when a category has a budget.',
    HomeSection.events => 'This month’s event groups.',
    HomeSection.recent => 'Latest entries with edit and swipe to delete.',
    HomeSection.todayRing => 'Today’s spending against a daily allowance.',
    HomeSection.rhythm => 'One bar per day; tap a day to open History.',
    HomeSection.forecast => 'A month-end projection at this month’s pace.',
  };

  bool get defaultVisible => switch (this) {
    HomeSection.events ||
    HomeSection.todayRing ||
    HomeSection.rhythm ||
    HomeSection.forecast => false,
    _ => true,
  };

  /// Balance cannot be hidden or moved from the top.
  bool get locked => this == HomeSection.balance;
}

HomeSection? homeSectionFromId(String id) {
  for (final section in HomeSection.values) {
    if (section.id == id) return section;
  }
  return null;
}

/// One persisted row in the Home layout.
class HomeSectionSetting {
  final HomeSection section;
  final bool visible;

  const HomeSectionSetting({required this.section, required this.visible});

  HomeSectionSetting copyWith({bool? visible}) =>
      HomeSectionSetting(section: section, visible: visible ?? this.visible);

  Map<String, Object> toJson() => {'id': section.id, 'visible': visible};

  @override
  bool operator ==(Object other) =>
      other is HomeSectionSetting &&
      other.section == section &&
      other.visible == visible;

  @override
  int get hashCode => Object.hash(section, visible);

  @override
  String toString() => 'HomeSectionSetting(${section.id}, $visible)';
}

const _defaultOrder = [
  HomeSection.balance,
  HomeSection.stats,
  HomeSection.categories,
  HomeSection.budgets,
  HomeSection.events,
  HomeSection.recent,
  HomeSection.todayRing,
  HomeSection.rhythm,
  HomeSection.forecast,
];

/// Clean first-run layout: header, balance, stats, categories, recent.
/// Budgets render only when they have content; Events stays off until the
/// user enables it. This affects new installs and Reset to default only —
/// a saved layout is decoded exactly as stored, never migrated here.
List<HomeSectionSetting> defaultHomeLayout() => [
  for (final section in _defaultOrder)
    HomeSectionSetting(section: section, visible: section.defaultVisible),
];

/// Keeps Balance first and visible, drops duplicates, and appends sections
/// that are absent from a saved layout as hidden (so a later version can add
/// a section without surprising existing users).
List<HomeSectionSetting> normalizeHomeLayout(
  Iterable<HomeSectionSetting> input,
) {
  final seen = <HomeSection>{};
  final rest = <HomeSectionSetting>[];
  for (final setting in input) {
    final section = setting.section;
    if (section == HomeSection.balance) continue;
    if (!seen.add(section)) continue;
    rest.add(setting);
  }
  for (final section in HomeSection.values) {
    if (section == HomeSection.balance || seen.contains(section)) continue;
    rest.add(HomeSectionSetting(section: section, visible: false));
  }
  return [
    const HomeSectionSetting(section: HomeSection.balance, visible: true),
    ...rest,
  ];
}

/// Decodes `home_layout_v1`. Unknown ids are ignored; an absent or corrupt
/// layout falls back to the defaults.
List<HomeSectionSetting> decodeHomeLayout(String? raw) {
  if (raw == null || raw.trim().isEmpty) return defaultHomeLayout();
  try {
    final decoded = jsonDecode(raw);
    if (decoded is! List) return defaultHomeLayout();
    final settings = <HomeSectionSetting>[];
    for (final item in decoded) {
      if (item is! Map) continue;
      final section = homeSectionFromId('${item['id'] ?? ''}');
      if (section == null) continue;
      settings.add(
        HomeSectionSetting(section: section, visible: item['visible'] == true),
      );
    }
    if (settings.isEmpty) return defaultHomeLayout();
    return normalizeHomeLayout(settings);
  } catch (_) {
    return defaultHomeLayout();
  }
}

String encodeHomeLayout(Iterable<HomeSectionSetting> layout) => jsonEncode([
  for (final setting in normalizeHomeLayout(layout)) setting.toJson(),
]);

/// Moves one row using ReorderableListView's `onReorderItem` indices, which
/// already account for the removed item. Balance is pinned at 0, so anything
/// dropped above it lands directly below it.
List<HomeSectionSetting> moveHomeSectionInLayout(
  List<HomeSectionSetting> layout,
  int oldIndex,
  int newIndex,
) {
  final next = [...layout];
  if (oldIndex <= 0 || oldIndex >= next.length) return next;
  final maxTarget = next.length - 1;
  if (maxTarget < 1) return next;
  final target = newIndex.clamp(1, maxTarget);
  final moved = next.removeAt(oldIndex);
  next.insert(target, moved);
  return next;
}
