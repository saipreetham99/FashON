import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../data/image_store.dart';
import '../models/clothing_item.dart';
import '../models/pair_score.dart';
import '../models/user_profile.dart';
import 'api_key_service.dart';

/// A Gemini failure worth showing the user.
class GeminiException implements Exception {
  final String message;
  final int? statusCode;

  /// True when the key is the problem, so the UI can send the user to Settings
  /// rather than offering a retry that cannot succeed.
  final bool isAuthFailure;

  const GeminiException(
    this.message, {
    this.statusCode,
    this.isAuthFailure = false,
  });

  @override
  String toString() => message;
}

/// Talks to the Gemini REST API with the user's own key.
///
/// Raw REST rather than a generated client, deliberately: model names stay
/// plain strings, so a new model works the day it ships without waiting on a
/// package release.
class GeminiService {
  /// Scoring model. Text plus vision.
  static const String scoringModel = 'gemini-3.6-flash';

  /// Nano Banana 2, for rendering an outfit worn.
  static const String imageModel = 'gemini-3.1-flash-image';

  static const String _base =
      'https://generativelanguage.googleapis.com/v1beta/models';

  /// Bump when [_scoringPrompt] changes.
  ///
  /// Cached verdicts carry this number, and anything older is ignored rather
  /// than shown next to fresh scores. Nothing needs deleting: the cache simply
  /// stops answering for the old rubric.
  static const int promptVersion = 1;

  final ApiKeyService _apiKeys;
  final ImageStore _images;
  final http.Client _client;

  /// Base64 payloads keyed by file name.
  ///
  /// Scoring one garment against four others would otherwise read and encode
  /// the same photo four times. Photos are already downscaled on disk, so this
  /// is only avoiding repeated IO and base64 work, but on a 40-item ranking
  /// that adds up.
  final Map<String, String> _encodedCache = <String, String>{};

  GeminiService({
    required ApiKeyService apiKeys,
    required ImageStore images,
    http.Client? client,
  }) : _apiKeys = apiKeys,
       _images = images,
       _client = client ?? http.Client();

  String _requireKey() {
    final key = _apiKeys.key;
    if (key == null || key.isEmpty) {
      throw const GeminiException(
        'Add your Gemini API key in Settings to score outfits.',
        isAuthFailure: true,
      );
    }
    return key;
  }

  // ---------------------------------------------------------------------------
  // The rubric
  // ---------------------------------------------------------------------------

  /// Returns no garment description on purpose.
  ///
  /// The user is looking at both photos already; describing them back is filler
  /// that costs tokens and reading time. Every field here is something the
  /// photos cannot tell them: why it scores what it scores, and what to change.
  static const String _scoringPrompt = '''
You are FashON, a fashion evaluation engine. You are given exactly two garments
as images. Judge only the garments. Never comment on the body, face, skin, or
attractiveness of any person visible in the images.

STEP 1 - VALIDATE
If the images do not show two distinct wearable garments, set "valid" false,
"score" 0, and leave every array empty.

STEP 2 - SCORE the pairing 0 to 10 on these weighted pillars:
1. Colour harmony, 40%. Undertone agreement, value contrast, saturation
   balance. Two competing busy patterns is a heavy penalty.
2. Texture and material synergy, 30%. Do the fabric weights and drapes belong
   in one outfit? Season consistency counts: heavy knit with summer linen
   loses points.
3. Silhouette and proportion, 20%. Volume distribution and waist definition.
   Oversized on oversized with no structure, or tight on tight with no relief,
   both lose points.
4. Style and occasion cohesion, 10%. Same style family and formality tier, or
   a deliberate contrast that earns itself.

Calibration: 9-10 exceptional and intentional. 7-8 solid, would wear.
5-6 functional but forgettable. 3-4 real conflicts. 0-2 actively wrong.
Be honest. Do not drift toward 7.

STEP 3 - ADVISE. Short, concrete entries. Maximum 12 words each.
- "boosting": what earns points. 1 to 3 entries.
- "costing": what loses points. 1 to 3 entries. Empty only if truly nothing.
- "improve": changes that would raise the score. 1 to 3 entries. Name the
  actual move: a colour, a fabric, a fit change, tuck or untuck, a layer.
- "shoes": footwear that completes this pairing. 1 to 3 entries. Be specific
  about style and colour, for example "white leather low-top sneakers".
- "accessories": belt, bag, watch, eyewear, jewellery, or headwear that
  completes this pairing. 1 to 3 entries.

Never describe what the garments are. Never restate the score as prose. Never
mention pillars, weights, percentages, or that you are a model.

OUTPUT
Return one JSON object and nothing else. No markdown, no fences, no preamble.
{"valid":true,"score":0.0,"boosting":[],"costing":[],"improve":[],"shoes":[],"accessories":[]}
''';

