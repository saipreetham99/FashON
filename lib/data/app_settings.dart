import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';

import 'database.dart';

/// User preferences that are not secrets.
///
/// Backed by the `settings` table. Values are read once into memory at startup,
/// so the UI can branch on them synchronously without every widget awaiting a
/// query.
class AppSettings extends ChangeNotifier {
  static const _keyBackfillEnabled = 'backfill_enabled';
  static const _keyBackfillConsented = 'backfill_consented';
  static const _keyBackfillCap = 'backfill_cap';

  /// Default ceiling on pairings scored per automatic run.
  ///
  /// Deliberately modest. The queue picks up again next launch, so a low cap
  /// costs only time, while a high one can spend a lot of someone's quota while
  /// they are not looking.
  static const int defaultCap = 40;

  final AppDatabase _database;

  AppSettings({required AppDatabase database}) : _database = database;

  final Map<String, String> _cache = {};
  bool _loaded = false;
  bool get isLoaded => _loaded;

  /// Whether newly added garments get scored against the closet automatically.
  bool get backfillEnabled => _cache[_keyBackfillEnabled] == 'true';

  /// Whether the user has been shown what automatic scoring will cost them.
  ///
  /// Separate from [backfillEnabled] so the explainer appears exactly once,
  /// and turning the feature off and on again does not re-prompt.
  bool get backfillConsented => _cache[_keyBackfillConsented] == 'true';

  int get backfillCap =>
      int.tryParse(_cache[_keyBackfillCap] ?? '') ?? defaultCap;

  Future<void> load() async {
    try {
      final db = await _database.db;
      final rows = await db.query('settings');
      _cache
        ..clear()
        ..addEntries(
          rows.map(
            (row) => MapEntry(row['key'] as String, row['value'] as String),
          ),
        );
    } on Exception catch (e) {
      // Missing preferences are not worth failing startup over; defaults apply.
      debugPrint('AppSettings: load failed, using defaults: $e');
    }
    _loaded = true;
    notifyListeners();
  }

  Future<void> setBackfillEnabled(bool value) =>
      _write(_keyBackfillEnabled, value.toString());

  Future<void> setBackfillConsented(bool value) =>
      _write(_keyBackfillConsented, value.toString());

  Future<void> setBackfillCap(int value) =>
      _write(_keyBackfillCap, value.toString());

  Future<void> _write(String key, String value) async {
    _cache[key] = value;
    notifyListeners();
    try {
      final db = await _database.db;
      await db.insert('settings', {
        'key': key,
        'value': value,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    } on Exception catch (e) {
      debugPrint('AppSettings: write failed for $key: $e');
    }
  }
}
