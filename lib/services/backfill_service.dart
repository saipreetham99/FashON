import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/app_settings.dart';
import '../data/score_repository.dart';
import '../models/clothing_item.dart';
import '../models/pair_score.dart';
import 'api_key_service.dart';
import 'gemini_service.dart';
import 'pair_scoring_service.dart';

enum BackfillStatus {
  /// Nothing to do, or nothing running.
  idle,

  running,

  /// Stopped by the user.
  paused,

  /// Stopped by a rate limit. Resumable.
  throttled,

  /// Stopped by something the user has to fix, usually the API key.
  blocked,
}

/// Scores pairings in the background so the app knows things before it is asked.
///
/// This exists because the upgrade suggestions are cache-only. They cost nothing
/// to compute, but they can only spot "these trousers score higher than the ones
/// you picked" if that pairing has already been judged. Without a backfill the
/// cache only fills where the user has explicitly looked, so the feature stays
/// dormant on a fresh closet — which is exactly when advice is most useful.
///
/// Two decisions worth knowing about:
///
/// **Cross-category only.** A pairing of two tops is never worn, so scoring it
/// is money spent on an answer nobody needs. Restricting to pairs from different
/// categories cuts the work substantially — ten tops alone would otherwise
/// contribute forty-five useless pairings — and it happens to be exactly the set
/// the upgrade search reads.
///
/// **The queue is derived, not stored.** Pending work is the difference between
/// every useful pair and the keys already cached. Nothing to persist, nothing to
/// keep in sync, and it is correct after a crash, a reinstall, or a rubric
/// version bump without any bookkeeping.
class BackfillService extends ChangeNotifier {
  /// One at a time. The user's own foreground scoring should always feel
  /// faster than the background work happening behind it.
  static const int _concurrency = 1;

  /// Pause between pairings, to stay clear of per-minute quotas on a free key
  /// and to keep the device from heating up while idle.
  static const Duration _breather = Duration(milliseconds: 750);

  final PairScoringService _scoring;
  final ScoreRepository _scores;
  final ApiKeyService _apiKeys;
  final AppSettings _settings;

  BackfillService({
    required PairScoringService scoring,
    required ScoreRepository scores,
    required ApiKeyService apiKeys,
    required AppSettings settings,
  }) : _scoring = scoring,
       _scores = scores,
       _apiKeys = apiKeys,
       _settings = settings;

  BackfillStatus _status = BackfillStatus.idle;
  BackfillStatus get status => _status;

  int _done = 0;
  int _total = 0;

  /// Pairings completed in the current run.
  int get done => _done;

  /// Pairings the current run intends to score.
  int get total => _total;

  double get progress => _total == 0 ? 0 : _done / _total;

  int _pending = 0;

  /// Useful pairings not yet scored, regardless of the per-run cap.
  int get pending => _pending;

  String? _message;
  String? get message => _message;

  bool get isRunning => _status == BackfillStatus.running;

  /// True when there is work and a reason to show controls for it.
  bool get hasWork => _pending > 0;

  int _run = 0;
  bool _disposed = false;

  // ---------------------------------------------------------------------------
  // Work discovery
  // ---------------------------------------------------------------------------

  /// Every pairing worth scoring, given the closet.
  ///
  /// Cross-category only, and ordered so that recently added garments are
  /// scored first — the reason someone is watching this run is usually the thing
  /// they just photographed.
  List<(ClothingItem, ClothingItem)> _usefulPairs(List<ClothingItem> closet) {
    final sorted = List<ClothingItem>.of(closet)
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

    final pairs = <(ClothingItem, ClothingItem)>[];
    for (var i = 0; i < sorted.length; i++) {
      for (var j = i + 1; j < sorted.length; j++) {
        if (sorted[i].category == sorted[j].category) continue;
        pairs.add((sorted[i], sorted[j]));
      }
    }
    return pairs;
  }

