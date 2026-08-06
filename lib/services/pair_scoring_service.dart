import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/score_repository.dart';
import '../models/clothing_item.dart';
import '../models/pair_score.dart';
import 'gemini_service.dart';

/// The single door between the app and paid scoring.
///
/// Everything that wants a score comes through here, which is what lets the
/// cache actually work: one pair is fetched once, scored once, and stored once,
/// no matter how many screens ask for it.
class PairScoringService {
  /// Concurrent Gemini calls. Three keeps a free-tier key clear of per-minute
  /// limits while still feeling parallel when ranking a dozen candidates.
  static const int maxConcurrent = 3;

  final GeminiService _gemini;
  final ScoreRepository _scores;

  /// In-flight work keyed by pair, so two widgets asking at the same moment
  /// share one network call instead of racing and paying twice.
  final Map<String, Future<PairScore>> _inFlight = {};

  PairScoringService({
    required GeminiService gemini,
    required ScoreRepository scores,
  }) : _gemini = gemini,
       _scores = scores;

  /// A verdict for the pair, from cache when available.
  Future<PairScore> score(ClothingItem a, ClothingItem b) {
    final key = pairKeyFor(a.id, b.id);

    final existing = _inFlight[key];
    if (existing != null) return existing;

    final future = _scoreUncached(a, b);
    _inFlight[key] = future;
    return future.whenComplete(() => _inFlight.remove(key));
  }

  Future<PairScore> _scoreUncached(ClothingItem a, ClothingItem b) async {
    final cached = await _scores.get(
      a.id,
      b.id,
      promptVersion: GeminiService.promptVersion,
    );
    if (cached != null) return cached;

    final fresh = await _gemini.scorePair(a, b);

    // A failed cache write must not fail the score the user is waiting on.
    try {
      await _scores.put(fresh);
    } on Exception catch (e) {
      debugPrint('PairScoring: cache write failed: $e');
    }

    return fresh;
  }

  /// Cache-only read. Never calls the model, so callers can render a
  /// placeholder rather than silently spending.
  Future<PairScore?> cached(String itemIdA, String itemIdB) =>
      _scores.get(itemIdA, itemIdB, promptVersion: GeminiService.promptVersion);

  /// Scores each candidate against all of [chosen] and ranks by mean score.
  ///
  /// Averaging pairwise scores rather than sending the whole outfit in one
  /// prompt is the choice that makes the cache pay: pairs are the unit, so
  /// swapping one chosen garment only costs the pairs that changed, and every
  /// pair computed anywhere in the app is reused here for free.
  ///
  /// [onProgress] reports `(done, total)`. Supply [cancelled] returning true to
  /// abandon the run; finished pairs stay cached, so resuming is cheap.
  Future<List<ScoredCandidate>> rank({
    required List<ClothingItem> chosen,
    required List<ClothingItem> candidates,
    void Function(int done, int total)? onProgress,
    bool Function()? cancelled,
  }) async {
    if (chosen.isEmpty || candidates.isEmpty) return const [];

    final total = candidates.length;
    var done = 0;

    final results = <ScoredCandidate>[];
    final queue = List<ClothingItem>.of(candidates);
    Object? firstError;

    Future<void> worker() async {
      while (true) {
        if (cancelled?.call() ?? false) return;
        if (queue.isEmpty) return;

        final candidate = queue.removeAt(0);
        try {
          final pairs = <String, PairScore>{};
          for (final item in chosen) {
            if (cancelled?.call() ?? false) return;
            pairs[item.id] = await score(candidate, item);
          }

          final mean =
              pairs.values.map((p) => p.score).reduce((a, b) => a + b) /
              pairs.length;

          results.add(
            ScoredCandidate(
              itemId: candidate.id,
              averageScore: mean,
              pairs: pairs,
            ),
          );
        } on GeminiException catch (e) {
          // An auth failure will hit every candidate, so stop immediately
          // rather than grinding through the queue failing identically.
          if (e.isAuthFailure) throw e;
          firstError ??= e;
          debugPrint('PairScoring: ${candidate.id} failed: ${e.message}');
        } finally {
          done++;
          onProgress?.call(done, total);
        }
      }
    }

    await Future.wait(
      List.generate(
        total < maxConcurrent ? total : maxConcurrent,
        (_) => worker(),
      ),
    );

    if (results.isEmpty && firstError != null) {
      throw GeminiException('Scoring failed. $firstError');
    }

    results.sort((a, b) => b.averageScore.compareTo(a.averageScore));
    return results;
  }
}
