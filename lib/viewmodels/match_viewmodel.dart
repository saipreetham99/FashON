import 'package:flutter/foundation.dart';

import '../data/look_repository.dart';
import '../data/score_repository.dart';
import '../models/clothing_item.dart';
import '../models/outfit.dart';
import '../models/pair_score.dart';
import '../models/user_profile.dart';
import '../services/gemini_service.dart';
import '../services/pair_scoring_service.dart';
import 'closet_viewmodel.dart';

/// What the user is asking Match to do.
enum MatchMode {
  /// Score the garments they picked, as picked.
  rate,

  /// Find the best garment in a category to complete what they picked.
  complete,
}

enum MatchStatus {
  idle,
  scoring,
  done,
  rendering,
  rendered,
  saving,
  saved,
  failed,
}

/// An alternative that beats what the user currently has selected.
class Upgrade {
  /// The garment already in the selection that could be replaced.
  final ClothingItem replace;

  /// The garment that would score better in its place.
  final ClothingItem with_;

  /// Score of the current pairing.
  final double currentScore;

  /// Score the swap would achieve.
  final double betterScore;

  const Upgrade({
    required this.replace,
    required this.with_,
    required this.currentScore,
    required this.betterScore,
  });

  double get gain => betterScore - currentScore;
}

/// Drives the Match tab.
///
/// Two jobs behind one selection: rate what you picked, or fill a gap in it.
/// Both reduce to the same pairwise scoring, which is why they share a
/// viewmodel rather than duplicating selection logic.
class MatchViewModel extends ChangeNotifier {
  final ClosetViewModel _closet;
  final PairScoringService _scoring;
  final ScoreRepository _scores;
  final LookRepository _looks;
  final GeminiService _gemini;
  final UserProfile Function() _currentProfile;

  MatchViewModel({
    required ClosetViewModel closet,
    required PairScoringService scoring,
    required ScoreRepository scores,
    required LookRepository looks,
    required GeminiService gemini,
    required UserProfile Function() currentProfile,
  }) : _closet = closet,
       _scoring = scoring,
       _scores = scores,
       _looks = looks,
       _gemini = gemini,
       _currentProfile = currentProfile;

  // --- Selection ------------------------------------------------------------

  /// At most one garment per category: an outfit does not have two pairs of
  /// trousers, and allowing it would make the averaged score meaningless.
  final Map<GarmentCategory, ClothingItem> _selected = {};
  Map<GarmentCategory, ClothingItem> get selected =>
      Map.unmodifiable(_selected);

  List<ClothingItem> get selectedItems =>
      _selected.values.toList(growable: false);

  MatchMode _mode = MatchMode.rate;
  MatchMode get mode => _mode;

  GarmentCategory? _gap;

  /// The category being searched, in [MatchMode.complete].
  GarmentCategory? get gap => _gap;

  // --- Results --------------------------------------------------------------

  MatchStatus _status = MatchStatus.idle;
  MatchStatus get status => _status;

  String? _error;
  String? get error => _error;

  bool _errorIsAuth = false;
  bool get errorIsAuth => _errorIsAuth;

  int _done = 0;
  int _total = 0;
  int get done => _done;
  int get total => _total;
  double get progress => _total == 0 ? 0 : _done / _total;

  /// Pairwise verdicts between the selected garments, in [MatchMode.rate].
  List<PairScore> _ownPairs = const [];
  List<PairScore> get ownPairs => _ownPairs;

  /// Mean of [_ownPairs]. Null until scored.
  double? get selectionScore {
    if (_ownPairs.isEmpty) return null;
    return _ownPairs.map((p) => p.score).reduce((a, b) => a + b) /
        _ownPairs.length;
  }

  /// Ranked candidates for [gap], best first, in [MatchMode.complete].
  List<ScoredCandidate> _ranked = const [];
  List<ScoredCandidate> get ranked => _ranked;

  /// Swaps that would score better than the current selection.
  List<Upgrade> _upgrades = const [];
  List<Upgrade> get upgrades => _upgrades;

  Uint8List? _preview;
  Uint8List? get preview => _preview;

  /// Bumped on every run and every selection change. A run whose token is
  /// stale has been superseded, so it discards its results instead of
  /// overwriting a selection the user has since changed.
  int _run = 0;
  bool _disposed = false;

  // --- Guards ---------------------------------------------------------------

  bool get canRate => _selected.length >= 2 && _status != MatchStatus.scoring;

  bool get canComplete =>
      _selected.isNotEmpty && _gap != null && _status != MatchStatus.scoring;

  bool get canRender =>
      _selected.isNotEmpty &&
      _status != MatchStatus.rendering &&
      _status != MatchStatus.scoring;

  bool get canSave => _selected.isNotEmpty && _status != MatchStatus.saving;

