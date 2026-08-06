import 'dart:typed_data';

import 'package:uuid/uuid.dart';

import '../models/outfit.dart';
import 'database.dart';
import 'image_store.dart';

/// Reads and writes saved looks.
class LookRepository {
  final AppDatabase _database;
  final ImageStore _images;
  final Uuid _uuid = const Uuid();

  LookRepository({required AppDatabase database, required ImageStore images})
    : _database = database,
      _images = images;

  Future<List<Look>> all() async {
    final db = await _database.db;
    final rows = await db.query('looks', orderBy: 'created_at DESC');
    return rows.map(Look.fromRow).toList(growable: false);
  }

  Future<List<Look>> byTag(LookTag tag) async {
    final db = await _database.db;
    final rows = await db.query(
      'looks',
      where: 'tag = ?',
      whereArgs: [tag.name],
      orderBy: 'created_at DESC',
    );
    return rows.map(Look.fromRow).toList(growable: false);
  }

  /// Saves a look, writing preview bytes to disk when present.
  Future<Look> save({
    required List<String> itemIds,
    required LookTag tag,
    double? score,
    Uint8List? previewBytes,
  }) async {
    final id = _uuid.v4();

    String? previewFileName;
    if (previewBytes != null) {
      previewFileName = await _images.savePreview(
        bytes: previewBytes,
        lookId: id,
      );
    }

    final look = Look(
      id: id,
      itemIds: itemIds,
      previewFileName: previewFileName,
      tag: tag,
      score: score,
      createdAt: DateTime.now(),
    );

    final db = await _database.db;
    await db.insert('looks', look.toRow());
    return look;
  }

  Future<void> delete(Look look) async {
    final db = await _database.db;
    await db.delete('looks', where: 'id = ?', whereArgs: [look.id]);
    final preview = look.previewFileName;
    if (preview != null) await _images.deletePreview(preview);
  }

  Future<int> count() async {
    final db = await _database.db;
    final result = await db.rawQuery('SELECT COUNT(*) AS n FROM looks');
    return (result.first['n'] as int?) ?? 0;
  }
}
