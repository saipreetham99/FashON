import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';

import '../data/item_repository.dart';
import '../models/clothing_item.dart';

enum ClosetStatus { loading, ready, saving, error }

/// Owns the closet: everything the user has photographed.
///
/// Every garment that enters the app lands here first, and nothing else in the
/// app invents items — Match and Combinations both read from this list, so the
/// closet is the single source of truth for what exists.
class ClosetViewModel extends ChangeNotifier {
  final ItemRepository _items;
  final ImagePicker _picker;

  ClosetViewModel({required ItemRepository items, ImagePicker? picker})
    : _items = items,
      _picker = picker ?? ImagePicker() {
    load();
  }

  /// Called after the closet gains or loses a garment.
  ///
  /// A callback rather than a direct dependency on the backfill service: the
  /// closet should not need to know that background scoring exists, and keeping
  /// the arrow pointing this way means the service layer never has to import a
  /// viewmodel.
  void Function(List<ClothingItem> closet)? onClosetChanged;

  ClosetStatus _status = ClosetStatus.loading;
  ClosetStatus get status => _status;

  List<ClothingItem> _all = const [];
  List<ClothingItem> get all => _all;

  String? _error;
  String? get error => _error;

  bool get isEmpty => _all.isEmpty;

  /// Garments grouped by category, in head-to-toe order, skipping empties.
  Map<GarmentCategory, List<ClothingItem>> get grouped {
    final out = <GarmentCategory, List<ClothingItem>>{};
    for (final category in GarmentCategory.values) {
      final matching = _all
          .where((item) => item.category == category)
          .toList(growable: false);
      if (matching.isNotEmpty) out[category] = matching;
    }
    return out;
  }

  List<ClothingItem> ofCategory(GarmentCategory category) =>
      _all.where((item) => item.category == category).toList(growable: false);

  ClothingItem? byId(String id) {
    for (final item in _all) {
      if (item.id == id) return item;
    }
    return null;
  }

  /// Categories with at least two garments, which is the minimum for the
  /// category to be worth offering as something to search within.
  List<GarmentCategory> get categoriesWithChoice => GarmentCategory.values
      .where((c) => ofCategory(c).length >= 2)
      .toList(growable: false);

  Future<void> load() async {
    _status = ClosetStatus.loading;
    _error = null;
    notifyListeners();

    try {
      _all = await _items.all();
      _status = ClosetStatus.ready;
      // Also fires on load, not just on add: otherwise an existing closet is
      // invisible to the backfill until the user happens to add something, and
      // work left over from a previous session would never resume.
      onClosetChanged?.call(_all);
    } on Exception catch (e) {
      debugPrint('Closet: load failed: $e');
      _error = 'Could not open your closet.';
      _status = ClosetStatus.error;
    }
    notifyListeners();
  }

  /// Photographs a garment with the camera and files it under [category].
  ///
  /// Returns the new garment, or null if the user backed out of the camera.
  Future<ClothingItem?> addFromCamera(GarmentCategory category) =>
      _addFrom(ImageSource.camera, category);

  /// Picks an existing photo instead of shooting a new one.
  Future<ClothingItem?> addFromGallery(GarmentCategory category) =>
      _addFrom(ImageSource.gallery, category);

  Future<ClothingItem?> _addFrom(
    ImageSource source,
    GarmentCategory category,
  ) async {
    XFile? picked;
    try {
      picked = await _picker.pickImage(
        source: source,
        // Let the plugin do a first pass, then ImageStore does the precise
        // resize. Two cheap steps beat decoding a 12MP file in Dart.
        maxWidth: 2048,
        maxHeight: 2048,
        imageQuality: 92,
      );
    } on Exception catch (e) {
      debugPrint('Closet: picker failed: $e');
      _error =
          source == ImageSource.camera
              ? 'Could not open the camera.'
              : 'Could not open your photos.';
      _status = ClosetStatus.error;
      notifyListeners();
      return null;
    }

    if (picked == null) return null;

    _status = ClosetStatus.saving;
    _error = null;
    notifyListeners();

    try {
      final item = await _items.add(
        sourceImage: File(picked.path),
        category: category,
      );
      _all = [item, ..._all];
      _status = ClosetStatus.ready;
      notifyListeners();
      onClosetChanged?.call(_all);
      return item;
    } on Exception catch (e) {
      debugPrint('Closet: save failed: $e');
      _error = 'Could not save that photo.';
      _status = ClosetStatus.error;
      notifyListeners();
      return null;
    }
  }

  Future<void> rename(ClothingItem item, String? label) async {
    final cleaned = (label ?? '').trim();
    final value = cleaned.isEmpty ? null : cleaned;
    try {
      await _items.updateLabel(item.id, value);
      _all = _all
          .map((i) => i.id == item.id ? i.copyWith(label: value) : i)
          .toList(growable: false);
      notifyListeners();
    } on Exception catch (e) {
      debugPrint('Closet: rename failed: $e');
    }
  }

  /// Deletes a garment, its photo, and every cached pairing that involved it.
  ///
  /// The pairings go via the database's cascade rather than an explicit sweep,
  /// so there is no window where a score points at a garment that is gone.
  Future<void> remove(ClothingItem item) async {
    try {
      await _items.delete(item);
      _all = _all.where((i) => i.id != item.id).toList(growable: false);
      notifyListeners();
      onClosetChanged?.call(_all);
    } on Exception catch (e) {
      debugPrint('Closet: delete failed: $e');
      _error = 'Could not remove that garment.';
      notifyListeners();
    }
  }

  void clearError() {
    if (_error == null) return;
    _error = null;
    if (_status == ClosetStatus.error) _status = ClosetStatus.ready;
    notifyListeners();
  }
}