  // ---------------------------------------------------------------------------
  // Public API
  // ---------------------------------------------------------------------------

  /// Confirms a key works, with a tiny text-only call.
  ///
  /// Cheaper than sending images, and separates "bad key" from "no network" so
  /// Settings can say something true.
  Future<void> validateKey(String rawKey) async {
    final uri = Uri.parse('$_base/$scoringModel:generateContent');
    try {
      final res = await _client
          .post(
            uri,
            headers: {
              'Content-Type': 'application/json',
              'x-goog-api-key': rawKey.trim(),
            },
            body: jsonEncode({
              'contents': [
                {
                  'parts': [
                    {'text': 'Reply with the single word: ok'},
                  ],
                },
              ],
            }),
          )
          .timeout(const Duration(seconds: 20));

      if (res.statusCode == 200) return;
      throw _errorFor(res.statusCode, res.body);
    } on GeminiException {
      rethrow;
    } on Exception catch (e) {
      throw GeminiException(
        'Could not reach Gemini. Check the connection. ($e)',
      );
    }
  }

  /// Scores one pairing. The only place a pair is sent to the model.
  ///
  /// [profile] contributes only its styling fields, and only as scoring
  /// criteria: the prompt still forbids any remark about the wearer. When the
  /// profile has no styling context the request is byte-identical to the
  /// profile-free version, which is what keeps an existing cache valid.
  Future<PairScore> scorePair(
    ClothingItem a,
    ClothingItem b, {
    UserProfile profile = UserProfile.empty,
  }) async {
    final key = _requireKey();

    final encodedA = await _encoded(a.fileName);
    final encodedB = await _encoded(b.fileName);

    final json = await _postForJson(
      model: scoringModel,
      apiKey: key,
      timeout: const Duration(seconds: 60),
      body: {
        'contents': [
          {
            'parts': [
              {'text': _promptFor(profile)},
              {'text': 'Garment 1 (${a.category.label}):'},
              {
                'inline_data': {'mime_type': 'image/jpeg', 'data': encodedA},
              },
              {'text': 'Garment 2 (${b.category.label}):'},
              {
                'inline_data': {'mime_type': 'image/jpeg', 'data': encodedB},
              },
            ],
          },
        ],
        // gemini-3.6-flash ignores temperature, top_p and top_k, and errors on
        // frequency or presence penalties, so there is nothing to tune. All
        // consistency has to come from the prompt itself.
        'generationConfig': {'response_mime_type': 'application/json'},
      },
    );

    return PairScore.fromModelJson(
      json,
      itemIdA: a.id,
      itemIdB: b.id,
      model: scoringModel,
      promptVersion: promptVersion,
      profileFingerprint: profile.fingerprint,
    );
  }

  /// The rubric, with a wearer block appended when there is one.
  static String _promptFor(UserProfile profile) {
    final context = profile.stylingContext;
    if (context == null) return _scoringPrompt;

    return '''$_scoringPrompt

WEARER CONTEXT — apply as scoring criteria only.
$context

Weigh colour against the stated undertone, and proportion and silhouette against
the stated frame and build. Let the stated occasions inform style cohesion.
Never describe, rate, or refer to the wearer's body, face, or appearance in any
output field; the advice must read as being about the clothes.''';
  }