  /// Recomputes [pending] against the current closet.
  Future<void> refresh(List<ClothingItem> closet) async {
    if (_disposed) return;

    try {
      final cached = await _scores.cachedPairKeys(
        promptVersion: GeminiService.promptVersion,
      );
      final missing =
          _usefulPairs(closet)
              .where(
                (pair) => !cached.contains(pairKeyFor(pair.$1.id, pair.$2.id)),
              )
              .length;

      if (_disposed) return;
      if (_pending != missing) {
        _pending = missing;
        notifyListeners();
      }
    } on Exception catch (e) {
      debugPrint('Backfill: refresh failed: $e');
    }
  }

  // ---------------------------------------------------------------------------
  // Running
  // ---------------------------------------------------------------------------

  /// Called after a garment is added.
  ///
  /// Only starts on its own when the user has turned automatic scoring on;
  /// otherwise it just updates the pending count so the UI can offer the work.
  Future<void> onClosetChanged(List<ClothingItem> closet) async {
    await refresh(closet);
    if (!_settings.backfillEnabled) return;
    if (_pending == 0) return;
    await start(closet);
  }

  /// Scores up to the configured cap, then stops.
  Future<void> start(List<ClothingItem> closet, {bool force = false}) async {
    if (isRunning) return;

    if (!_apiKeys.hasKey) {
      _fail(BackfillStatus.blocked, 'Add a Gemini API key to score pairings.');
      return;
    }

    final cached = await _scores.cachedPairKeys(
      promptVersion: GeminiService.promptVersion,
    );
    final queue =
        _usefulPairs(closet)
            .where(
              (pair) => !cached.contains(pairKeyFor(pair.$1.id, pair.$2.id)),
            )
            .toList();

    _pending = queue.length;
    if (queue.isEmpty) {
      _status = BackfillStatus.idle;
      _message = null;
      notifyListeners();
      return;
    }

    // The cap bounds a single run, not the total work. Whatever is left is
    // picked up next time, so an unattended app cannot quietly drain a quota.
    final cap = force ? queue.length : _settings.backfillCap;
    final batch = queue.take(cap).toList();

    final run = ++_run;
    _status = BackfillStatus.running;
    _done = 0;
    _total = batch.length;
    _message = null;
    notifyListeners();

    await _drain(batch, run);
  }

  Future<void> _drain(List<(ClothingItem, ClothingItem)> batch, int run) async {
    for (final pair in batch) {
      if (_disposed || run != _run) return;

      try {
        await _scoring.score(pair.$1, pair.$2);
        _done++;
        _pending = _pending > 0 ? _pending - 1 : 0;
        if (run == _run) notifyListeners();
      } on GeminiException catch (e) {
        if (run != _run) return;

        // A rate limit is temporary and a key problem is not, so they get
        // different states: one invites a retry, the other sends the user to
        // Settings.
        if (e.statusCode == 429) {
          _fail(
            BackfillStatus.throttled,
            'Paused at $_done of $_total — your key hit its rate limit.',
          );
          return;
        }
        if (e.isAuthFailure) {
          _fail(BackfillStatus.blocked, e.message);
          return;
        }

        // Anything else is probably this one pairing's fault, so skip it and
        // keep going rather than abandoning the batch.
        debugPrint('Backfill: skipped a pairing: ${e.message}');
        _done++;
        if (run == _run) notifyListeners();
      } on Exception catch (e) {
        if (run != _run) return;
        _fail(BackfillStatus.paused, 'Stopped: $e');
        return;
      }

      // Yield between pairings so foreground scoring and scrolling stay smooth.
      await Future<void>.delayed(_breather);
    }

    if (_disposed || run != _run) return;

    _status = BackfillStatus.idle;
    _message =
        _pending > 0
            ? '$_pending left. Continues next time you add something.'
            : null;
    notifyListeners();
  }

  void pause() {
    if (!isRunning) return;
    _run++;
    _status = BackfillStatus.paused;
    _message = 'Paused at $_done of $_total.';
    notifyListeners();
  }

  void _fail(BackfillStatus status, String message) {
    _run++;
    _status = status;
    _message = message;
    notifyListeners();
  }

  void clearMessage() {
    if (_message == null) return;
    _message = null;
    if (_status != BackfillStatus.running) _status = BackfillStatus.idle;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _run++;
    super.dispose();
  }
}
