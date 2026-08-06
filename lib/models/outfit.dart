import 'dart:convert';

/// Tags a saved look can carry. Mirrors the reference app's set.
enum LookTag {
  casual,
  work,
  formal,
  sporty,
  party;

  String get label => switch (this) {
    LookTag.casual => 'Casual',
    LookTag.work => 'Work',
    LookTag.formal => 'Formal',
    LookTag.sporty => 'Sporty',
    LookTag.party => 'Party',
  };

  static LookTag fromName(String? name) => LookTag.values.firstWhere(
    (t) => t.name == name,
    orElse: () => LookTag.casual,
  );
}

/// A saved outfit: the garments, the generated preview, and how it scored.
class Look {
  final String id;

  /// Item ids, in the order they were chosen.
  final List<String> itemIds;

  /// Preview file name inside the previews directory, or null if the user
  /// saved the combination without rendering it.
  final String? previewFileName;

  final LookTag tag;

  /// Mean pairwise score at save time, kept so the card can show a number
  /// without recomputing anything.
  final double? score;

  final DateTime createdAt;

  const Look({
    required this.id,
    required this.itemIds,
    required this.previewFileName,
    required this.tag,
    required this.score,
    required this.createdAt,
  });

  factory Look.fromRow(Map<String, Object?> row) {
    List<String> ids() {
      final raw = row['item_ids'] as String?;
      if (raw == null || raw.isEmpty) return const [];
      try {
        final parsed = jsonDecode(raw);
        if (parsed is! List) return const [];
        return parsed.map((e) => e.toString()).toList(growable: false);
      } on FormatException {
        return const [];
      }
    }

    return Look(
      id: row['id'] as String,
      itemIds: ids(),
      previewFileName: row['preview_file'] as String?,
      tag: LookTag.fromName(row['tag'] as String?),
      score: (row['score'] as num?)?.toDouble(),
      createdAt: DateTime.fromMillisecondsSinceEpoch(row['created_at'] as int),
    );
  }

  Map<String, Object?> toRow() => {
    'id': id,
    'item_ids': jsonEncode(itemIds),
    'preview_file': previewFileName,
    'tag': tag.name,
    'score': score,
    'created_at': createdAt.millisecondsSinceEpoch,
  };
}