  // --- Mutation -------------------------------------------------------------

  void setMode(MatchMode mode) {
    if (_mode == mode) return;
    _mode = mode;
    _invalidate();
    notifyListeners();
  }

  void toggle(ClothingItem item) {
    final current = _selected[item.category];

    if (current?.id == item.id) {
      _selected.remove(item.category);
    } else {
      _selected[item.category] = item;
      // The gap cannot be a category you have now filled.
      if (_gap == item.category) _gap = null;
    }

    _invalidate();
    notifyListeners();
  }

  bool isSelected(ClothingItem item) => _selected[item.category]?.id == item.id;

  void setGap(GarmentCategory? category) {
    if (category != null && _selected.containsKey(category)) {
      _error =
          'You already picked ${category.singular}. '
          'Deselect it to search for a different one.';
      notifyListeners();
      return;
    }
    _gap = category;
    _invalidate();
    notifyListeners();
  }

  void clearSelection() {
    _selected.clear();
    _gap = null;
    _invalidate();
    notifyListeners();
  }

  /// Drops every derived result. Called whenever the inputs change, so stale
  /// scores are never shown beside a selection they were not computed for.
  void _invalidate() {
    _run++;
    _ownPairs = const [];
    _ranked = const [];
    _upgrades = const [];
    _preview = null;
    _done = 0;
    _total = 0;
    _error = null;
    _errorIsAuth = false;
    if (_status != MatchStatus.idle) _status = MatchStatus.idle;
  }

  // --- Rate the selection ---------------------------------------------------

  /// Scores every pair inside the current selection.
  ///
  /// Three garments is three pairs, four is six. Each is cached independently,
  /// so adding a fourth garment to a scored trio only costs the three new
  /// pairs.
  Future<void> rateSelection() async {
    if (!canRate) return;

    final items = selectedItems;
    final combos = <List<ClothingItem>>[];
    for (var i = 0; i < items.length; i++) {
      for (var j = i + 1; j < items.length; j++) {
        combos.add([items[i], items[j]]);
      }
    }

    final run = ++_run;
    _status = MatchStatus.scoring;
    _done = 0;
    _total = combos.length;
    _error = null;
    notifyListeners();

    final results = <PairScore>[];
    try {
      for (final combo in combos) {
        if (_disposed || run != _run) return;
        results.add(await _scoring.score(combo[0], combo[1]));
        _done++;
        if (run == _run) notifyListeners();
      }

      if (run != _run) return;

      _ownPairs = results;
      _status = MatchStatus.done;
      notifyListeners();

      // Findable improvements come from the cache only — never new spend.
      await _findUpgrades(run);
    } on GeminiException catch (e) {
      if (run != _run) return;
      _fail(e);
    } on Exception catch (e) {
      if (run != _run) return;
      debugPrint('Match: rate failed: $e');
      _fail(
        const GeminiException(
          'Scoring failed. Check your connection and try again.',
        ),
      );
    }
  }

  /// Looks for a garment already scored higher than one in the selection.
  ///
  /// Cache-only, deliberately: this runs unprompted after every rating, so it
  /// has to be free. It gets better the more the user uses the app, which is
  /// the right shape for a suggestion — it never costs anything and it grows
  /// more useful over time.
  Future<void> _findUpgrades(int run) async {
    if (_selected.length < 2) return;

    final found = <Upgrade>[];

    for (final anchor in selectedItems) {
      for (final target in selectedItems) {
        if (anchor.id == target.id) continue;

        final current = _pairBetween(anchor.id, target.id);
        if (current == null) continue;

        // Alternatives in the same category as target, excluding target itself
        // and anything already selected.
        final alternatives = _closet
            .ofCategory(target.category)
            .where((i) => i.id != target.id)
            .where((i) => !_selected.values.any((s) => s.id == i.id))
            .map((i) => i.id)
            .toList(growable: false);

        if (alternatives.isEmpty) continue;

        final cached = await _scores.between(
          anchor.id,
          alternatives,
          promptVersion: GeminiService.promptVersion,
          profileFingerprint: _currentProfile().fingerprint,
        );
        if (_disposed || run != _run) return;

        for (final candidate in cached) {
          if (candidate.score <= current.score) continue;
          final betterId = candidate.otherThan(anchor.id);
          final better = _closet.byId(betterId);
          if (better == null) continue;

          found.add(
            Upgrade(
              replace: target,
              with_: better,
              currentScore: current.score,
              betterScore: candidate.score,
            ),
          );
        }
      }
    }

    if (run != _run) return;

    // Best gain first, and only the strongest suggestion per replaced garment:
    // five ways to swap the same trousers is noise, not advice.
    found.sort((a, b) => b.gain.compareTo(a.gain));
    final seen = <String>{};
    _upgrades = found
        .where((u) => seen.add(u.replace.id))
        .take(3)
        .toList(growable: false);

    notifyListeners();
  }

