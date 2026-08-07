import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';

import '../data/profile_repository.dart';
import '../models/outfit.dart';
import '../models/user_profile.dart';

/// Owns the wearer's profile.
///
/// Holds the single source of truth that the scoring and preview paths read
/// from, so there is never a window where a score is computed against one
/// profile and cached under another's fingerprint.
class ProfileViewModel extends ChangeNotifier {
  final ProfileRepository _profiles;
  final ImagePicker _picker;

  ProfileViewModel({required ProfileRepository profiles, ImagePicker? picker})
    : _profiles = profiles,
      _picker = picker ?? ImagePicker();

  UserProfile _profile = UserProfile.empty;
  UserProfile get profile => _profile;

  bool _loading = true;
  bool get loading => _loading;

  bool _busy = false;
  bool get busy => _busy;

  String? _error;
  String? get error => _error;

  /// Fingerprint of the last saved styling context.
  ///
  /// Compared against a pending edit so the UI can warn *before* saving that a
  /// change will cost a rescore, rather than after the cache has already been
  /// orphaned.
  String get fingerprint => _profile.fingerprint;

  Future<void> load() async {
    _loading = true;
    notifyListeners();
    try {
      _profile = await _profiles.load();
    } on Exception catch (e) {
      debugPrint('Profile: load failed: $e');
      _profile = UserProfile.empty;
    }
    _loading = false;
    notifyListeners();
  }

  /// True when [candidate] would invalidate cached scores.
  bool wouldInvalidateCache(UserProfile candidate) =>
      candidate.fingerprint != _profile.fingerprint;

  Future<void> save(UserProfile updated) async {
    _busy = true;
    _error = null;
    notifyListeners();

    try {
      await _profiles.save(updated);
      _profile = updated;
    } on Exception catch (e) {
      debugPrint('Profile: save failed: $e');
      _error = 'Could not save your profile.';
    }

    _busy = false;
    notifyListeners();
  }

  /// Replaces the portrait. Render-only, so this never affects cached scores.
  Future<void> setPhoto(ImageSource source) async {
    XFile? picked;
    try {
      picked = await _picker.pickImage(
        source: source,
        maxWidth: 2048,
        maxHeight: 2048,
        imageQuality: 92,
      );
    } on Exception catch (e) {
      debugPrint('Profile: picker failed: $e');
      _error =
          source == ImageSource.camera
              ? 'Could not open the camera.'
              : 'Could not open your photos.';
      notifyListeners();
      return;
    }

    if (picked == null) return;

    _busy = true;
    _error = null;
    notifyListeners();

    try {
      final fileName = await _profiles.savePhoto(File(picked.path));
      final updated = _profile.copyWith(photoFileName: fileName);
      await _profiles.save(updated);
      _profile = updated;
    } on Exception catch (e) {
      debugPrint('Profile: photo save failed: $e');
      _error = 'Could not save that photo.';
    }

    _busy = false;
    notifyListeners();
  }

  Future<void> removePhoto() async {
    final existing = _profile.photoFileName;
    if (existing == null) return;

    final updated = _profile.copyWith(clearPhoto: true);
    await save(updated);
    await _profiles.deletePhoto(existing);
  }

  /// Convenience mutators used by the editor. Each persists immediately, so
  /// there is no half-saved state if the user backs out mid-edit.
  Future<void> setUndertone(Undertone? value) => save(
    value == null
        ? _profile.copyWith(clearUndertone: true)
        : _profile.copyWith(undertone: value),
  );

  Future<void> setHeightBand(HeightBand? value) => save(
    value == null
        ? _profile.copyWith(clearHeightBand: true)
        : _profile.copyWith(heightBand: value),
  );

  Future<void> setBuild(BuildType? value) => save(
    value == null
        ? _profile.copyWith(clearBuild: true)
        : _profile.copyWith(build: value),
  );

  Future<void> toggleOccasion(LookTag tag) {
    final next = Set<LookTag>.of(_profile.occasions);
    if (!next.remove(tag)) next.add(tag);
    return save(_profile.copyWith(occasions: next));
  }

  Future<void> setDetails({
    String? displayName,
    int? age,
    int? heightCm,
    int? weightKg,
    String? presentation,
  }) => save(
    _profile.copyWith(
      displayName: displayName,
      age: age,
      heightCm: heightCm,
      weightKg: weightKg,
      presentation: presentation,
    ),
  );

  void clearError() {
    if (_error == null) return;
    _error = null;
    notifyListeners();
  }
}
