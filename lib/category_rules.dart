// Pure Dart, ordered "note contains -> category" rules. No I/O: the store
// owns the pref. The first enabled, valid rule wins.
import 'dart:convert';

enum CategoryRuleType { expense, income, any }

class CategoryRule {
  final String id;
  final String text;
  final String categoryId;
  final CategoryRuleType type;
  final bool enabled;

  const CategoryRule({
    required this.id,
    required this.text,
    required this.categoryId,
    this.type = CategoryRuleType.any,
    this.enabled = true,
  });

  CategoryRule copyWith({
    String? text,
    String? categoryId,
    CategoryRuleType? type,
    bool? enabled,
  }) =>
      CategoryRule(
        id: id,
        text: text ?? this.text,
        categoryId: categoryId ?? this.categoryId,
        type: type ?? this.type,
        enabled: enabled ?? this.enabled,
      );

  Map<String, Object> toJson() => {
        'id': id,
        'text': text,
        'categoryId': categoryId,
        'type': type.name,
        'enabled': enabled,
      };

  factory CategoryRule.fromJson(Map<String, dynamic> json) => CategoryRule(
        id: '${json['id'] ?? ''}',
        text: '${json['text'] ?? ''}',
        categoryId: '${json['categoryId'] ?? ''}',
        type: CategoryRuleType.values.firstWhere(
          (t) => t.name == json['type'],
          orElse: () => CategoryRuleType.any,
        ),
        enabled: json['enabled'] != false,
      );

  @override
  bool operator ==(Object other) =>
      other is CategoryRule &&
      other.id == id &&
      other.text == text &&
      other.categoryId == categoryId &&
      other.type == type &&
      other.enabled == enabled;

  @override
  int get hashCode => Object.hash(id, text, categoryId, type, enabled);
}

String normalizeRuleText(String raw) =>
    raw.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

bool isValidRuleText(String raw) => normalizeRuleText(raw).length >= 2;

/// The first enabled rule whose text is contained in [note] and whose type
/// matches. Orphaned rules (deleted category) are skipped, not deleted.
CategoryRule? matchCategoryRule(
  Iterable<CategoryRule> rules, {
  required String note,
  required String type,
  required Set<String> validCategoryIds,
}) {
  final haystack = normalizeRuleText(note);
  if (haystack.length < 2) return null;
  for (final rule in rules) {
    if (!rule.enabled) continue;
    if (!validCategoryIds.contains(rule.categoryId)) continue;
    if (rule.type != CategoryRuleType.any && rule.type.name != type) {
      continue;
    }
    final needle = normalizeRuleText(rule.text);
    if (needle.length < 2) {
      continue;
    }
    if (haystack.contains(needle)) return rule;
  }
  return null;
}

List<CategoryRule> decodeCategoryRules(String? raw) {
  if (raw == null || raw.trim().isEmpty) return [];
  try {
    final decoded = jsonDecode(raw);
    if (decoded is! List) return [];
    return [
      for (final item in decoded)
        if (item is Map) CategoryRule.fromJson(Map<String, dynamic>.from(item)),
    ];
  } catch (_) {
    return [];
  }
}

String encodeCategoryRules(Iterable<CategoryRule> rules) =>
    jsonEncode([for (final rule in rules) rule.toJson()]);

/// Moves one row using ReorderableListView's onReorderItem indices.
List<CategoryRule> moveCategoryRule(
  List<CategoryRule> rules,
  int oldIndex,
  int newIndex,
) {
  if (oldIndex < 0 || oldIndex >= rules.length) return rules;
  final next = [...rules];
  final moved = next.removeAt(oldIndex);
  final target = newIndex.clamp(0, next.length);
  next.insert(target, moved);
  return next;
}
