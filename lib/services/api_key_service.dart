import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Holds the user's own Gemini API key.
///
/// The key goes into the platform keystore — Android Keystore, iOS Keychain —
/// and nowhere else. Not in source, not in the database, not in
/// shared_preferences. This matters more than it might seem for a client app:
/// an APK can be unpacked in a minute, so a key compiled into the binary is a
/// published key. Asking each user for their own means a leaked build can only
/// ever bill the person who built it.
class ApiKeyService extends ChangeNotifier {
  static const _storageKey = 'gemini_api_key';

  final FlutterSecureStorage _storage;

  ApiKeyService({FlutterSecureStorage? storage})
    : _storage =
          storage ??
          const FlutterSecureStorage(
            aOptions: AndroidOptions(encryptedSharedPreferences: true),
            iOptions: IOSOptions(
              accessibility: KeychainAccessibility.first_unlock,
            ),
          );

  String? _key;
  bool _loaded = false;

  /// True once the keystore has been read, so the UI can tell "no key yet"
  /// apart from "haven't looked".
  bool get isLoaded => _loaded;

  bool get hasKey => (_key ?? '').isNotEmpty;

  String? get key => _key;

  /// Enough of the key to confirm which one is installed, without showing it.
  String get masked {
    final k = _key;
    if (k == null || k.length < 4) return '••••';
    return '••••••••${k.substring(k.length - 4)}';
  }

  Future<void> load() async {
    try {
      _key = await _storage.read(key: _storageKey);
    } on Exception catch (e) {
      // A corrupt keystore entry should not stop the app from starting.
      debugPrint('ApiKeyService: read failed, treating as absent: $e');
      _key = null;
    }
    _loaded = true;
    notifyListeners();
  }

  Future<void> save(String raw) async {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) {
      await clear();
      return;
    }
    await _storage.write(key: _storageKey, value: trimmed);
    _key = trimmed;
    notifyListeners();
  }

  Future<void> clear() async {
    await _storage.delete(key: _storageKey);
    _key = null;
    notifyListeners();
  }

  /// Catches obvious paste mistakes before spending a network round trip.
  /// The real check is a live call — see `GeminiService.validateKey`.
  static String? checkFormat(String raw) {
    final k = raw.trim();
    if (k.isEmpty) return 'Paste a key to continue.';
    if (k.contains(RegExp(r'\s'))) {
      return 'That key contains a space. Check what was pasted.';
    }
    if (k.startsWith('sk-')) {
      return 'That is an OpenAI key. Gemini keys begin with AIza.';
    }
    if (!k.startsWith('AIza')) {
      return 'Gemini keys begin with AIza. Check the whole key was copied.';
    }
    if (k.length < 30) return 'That key looks too short to be complete.';
    return null;
  }
}
