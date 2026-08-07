import 'dart:convert';

/// Order-independent key for a pair of item ids.
///
/// Sorting means a pairing is stored and scored exactly once, whichever way
/// round the caller happens to hold it.
String pairKeyFor(String a, String b) {
  final ids = <String>[a, b]..sort();
  return '${ids[0]}__${ids[1]}';
}

/// A cached verdict on exactly two garments.
///
/// There is deliberately no description field. The user is looking at the two
/// photos, so every list here has to tell them something the photos cannot.
class PairScore {
  final String pairKey;
  final String itemA;
  final String itemB;

  /// 0.0 - 10.0
  final double score;

  /// What is earning points.
  final List<String> boosting;

  /// What is costing points.
  final List<String> costing;

  /// Specific changes that would raise the score.
  final List<String> improve;

  /// Footwear that would complete the pairing.
  final List<String> shoes;

  /// Accessories that would complete the pairing.
  final List<String> accessories;

  /// False when the model did not see two scoreable garments.
  final bool valid;

  final String model;

  /// Stamped so a rubric change can invalidate old verdicts instead of
  /// silently mixing two scoring standards in one grid.
  final int promptVersion;

  /// Identity of the wearer context this was judged under.
  ///
  /// `none` when no styling fields were set. Part of the cache key: a verdict
  /// produced for a different wearer is not comparable, so it is a miss rather
  /// than a stale-but-usable hit.
  final String profileFingerprint;

  final DateTime scoredAt;

  const PairScore({
    required this.pairKey,
    required this.itemA,
    required this.itemB,
    required this.score,
    required this.boosting,
    required this.costing,
    required this.improve,
    required this.shoes,
    required this.accessories,
    required this.valid,
    required this.model,
    required this.promptVersion,
    required this.profileFingerprint,
    required this.scoredAt,
  });

  /// Builds a verdict from the model's JSON reply.
  factory PairScore.fromModelJson(
    Map<String, dynamic> json, {
    required String itemIdA,
    required String itemIdB,
    required String model,
    required int promptVersion,
    required String profileFingerprint,
  }) {
    List<String> list(String field) {
      final raw = json[field];
      if (raw is! List) return const [];
      return raw
          .map((e) => e.toString().trim())
          .where((e) => e.isNotEmpty)
          .toList(growable: false);
    }

    final raw = json['score'];
    final parsed =
        raw is num
            ? raw.toDouble()
            : double.tryParse(raw?.toString() ?? '') ?? 0.0;

    final ids = <String>[itemIdA, itemIdB]..sort();

    return PairScore(
      pairKey: pairKeyFor(itemIdA, itemIdB),
      itemA: ids[0],
      itemB: ids[1],
      score: parsed.clamp(0.0, 10.0),
      boosting: list('boosting'),
      costing: list('costing'),
      improve: list('improve'),
      shoes: list('shoes'),
      accessories: list('accessories'),
      valid: json['valid'] as bool? ?? true,
      model: model,
      promptVersion: promptVersion,
      profileFingerprint: profileFingerprint,
      scoredAt: DateTime.now(),
    );
  }

  factory PairScore.fromRow(Map<String, Object?> row) {
    List<String> decode(String field) {
      final raw = row[field] as String?;
      if (raw == null || raw.isEmpty) return const [];
      try {
        final parsed = jsonDecode(raw);
        if (parsed is! List) return const [];
        return parsed.map((e) => e.toString()).toList(growable: false);
      } on FormatException {
        return const [];
      }
    }

    return PairScore(
      pairKey: row['pair_key'] as String,
      itemA: row['item_a'] as String,
      itemB: row['item_b'] as String,
      score: (row['score'] as num).toDouble(),
      boosting: decode('boosting'),
      costing: decode('costing'),
      improve: decode('improve'),
      shoes: decode('shoes'),
      accessories: decode('accessories'),
      valid: (row['valid'] as int) == 1,
      model: row['model'] as String? ?? '',
      promptVersion: (row['prompt_version'] as int?) ?? 0,
      profileFingerprint: row['profile_fp'] as String? ?? 'none',
      scoredAt: DateTime.fromMillisecondsSinceEpoch(row['scored_at'] as int),
    );
  }

  Map<String, Object?> toRow() => {
    'pair_key': pairKey,
    'item_a': itemA,
    'item_b': itemB,
    'score': score,
    'boosting': jsonEncode(boosting),
    'costing': jsonEncode(costing),
    'improve': jsonEncode(improve),
    'shoes': jsonEncode(shoes),
    'accessories': jsonEncode(accessories),
    'valid': valid ? 1 : 0,
    'model': model,
    'prompt_version': promptVersion,
    'profile_fp': profileFingerprint,
    'scored_at': scoredAt.millisecondsSinceEpoch,
  };

  /// The other half of the pairing, given one side of it.
  String otherThan(String itemId) => itemId == itemA ? itemB : itemA;

  bool involves(String itemId) => itemId == itemA || itemId == itemB;
}

/// A candidate garment ranked against a set of already-chosen garments.
class ScoredCandidate {
  final String itemId;

  /// Mean of this candidate's pairwise scores against every chosen item.
  final double averageScore;

  /// The pairwise breakdown, keyed by the chosen item's id.
  final Map<String, PairScore> pairs;

  const ScoredCandidate({
    required this.itemId,
    required this.averageScore,
    required this.pairs,
  });

  /// The pairing dragging the average down hardest, so the UI can say
  /// "great with the jacket, fighting the trousers".
  PairScore? get weakestPair {
    if (pairs.isEmpty) return null;
    final sorted =
        pairs.values.toList()..sort((a, b) => a.score.compareTo(b.score));
    return sorted.first;
  }

  PairScore? get strongestPair {
    if (pairs.isEmpty) return null;
    final sorted =
        pairs.values.toList()..sort((a, b) => b.score.compareTo(a.score));
    return sorted.first;
  }

  /// Combined advice across every pairing, de-duplicated, best-first.
  List<String> get allShoes => _merge((p) => p.shoes);
  List<String> get allAccessories => _merge((p) => p.accessories);
  List<String> get allImprove => _merge((p) => p.improve);

  List<String> _merge(List<String> Function(PairScore) pick) {
    final seen = <String>{};
    final out = <String>[];
    final ordered =
        pairs.values.toList()..sort((a, b) => b.score.compareTo(a.score));
    for (final pair in ordered) {
      for (final entry in pick(pair)) {
        final key = entry.toLowerCase();
        if (seen.add(key)) out.add(entry);
      }
    }
    return out;
  }
}