  /// Renders the given garments worn together as one outfit.
  ///
  /// Uses the profile photo as a likeness reference when
  /// [UserProfile.mayUsePhotoAsLikeness] allows it, and the physique fields
  /// regardless. Returns image bytes; the caller decides whether to keep them.
  Future<Uint8List> generateOutfitPreview({
    required List<ClothingItem> items,
    UserProfile profile = UserProfile.empty,
    String? note,
  }) async {
    final key = _requireKey();
    if (items.isEmpty) {
      throw const GeminiException('Pick at least one garment to preview.');
    }

    // Render-only fields are all fair game here: previews are never cached, so
    // physique and presentation can change as often as the user likes.
    final physique = profile.renderNote;
    final useLikeness = profile.mayUsePhotoAsLikeness;

    final parts = <Map<String, dynamic>>[
      {
        'text':
            'Render one photorealistic full-body studio photograph of a '
            'single model wearing all ${items.length} reference garments '
            'together as one outfit. Every reference garment must appear, and '
            'must keep its own colour, pattern, and cut. Seamless neutral '
            'background, soft even lighting, relaxed natural pose, sharp focus.'
            '${physique == null ? '' : ' $physique'}'
            '${useLikeness ? ' Use the portrait reference for the model\'s face and build.' : ''}'
            '${note == null || note.isEmpty ? '' : ' $note'}',
      },
    ];

    if (useLikeness) {
      parts.add({'text': 'Portrait reference (the wearer):'});
      parts.add({
        'inline_data': {
          'mime_type': 'image/jpeg',
          'data': base64Encode(
            await _images.readProfileBytes(profile.photoFileName!),
          ),
        },
      });
    }

    for (final item in items) {
      parts.add({'text': 'Reference (${item.category.label}):'});
      parts.add({
        'inline_data': {
          'mime_type': 'image/jpeg',
          'data': await _encoded(item.fileName),
        },
      });
    }

    final decoded = await _post(
      model: imageModel,
      apiKey: key,
      timeout: const Duration(seconds: 120),
      body: {
        'contents': [
          {'parts': parts},
        ],
      },
    );

