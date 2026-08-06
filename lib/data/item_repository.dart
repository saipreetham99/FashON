import 'dart:io';

import 'package:uuid/uuid.dart';

import '../models/clothing_item.dart';
import 'database.dart';
import 'image_store.dart';

/// Reads and writes garments.
class ItemRepository {
  final AppDatabase _database;
  final ImageStore _images;
  final Uuid _uuid = const Uuid();

  ItemRepository({required AppDatabase database, required ImageStore images})
    : _database = database,
      _images = images;

  Future<List<ClothingItem>> all() async {
    final db = await _database.db;
    final rows = await db.query('items', orderBy: 'created_at DESC');
    return rows.map(ClothingItem.fromRow).toList(growable: false);
  }

  Future<List<ClothingItem>> byCategory(GarmentCategory category) async {
    final db = await _database.db;
    final rows = await db.query(
      'items',
      where: 'category = ?',
      whereArgs: [category.name],
      orderBy: 'created_at DESC',
    );
    return rows.map(ClothingItem.fromRow).toList(growable: false);
  }

  Future<ClothingItem?> byId(String id) async {
    final db = await _database.db;
    final rows = await db.query(
      'items',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return ClothingItem.fromRow(rows.first);
  }

  /// Stores a photo and its row, returning the created garment.
  Future<ClothingItem> add({
    required File sourceImage,
    required GarmentCategory category,
    String? label,
  }) async {
    final id = _uuid.v4();
    final fileName = await _images.saveItemImage(
      source: sourceImage,
      itemId: id,
    );

    final item = ClothingItem(
      id: id,
      category: category,
      fileName: fileName,
      createdAt: DateTime.now(),
      label: label,
    );

    final db = await _database.db;
    await db.insert('items', item.toRow());
    return item;
  }

  Future<void> updateLabel(String id, String? label) async {
    final db = await _database.db;
    await db.update(
      'items',
      {'label': label},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Deletes a garment, its photo, and (by cascade) every pairing involving it.
  Future<void> delete(ClothingItem item) async {
    final db = await _database.db;
    await db.delete('items', where: 'id = ?', whereArgs: [item.id]);
    await _images.deleteItemImage(item.fileName);
  }

  Future<int> count() async {
    final db = await _database.db;
    final result = await db.rawQuery('SELECT COUNT(*) AS n FROM items');
    return (result.first['n'] as int?) ?? 0;
  }
}
