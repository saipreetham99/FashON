import 'package:sqflite/sqflite.dart';

import '../models/pair_score.dart';
import 'database.dart';

/// The pairing score cache.
///
/// Every verdict the model ever produces lands here, keyed on the sorted pair.
/// Two consequences worth naming:
///
/// * The combinations grid is a single indexed query, not n-squared API calls.
///   Displaying scores costs nothing once they exist.
/// * Swapping one garment in a selection only requires scoring the pairs that
///   actually changed. Everything else is a hit, including pairs scored in a
///   completely different part of the app weeks earlier.
class ScoreRepository {
  final AppDatabase _database;

  ScoreRepository({required AppDatabase database}) : _database = database;

  /// A cached verdict, or null on a miss or a stale prompt version.
  ///
  /// Staleness is not a soft signal: a verdict written under a different rubric
  /// is not comparable to a fresh one, so it is treated as absent.
  Future<PairScore?> get(
    String itemA,
    String itemB, {
    required int promptVersion,
  }) async {
    final db = await _database.db;
    final rows = await db.query(
      'pair_scores',
      where: 'pair_key = ? AND prompt_version = ?',
      whereArgs: [pairKeyFor(itemA, itemB), promptVersion],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return PairScore.fromRow(rows.first);
  }

  Future<void> put(PairScore score) async {
    final db = await _database.db;
    await db.insert(
      'pair_scores',
      score.toRow(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Every cached pairing, best first. Backs the combinations grid.
  Future<List<PairScore>> allRanked({required int promptVersion}) async {
    final db = await _database.db;
    final rows = await db.query(
      'pair_scores',
      where: 'prompt_version = ? AND valid = 1',
      whereArgs: [promptVersion],
      orderBy: 'score DESC',
    );
    return rows.map(PairScore.fromRow).toList(growable: false);
  }

  /// Every cached pairing involving [itemId], best first.
  ///
  /// Both sides are indexed, so this stays cheap as the closet grows.
  Future<List<PairScore>> forItem(
    String itemId, {
    required int promptVersion,
  }) async {
    final db = await _database.db;
    final rows = await db.query(
      'pair_scores',
      where: '(item_a = ? OR item_b = ?) AND prompt_version = ? AND valid = 1',
      whereArgs: [itemId, itemId, promptVersion],
      orderBy: 'score DESC',
    );
    return rows.map(PairScore.fromRow).toList(growable: false);
  }

  /// Cached pairings between [itemId] and any of [candidateIds].
  ///
  /// Used to answer "is there something in the closet that beats what you have
  /// picked" without a single network call.
  Future<List<PairScore>> between(
    String itemId,
    List<String> candidateIds, {
    required int promptVersion,
  }) async {
    if (candidateIds.isEmpty) return const [];

    final db = await _database.db;
    final placeholders = List.filled(candidateIds.length, '?').join(',');

    final rows = await db.rawQuery(
      '''
      SELECT * FROM pair_scores
      WHERE prompt_version = ?
        AND valid = 1
        AND (
          (item_a = ? AND item_b IN ($placeholders))
          OR
          (item_b = ? AND item_a IN ($placeholders))
        )
      ORDER BY score DESC
      ''',
      [promptVersion, itemId, ...candidateIds, itemId, ...candidateIds],
    );

    return rows.map(PairScore.fromRow).toList(growable: false);
  }

  /// Just the pair keys already scored under [promptVersion].
  ///
  /// Keys only, deliberately: the backfill needs to know what is *missing*, and
  /// loading full verdicts with their advice text to answer a set-membership
  /// question would read megabytes to compute a difference.
  Future<Set<String>> cachedPairKeys({required int promptVersion}) async {
    final db = await _database.db;
    final rows = await db.query(
      'pair_scores',
      columns: ['pair_key'],
      where: 'prompt_version = ?',
      whereArgs: [promptVersion],
    );
    return rows.map((row) => row['pair_key'] as String).toSet();
  }

  /// How many pairings are cached, for the settings readout.
  Future<int> count() async {
    final db = await _database.db;
    final result = await db.rawQuery('SELECT COUNT(*) AS n FROM pair_scores');
    return (result.first['n'] as int?) ?? 0;
  }

  /// Drops every cached verdict. Offered in Settings for when the user wants
  /// to rescore from scratch after editing the rubric.
  Future<void> clear() async {
    final db = await _database.db;
    await db.delete('pair_scores');
  }
}