    final bytes = _firstImage(decoded);
    if (bytes == null) {
      throw const GeminiException('The model returned no image. Try again.');
    }
    return bytes;
  }

  // ---------------------------------------------------------------------------
  // Transport
  // ---------------------------------------------------------------------------

  Future<Map<String, dynamic>> _postForJson({
    required String model,
    required String apiKey,
    required Map<String, dynamic> body,
    required Duration timeout,
  }) async {
    final decoded = await _post(
      model: model,
      apiKey: apiKey,
      body: body,
      timeout: timeout,
    );

    final text = _joinText(decoded);
    if (text.isEmpty) {
      throw const GeminiException('Gemini returned nothing. Try again.');
    }

    final parsed = extractJson(text);
    if (parsed == null) {
      throw const GeminiException(
        'Could not read the scoring reply. Try again.',
      );
    }
    return parsed;
  }

  Future<Map<String, dynamic>> _post({
    required String model,
    required String apiKey,
    required Map<String, dynamic> body,
    required Duration timeout,
  }) async {
    final uri = Uri.parse('$_base/$model:generateContent');

    http.Response res;
    try {
      res = await _client
          .post(
            uri,
            headers: {
              'Content-Type': 'application/json',
              'x-goog-api-key': apiKey,
            },
            body: jsonEncode(body),
          )
          .timeout(timeout);
    } on Exception catch (e) {
      throw GeminiException('Network error talking to Gemini. ($e)');
    }

    if (res.statusCode != 200) {
      throw _errorFor(res.statusCode, res.body);
    }

    try {
      return jsonDecode(res.body) as Map<String, dynamic>;
    } on Exception {
      throw const GeminiException('Gemini sent a malformed reply.');
    }
  }

  GeminiException _errorFor(int status, String body) {
    var detail = '';
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map && decoded['error'] is Map) {
        detail = (decoded['error']['message'] ?? '').toString();
      }
    } on Exception {
      detail = body.substring(0, min(body.length, 200));
    }

    return switch (status) {
      400 when detail.toLowerCase().contains('api key') =>
        const GeminiException(
          'That API key was rejected. Check it in Settings.',
          statusCode: 400,
          isAuthFailure: true,
        ),
      400 => GeminiException(
        'Gemini rejected the request. $detail',
        statusCode: 400,
      ),
      401 || 403 => const GeminiException(
        'Your key is not authorised for this model. Check it in Settings.',
        statusCode: 403,
        isAuthFailure: true,
      ),
      429 => const GeminiException(
        'Your key hit its rate limit. Wait a moment, then try again.',
        statusCode: 429,
      ),
      500 || 503 => const GeminiException(
        'Gemini is briefly unavailable. Try again shortly.',
        statusCode: 503,
      ),
      _ => GeminiException('Gemini error $status. $detail', statusCode: status),
    };
  }

  /// Joins every non-thought text part.
  ///
  /// Gemini 3.x can return reasoning parts alongside the answer; concatenating
  /// everything blindly corrupts the JSON.
  String _joinText(Map<String, dynamic> decoded) {
    final candidates = decoded['candidates'];
    if (candidates is! List || candidates.isEmpty) return '';

    final parts = candidates.first['content']?['parts'];
    if (parts is! List) return '';

    final buffer = StringBuffer();
    for (final part in parts) {
      if (part is! Map) continue;
      if (part['thought'] == true) continue;
      final text = part['text'];
      if (text is String) buffer.write(text);
    }
    return buffer.toString().trim();
  }

  Uint8List? _firstImage(Map<String, dynamic> decoded) {
    final candidates = decoded['candidates'];
    if (candidates is! List || candidates.isEmpty) return null;

    final parts = candidates.first['content']?['parts'];
    if (parts is! List) return null;

    for (final part in parts) {
      if (part is! Map) continue;
      final inline = part['inlineData'] ?? part['inline_data'];
      if (inline is Map && inline['data'] is String) {
        try {
          return base64Decode(inline['data'] as String);
        } on FormatException {
          continue;
        }
      }
    }
    return null;
  }

  /// Pulls the outermost JSON object from a reply.
  ///
  /// `response_mime_type` usually makes this redundant, but brace matching
  /// costs nothing and survives the occasional code fence or stray sentence.
  static Map<String, dynamic>? extractJson(String text) {
    try {
      final direct = jsonDecode(text);
      if (direct is Map<String, dynamic>) return direct;
    } on FormatException {
      // Fall through.
    }

    final start = text.indexOf('{');
    final end = text.lastIndexOf('}');
    if (start == -1 || end == -1 || end <= start) return null;

    try {
      final decoded = jsonDecode(text.substring(start, end + 1));
      return decoded is Map<String, dynamic> ? decoded : null;
    } on FormatException {
      return null;
    }
  }

  // ---------------------------------------------------------------------------
  // Images
  // ---------------------------------------------------------------------------

  Future<String> _encoded(String fileName) async {
    final cached = _encodedCache[fileName];
    if (cached != null) return cached;

    final bytes = await _images.readItemBytes(fileName);
    final encoded = base64Encode(bytes);

    // Bounded so a large closet cannot grow this without limit.
    if (_encodedCache.length > 40) _encodedCache.clear();
    _encodedCache[fileName] = encoded;
    return encoded;
  }

  void clearImageCache() => _encodedCache.clear();

  void dispose() {
    _encodedCache.clear();
    _client.close();
  }
}