  /// The already-scored pair joining two selected garments, if present.
  PairScore? _pairBetween(String idA, String idB) {
    for (final pair in _ownPairs) {
      if (pair.involves(idA) && pair.involves(idB)) return pair;
    }
    return null;
  }

  /// Applies an upgrade to the selection and rescores.
  Future<void> applyUpgrade(Upgrade upgrade) async {
    _selected[upgrade.with_.category] = upgrade.with_;
    _invalidate();
    notifyListeners();
    await rateSelection();
  }

  // --- Complete the selection ----------------------------------------------

  /// Ranks every garment in [gap] against the current selection.
  Future<void> findBest() async {
    if (!canComplete) return;

    final gapCategory = _gap!;
    final chosen = selectedItems;
    final chosenIds = chosen.map((i) => i.id).toSet();

    final candidates = _closet
        .ofCategory(gapCategory)
        .where((i) => !chosenIds.contains(i.id))
        .toList(growable: false);

    if (candidates.isEmpty) {
      _error =
          'Your closet has no ${gapCategory.singular} to choose from. '
          'Add one from the Closet tab.';
      _status = MatchStatus.failed;
      notifyListeners();
      return;
    }

    final run = ++_run;
    _status = MatchStatus.scoring;
    _done = 0;
    _total = candidates.length;
    _error = null;
    notifyListeners();

    try {
      final ranked = await _scoring.rank(
        chosen: chosen,
        candidates: candidates,
        cancelled: () => _disposed || run != _run,
        onProgress: (done, total) {
          if (run != _run) return;
          _done = done;
          _total = total;
          notifyListeners();
        },
      );

      if (run != _run) return;

      if (ranked.isEmpty) {
        _error = 'Could not score any ${gapCategory.label.toLowerCase()}.';
        _status = MatchStatus.failed;
      } else {
        _ranked = ranked;
        _status = MatchStatus.done;
      }
      notifyListeners();
    } on GeminiException catch (e) {
      if (run != _run) return;
      _fail(e);
    } on Exception catch (e) {
      if (run != _run) return;
      debugPrint('Match: findBest failed: $e');
      _fail(
        const GeminiException(
          'Scoring failed. Check your connection and try again.',
        ),
      );
    }
  }

  /// Adds a ranked candidate into the selection, so it can be rendered or saved.
  void acceptCandidate(String itemId) {
    final item = _closet.byId(itemId);
    if (item == null) return;
    _selected[item.category] = item;
    if (_gap == item.category) _gap = null;
    _ranked = const [];
    _preview = null;
    _status = MatchStatus.idle;
    notifyListeners();
  }

  /// Stops an in-flight run. Finished pairs stay cached.
  void cancel() {
    if (_status != MatchStatus.scoring) return;
    _run++;
    _status = MatchStatus.idle;
    _done = 0;
    _total = 0;
    notifyListeners();
  }

  // --- Preview and save ----------------------------------------------------

  Future<void> renderPreview() async {
    if (!canRender) return;

    final run = ++_run;
    _status = MatchStatus.rendering;
    _error = null;
    notifyListeners();

    try {
      final bytes = await _gemini.generateOutfitPreview(
        items: selectedItems,
        profile: _currentProfile(),
      );
      if (_disposed || run != _run) return;
      _preview = bytes;
      _status = MatchStatus.rendered;
      notifyListeners();
    } on GeminiException catch (e) {
      if (run != _run) return;
      _fail(e);
    } on Exception catch (e) {
      if (run != _run) return;
      debugPrint('Match: render failed: $e');
      _fail(const GeminiException('Could not render a preview. Try again.'));
    }
  }

  Future<bool> saveLook(LookTag tag) async {
    if (!canSave) return false;

    _status = MatchStatus.saving;
    notifyListeners();

    try {
      await _looks.save(
        itemIds: selectedItems.map((i) => i.id).toList(growable: false),
        tag: tag,
        score: selectionScore,
        previewBytes: _preview,
      );
      _status = MatchStatus.saved;
      notifyListeners();
      return true;
    } on Exception catch (e) {
      debugPrint('Match: save failed: $e');
      _fail(const GeminiException('Could not save this look.'));
      return false;
    }
  }

  void _fail(GeminiException e) {
    _error = e.message;
    _errorIsAuth = e.isAuthFailure;
    _status = MatchStatus.failed;
    notifyListeners();
  }

  void clearError() {
    if (_error == null) return;
    _error = null;
    _errorIsAuth = false;
    if (_status == MatchStatus.failed) _status = MatchStatus.idle;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _run++;
    super.dispose();
  }
}
