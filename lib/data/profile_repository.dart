import 'dart:io';

import 'package:sqflite/sqflite.dart';

import '../models/user_profile.dart';
import 'database.dart';
import 'image_store.dart';

/// Reads and writes the single profile row.
class ProfileRepository {
  static const _rowId = 'me';

  final AppDatabase _database;
  final ImageStore _images;

  ProfileRepository({required AppDatabase database, required ImageStore images})
    : _database = database,
      _images = images;

  Future<UserProfile> load() async {
    final db = await _database.db;
    final rows = await db.query(
      'profile',
      where: 'id = ?',
      whereArgs: [_rowId],
      limit: 1,
    );
    if (rows.isEmpty) return UserProfile.empty;
    return UserProfile.fromRow(rows.first);
  }

  Future<void> save(UserProfile profile) async {
    final db = await _database.db;
    await db.insert(
      'profile',
      profile.toRow(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Stores a new profile photo and returns the file name to persist.
  ///
  /// Reuses the garment downscaling path: the same 1024px ceiling applies, and
  /// there is no reason a portrait needs more than a garment does.
  Future<String> savePhoto(File source) async {
    return _images.saveProfilePhoto(source);
  }

  Future<void> deletePhoto(String fileName) =>
      _images.deleteProfilePhoto(fileName);
}
