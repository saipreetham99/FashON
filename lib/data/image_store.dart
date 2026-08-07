import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Where garment photos and generated previews live on disk.
///
/// Photos are downscaled once, on the way in. A phone camera file is commonly
/// 3-5 MB, and nothing in this app benefits from that: the model judges colour,
/// texture and silhouette perfectly well at 1024px, the grid shows 200px
/// thumbnails, and every saved byte is a byte not re-encoded on every scoring
/// call. Storing them already-shrunk means the expensive decode happens once
/// per garment rather than once per request.
class ImageStore {
  /// Longest edge kept for garment photos.
  static const int itemMaxEdge = 1024;

  static const int _jpegQuality = 88;

  Directory? _items;
  Directory? _previews;
  Directory? _profile;

  Future<Directory> get itemsDir async => _items ??= await _ensure('garments');

  Future<Directory> get previewsDir async =>
      _previews ??= await _ensure('previews');

  Future<Directory> get profileDir async =>
      _profile ??= await _ensure('profile');

  /// Resolves both directories up front, at startup.
  ///
  /// Grid tiles need a path synchronously — going through a FutureBuilder per
  /// tile makes a scrolling closet flicker as each thumbnail resolves its own
  /// directory. One await here buys [itemPathSync] for the whole session.
  Future<void> warmUp() async {
    await itemsDir;
    await previewsDir;
    await profileDir;
  }

  /// Path for a garment photo, valid only after [warmUp].
  ///
  /// Throws if called too early, which is a programming error rather than a
  /// runtime condition worth handling in the UI.
  String itemPathSync(String fileName) {
    final dir = _items;
    if (dir == null) {
      throw StateError('ImageStore.warmUp() must run before itemPathSync.');
    }
    return p.join(dir.path, fileName);
  }

  /// Path for a generated preview, valid only after [warmUp].
  String previewPathSync(String fileName) {
    final dir = _previews;
    if (dir == null) {
      throw StateError('ImageStore.warmUp() must run before previewPathSync.');
    }
    return p.join(dir.path, fileName);
  }

  /// Path for the profile photo, valid only after [warmUp].
  String profilePathSync(String fileName) {
    final dir = _profile;
    if (dir == null) {
      throw StateError('ImageStore.warmUp() must run before profilePathSync.');
    }
    return p.join(dir.path, fileName);
  }

  Future<Directory> _ensure(String name) async {
    final root = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(root.path, name));
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  /// Absolute path for a stored garment photo.
  ///
  /// Resolved on demand rather than stored, because the documents directory
  /// path changes across OS updates and restores; a persisted absolute path
  /// silently rots.
  Future<String> itemPath(String fileName) async =>
      p.join((await itemsDir).path, fileName);

  Future<String> previewPath(String fileName) async =>
      p.join((await previewsDir).path, fileName);

  Future<File> itemFile(String fileName) async =>
      File(await itemPath(fileName));

  Future<File> previewFile(String fileName) async =>
      File(await previewPath(fileName));

  /// Downscales [source] and writes it into the garments directory.
  ///
  /// Returns the file name to persist in the database.
  Future<String> saveItemImage({
    required File source,
    required String itemId,
  }) async {
    final raw = await source.readAsBytes();
    final shrunk = await compute(_downscaleJpeg, raw);

    final fileName = '$itemId.jpg';
    final target = await itemFile(fileName);
    await target.writeAsBytes(shrunk, flush: true);
    return fileName;
  }

  /// Writes generated preview bytes and returns the file name.
  Future<String> savePreview({
    required Uint8List bytes,
    required String lookId,
  }) async {
    final fileName = '$lookId.png';
    final target = await previewFile(fileName);
    await target.writeAsBytes(bytes, flush: true);
    return fileName;
  }

  /// Downscales and stores the profile photo.
  ///
  /// The file name carries a timestamp so replacing a photo never collides with
  /// a cached decode of the previous one — reusing a fixed name leaves Flutter's
  /// image cache serving the old portrait until the app restarts.
  Future<String> saveProfilePhoto(File source) async {
    final raw = await source.readAsBytes();
    final shrunk = await compute(_downscaleJpeg, raw);

    final fileName = 'me_${DateTime.now().millisecondsSinceEpoch}.jpg';
    final target = File(p.join((await profileDir).path, fileName));
    await target.writeAsBytes(shrunk, flush: true);

    // Only one portrait is ever current, so clear the rest rather than
    // accumulating every photo the user has tried.
    final dir = await profileDir;
    for (final entity in dir.listSync()) {
      if (entity is File && p.basename(entity.path) != fileName) {
        try {
          entity.deleteSync();
        } on FileSystemException {
          // A stale portrait is harmless; nothing references it.
        }
      }
    }

    return fileName;
  }

  Future<Uint8List> readProfileBytes(String fileName) async {
    final file = File(p.join((await profileDir).path, fileName));
    return file.readAsBytes();
  }

  Future<void> deleteProfilePhoto(String fileName) async {
    try {
      final file = File(p.join((await profileDir).path, fileName));
      if (await file.exists()) await file.delete();
    } on FileSystemException catch (e) {
      debugPrint('ImageStore: could not delete portrait $fileName: $e');
    }
  }

  /// Reads a garment photo back, for sending to the model.
  Future<Uint8List> readItemBytes(String fileName) async {
    final file = await itemFile(fileName);
    return file.readAsBytes();
  }

  Future<void> deleteItemImage(String fileName) async {
    try {
      final file = await itemFile(fileName);
      if (await file.exists()) await file.delete();
    } on FileSystemException catch (e) {
      // An orphaned image wastes a little space; failing the delete would
      // leave a database row pointing at nothing, which is worse.
      debugPrint('ImageStore: could not delete $fileName: $e');
    }
  }

  Future<void> deletePreview(String fileName) async {
    try {
      final file = await previewFile(fileName);
      if (await file.exists()) await file.delete();
    } on FileSystemException catch (e) {
      debugPrint('ImageStore: could not delete preview $fileName: $e');
    }
  }
}

/// Runs in an isolate via [compute]: decoding a full-resolution photo on the
/// UI isolate drops frames visibly.
///
/// Returns the input untouched if decoding fails, so an unsupported format
/// surfaces as a model-side error rather than a silent blank. Note that
/// package:image cannot decode HEIC; `image_picker` hands back JPEG on both
/// platforms, so this only matters for files imported by other means.
Uint8List _downscaleJpeg(Uint8List bytes) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) return bytes;

  // Honour EXIF rotation, or half the photos come in sideways.
  final oriented = img.bakeOrientation(decoded);

  const maxEdge = ImageStore.itemMaxEdge;
  final needsResize = oriented.width > maxEdge || oriented.height > maxEdge;

  final out =
      needsResize
          ? (oriented.width >= oriented.height
              ? img.copyResize(oriented, width: maxEdge)
              : img.copyResize(oriented, height: maxEdge))
          : oriented;

  return Uint8List.fromList(
    img.encodeJpg(out, quality: ImageStore._jpegQuality),
  );
}
