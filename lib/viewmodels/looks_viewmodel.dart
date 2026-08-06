import 'package:flutter/foundation.dart';

import '../data/look_repository.dart';
import '../models/outfit.dart';

/// Saved looks, filtered by tag.
class LooksViewModel extends ChangeNotifier {
  final LookRepository _looks;

  LooksViewModel({required LookRepository looks}) : _looks = looks {
    load();
  }

  bool _loading = true;
  bool get loading => _loading;

  List<Look> _all = const [];
  List<Look> get all => _all;

  LookTag? _tag;
  LookTag? get tag => _tag;

  bool get isEmpty => _all.isEmpty;

  List<Look> get visible {
    final tag = _tag;
    if (tag == null) return _all;
    return _all.where((look) => look.tag == tag).toList(growable: false);
  }

  /// Only tags that have at least one look, so the filter row never offers a
  /// choice that leads to an empty screen.
  List<LookTag> get usedTags {
    final present = _all.map((l) => l.tag).toSet();
    return LookTag.values.where(present.contains).toList(growable: false);
  }

  Future<void> load() async {
    _loading = true;
    notifyListeners();

    try {
      _all = await _looks.all();
    } on Exception catch (e) {
      debugPrint('Looks: load failed: $e');
      _all = const [];
    }

    _loading = false;
    notifyListeners();
  }

  void setTag(LookTag? tag) {
    if (_tag == tag) return;
    _tag = tag;
    notifyListeners();
  }

  Future<void> remove(Look look) async {
    try {
      await _looks.delete(look);
      _all = _all.where((l) => l.id != look.id).toList(growable: false);
      notifyListeners();
    } on Exception catch (e) {
      debugPrint('Looks: delete failed: $e');
    }
  }
}
