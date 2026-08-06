import 'package:flutter/foundation.dart';

import '../data/score_repository.dart';
import '../models/clothing_item.dart';
import '../models/pair_score.dart';
import '../services/gemini_service.dart';
import 'closet_viewmodel.dart';

enum CombinationSort { bestFirst, worstFirst, newestFirst }

/// A cached pairing joined to its two garments, ready to render.
class Combination {
  final PairScore score;
  final ClothingItem a;
  final ClothingItem b;

  const Combination({required this.score, required this.a, required this.b});
}

/// Everything the app has ever scored, as a browsable grid.
///
/// This screen never calls the model. It is pure cache readback, which is the
/// entire point: scoring is the expensive part, so once a pairing has been
/// judged, looking at it again should be instant and free. The grid fills in as
/// a side effect of using Match, and nothing here ever adds to the bill.
class CombinationsViewModel extends ChangeNotifier {
  final ScoreRepository _scores;
  final ClosetViewModel _closet;

  CombinationsViewModel({
    required ScoreRepository scores,
    required ClosetViewModel closet,
  }) : _scores = scores,
       _closet = closet {
    load();
  }

  bool _loading = true;
  bool get loading => _loading;

  List<Combination> _all = const [];

  CombinationSort _sort = CombinationSort.bestFirst;
  CombinationSort get sort => _sort;

  GarmentCategory? _filter;
  GarmentCategory? get filter => _filter;

  /// How many pairings exist in total, regardless of filtering.
  int get totalCached => _all.length;

  /// Pairings after the active filter and sort.
  List<Combination> get visible {
    var list = _all;

    final filter = _filter;
    if (filter != null) {
      list = list
          .where((c) => c.a.category == filter || c.b.category == filter)
          .toList(growable: false);
    }

    final sorted = List<Combination>.of(list);
    switch (_sort) {
      case CombinationSort.bestFirst:
        sorted.sort((x, y) => y.score.score.compareTo(x.score.score));
      case CombinationSort.worstFirst:
        sorted.sort((x, y) => x.score.score.compareTo(y.score.score));
      case CombinationSort.newestFirst:
        sorted.sort((x, y) => y.score.scoredAt.compareTo(x.score.scoredAt));
    }
    return sorted;
  }

  /// Categories that actually appear in the cache, for the filter row.
  List<GarmentCategory> get availableCategories {
    final present = <GarmentCategory>{};
    for (final combo in _all) {
      present.add(combo.a.category);
      present.add(combo.b.category);
    }
    return GarmentCategory.values.where(present.contains).toList(growable: false);
  }

  /// Mean score across everything cached, or null when empty.
  double? get averageScore {
    if (_all.isEmpty) return null;
    final total = _all.map((c) => c.score.score).reduce((a, b) => a + b);
    return total / _all.length;
  }

  /// The single best pairing found so far.
  Combination? get best {
    if (_all.isEmpty) return null;
    final sorted = List<Combination>.of(_all)
      ..sort((x, y) => y.score.score.compareTo(x.score.score));
    return sorted.first;
  }

  Future<void> load() async {
    _loading = true;
    notifyListeners();

    try {
      final rows = await _scores.allRanked(
        promptVersion: GeminiService.promptVersion,
      );

      // Join against the closet in memory. A pairing whose garment has been
      // deleted is dropped rather than rendered as a hole; the database cascade
      // removes it properly, this just guards the window before a reload.
      final joined = <Combination>[];
      for (final score in rows) {
        final a = _closet.byId(score.itemA);
        final b = _closet.byId(score.itemB);
        if (a == null || b == null) continue;
        joined.add(Combination(score: score, a: a, b: b));
      }

      _all = joined;
    } on Exception catch (e) {
      debugPrint('Combinations: load failed: $e');
      _all = const [];
    }

    _loading = false;
    notifyListeners();
  }

  void setSort(CombinationSort sort) {
    if (_sort == sort) return;
    _sort = sort;
    notifyListeners();
  }

  void setFilter(GarmentCategory? category) {
    if (_filter == category) return;
    _filter = category;
    notifyListeners();
  }

  /// Every cached pairing involving one garment, best first. Backs the
  /// "what does this go with" view from a closet tile.
  Future<List<Combination>> forItem(String itemId) async {
    final rows = await _scores.forItem(
      itemId,
      promptVersion: GeminiService.promptVersion,
    );

    final out = <Combination>[];
    for (final score in rows) {
      final a = _closet.byId(score.itemA);
      final b = _closet.byId(score.itemB);
      if (a == null || b == null) continue;
      out.add(Combination(score: score, a: a, b: b));
    }
    return out;
  }

  Future<void> clearCache() async {
    await _scores.clear();
    await load();
  }
}
