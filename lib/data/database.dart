import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

/// Owns the SQLite connection and schema.
///
/// One database, three tables. The interesting part is the indexing on
/// `pair_scores`: because a pair key is sorted, `item_a` is always the lower
/// id, so finding every pairing for one garment means
/// `WHERE item_a = ? OR item_b = ?` and both sides are indexed. That keeps the
/// combinations grid a single indexed scan rather than a table walk.
class AppDatabase {
  static const _fileName = 'fashon.db';

  /// v1 → v2 added the `settings` table for the background-scoring preference.
  static const _version = 2;

  Database? _db;

  Future<Database> get db async => _db ??= await _open();

  Future<Database> _open() async {
    final dir = await getDatabasesPath();
    return openDatabase(
      p.join(dir, _fileName),
      version: _version,
      onConfigure: (db) async {
        // Cascade deletes: removing a garment should take its pairings with
        // it, rather than leaving rows keyed on an id that can never appear.
        await db.execute('PRAGMA foreign_keys = ON');
      },
      onUpgrade: (db, from, to) async {
        // Migrations run in order and each one must be safe on a populated
        // database. Never drop and recreate: the score cache is expensive to
        // rebuild, so losing it would cost the user real money.
        if (from < 2) await _createSettings(db);
      },
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE items (
            id          TEXT    PRIMARY KEY,
            category    TEXT    NOT NULL,
            file_name   TEXT    NOT NULL,
            created_at  INTEGER NOT NULL,
            label       TEXT
          )
        ''');
        await db.execute('CREATE INDEX idx_items_category ON items(category)');

        await db.execute('''
          CREATE TABLE pair_scores (
            pair_key       TEXT    PRIMARY KEY,
            item_a         TEXT    NOT NULL,
            item_b         TEXT    NOT NULL,
            score          REAL    NOT NULL,
            boosting       TEXT    NOT NULL,
            costing        TEXT    NOT NULL,
            improve        TEXT    NOT NULL,
            shoes          TEXT    NOT NULL,
            accessories    TEXT    NOT NULL,
            valid          INTEGER NOT NULL,
            model          TEXT    NOT NULL,
            prompt_version INTEGER NOT NULL,
            scored_at      INTEGER NOT NULL,
            FOREIGN KEY (item_a) REFERENCES items(id) ON DELETE CASCADE,
            FOREIGN KEY (item_b) REFERENCES items(id) ON DELETE CASCADE
          )
        ''');
        await db.execute('CREATE INDEX idx_pair_a ON pair_scores(item_a)');
        await db.execute('CREATE INDEX idx_pair_b ON pair_scores(item_b)');
        await db.execute(
          'CREATE INDEX idx_pair_score ON pair_scores(score DESC)',
        );

        await db.execute('''
          CREATE TABLE looks (
            id           TEXT    PRIMARY KEY,
            item_ids     TEXT    NOT NULL,
            preview_file TEXT,
            tag          TEXT    NOT NULL,
            score        REAL,
            created_at   INTEGER NOT NULL
          )
        ''');
        await db.execute('CREATE INDEX idx_looks_tag ON looks(tag)');

        await _createSettings(db);
      },
    );
  }

  /// Small key-value store for user preferences.
  ///
  /// A table rather than shared_preferences: the app already owns a database,
  /// and one dependency fewer is worth more than the convenience.
  static Future<void> _createSettings(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS settings (
        key   TEXT PRIMARY KEY,
        value TEXT NOT NULL
      )
    ''');
  }

  Future<void> close() async {
    await _db?.close();
    _db = null;
  }
}
