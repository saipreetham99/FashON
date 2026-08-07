import 'outfit.dart';

/// Skin undertone. Feeds the colour-harmony pillar, which is 40% of a score.
enum Undertone {
  warm,
  cool,
  neutral,
  unsure;

  String get label => switch (this) {
    Undertone.warm => 'Warm',
    Undertone.cool => 'Cool',
    Undertone.neutral => 'Neutral',
    Undertone.unsure => 'Not sure',
  };

  /// Phrasing handed to the model. Kept as guidance about colour, never about
  /// the person.
  String get guidance => switch (this) {
    Undertone.warm =>
      'warm undertone: golden, peach, olive and earth tones flatter; '
          'stark cool blue-greys fight it',
    Undertone.cool =>
      'cool undertone: blue-based, jewel and true-grey tones flatter; '
          'orange-yellows fight it',
    Undertone.neutral => 'neutral undertone: both warm and cool palettes work',
    Undertone.unsure => 'undertone unknown: judge colour on its own terms',
  };

  static Undertone? fromName(String? name) {
    for (final value in Undertone.values) {
      if (value.name == name) return value;
    }
    return null;
  }
}

/// Self-described height, as a band rather than a measurement.
///
/// A band and not centimetres on purpose: proportion advice only changes at
/// coarse thresholds, and gendered height norms make a single numeric scale
/// misleading. It also keeps the exact figure out of the cache fingerprint, so
/// correcting your height by a centimetre never triggers a rescore.
enum HeightBand {
  petite,
  average,
  tall;

  String get label => switch (this) {
    HeightBand.petite => 'Petite',
    HeightBand.average => 'Average',
    HeightBand.tall => 'Tall',
  };

  String get guidance => switch (this) {
    HeightBand.petite =>
      'petite frame: cropped and high-waisted proportions lengthen; '
          'long heavy layers overwhelm',
    HeightBand.average => 'average frame: standard proportions read true',
    HeightBand.tall =>
      'tall frame: long lines and full-length layers suit; '
          'cropped hems can look accidental',
  };

  static HeightBand? fromName(String? name) {
    for (final value in HeightBand.values) {
      if (value.name == name) return value;
    }
    return null;
  }
}

/// Self-described build. Feeds the silhouette and proportion pillar.
enum BuildType {
  slim,
  athletic,
  average,
  curvy,
  broad;

  String get label => switch (this) {
    BuildType.slim => 'Slim',
    BuildType.athletic => 'Athletic',
    BuildType.average => 'Average',
    BuildType.curvy => 'Curvy',
    BuildType.broad => 'Broad',
  };

  String get guidance => switch (this) {
    BuildType.slim =>
      'slim build: structure and volume add presence; cling reads thin',
    BuildType.athletic =>
      'athletic build: defined shoulders take structure well',
    BuildType.average => 'average build: most silhouettes read true',
    BuildType.curvy =>
      'curvy build: defined waists and drape flatter; boxy cuts flatten',
    BuildType.broad =>
      'broad build: clean vertical lines and unfussy cuts suit',
  };

  static BuildType? fromName(String? name) {
    for (final value in BuildType.values) {
      if (value.name == name) return value;
    }
    return null;
  }
}

/// Who the wearer is, split by what the information is allowed to affect.
///
/// **Styling fields** — [undertone], [heightBand], [build], [occasions] — each
/// map onto a scoring pillar, so they legitimately change what a good pairing
/// is. They are part of [fingerprint], and changing one invalidates cached
/// scores.
///
/// **Render fields** — [displayName], [age], [heightCm], [weightKg],
/// [presentation], [photoFileName] — only shape the generated preview. Previews
/// are never cached, so these can change as often as the user likes and cost
/// nothing.
///
/// That split is the whole design. It means a user can correct their weight or
/// swap their photo freely, and only a deliberate change to how they want to be
/// styled ever spends money re-scoring.
class UserProfile {
  // --- Styling ---
  final Undertone? undertone;
  final HeightBand? heightBand;
  final BuildType? build;
  final Set<LookTag> occasions;

  // --- Render only ---
  final String? displayName;
  final int? age;
  final int? heightCm;
  final int? weightKg;
  final String? presentation;
  final String? photoFileName;

  const UserProfile({
    this.undertone,
    this.heightBand,
    this.build,
    this.occasions = const {},
    this.displayName,
    this.age,
    this.heightCm,
    this.weightKg,
    this.presentation,
    this.photoFileName,
  });

  static const empty = UserProfile();

  /// True when nothing has been filled in.
  bool get isEmpty =>
      undertone == null &&
      heightBand == null &&
      build == null &&
      occasions.isEmpty &&
      displayName == null &&
      age == null &&
      heightCm == null &&
      weightKg == null &&
      presentation == null &&
      photoFileName == null;

  /// True when at least one field influences scoring.
  bool get hasStylingContext =>
      undertone != null ||
      heightBand != null ||
      build != null ||
      occasions.isNotEmpty;

  bool get hasPhoto => (photoFileName ?? '').isNotEmpty;

  /// Whether the photo may be used as a likeness reference when rendering.
  ///
  /// Generating realistic full-body imagery of a minor is not something this
  /// app will do, so a stated age under 18 renders the garments without a
  /// person reference instead.
  bool get mayUsePhotoAsLikeness => hasPhoto && (age == null || age! >= 18);

  /// Canonical, stable identity of the scoring-relevant fields.
  ///
  /// Stored alongside each cached verdict; a mismatch is treated as a cache
  /// miss. Readable rather than hashed so a surprising invalidation can be
  /// diagnosed by looking at the row, and because Dart's `hashCode` is not
  /// guaranteed stable across runs, which would silently void the whole cache
  /// on an upgrade.
  String get fingerprint {
    if (!hasStylingContext) return 'none';

    final occasionNames = occasions.map((o) => o.name).toList()..sort();
    return [
      'u:${undertone?.name ?? '-'}',
      'h:${heightBand?.name ?? '-'}',
      'b:${build?.name ?? '-'}',
      'o:${occasionNames.isEmpty ? '-' : occasionNames.join(',')}',
    ].join('|');
  }

  /// The block injected into the scoring prompt, or null when there is nothing
  /// to say.
  ///
  /// Phrased as scoring criteria, never as description. The prompt separately
  /// forbids commenting on the wearer, so this can inform the judgement without
  /// licensing remarks about the person.
  String? get stylingContext {
    if (!hasStylingContext) return null;

    final lines = <String>[];
    if (undertone != null) lines.add('- Colour: ${undertone!.guidance}.');
    if (heightBand != null) lines.add('- Proportion: ${heightBand!.guidance}.');
    if (build != null) lines.add('- Silhouette: ${build!.guidance}.');
    if (occasions.isNotEmpty) {
      final names = occasions.map((o) => o.label.toLowerCase()).join(', ');
      lines.add('- Usually dressing for: $names.');
    }
    return lines.join('\n');
  }

  /// Physique note for the preview prompt. Render-only fields are welcome here.
  String? get renderNote {
    final parts = <String>[];
    if (presentation != null && presentation!.trim().isNotEmpty) {
      parts.add(presentation!.trim());
    }
    if (heightCm != null) parts.add('${heightCm}cm tall');
    if (weightKg != null) parts.add('${weightKg}kg');
    if (build != null) parts.add('${build!.label.toLowerCase()} build');
    if (age != null) parts.add('around $age years old');
    if (parts.isEmpty) return null;
    return 'Model to resemble: ${parts.join(', ')}.';
  }

  UserProfile copyWith({
    Undertone? undertone,
    bool clearUndertone = false,
    HeightBand? heightBand,
    bool clearHeightBand = false,
    BuildType? build,
    bool clearBuild = false,
    Set<LookTag>? occasions,
    String? displayName,
    int? age,
    int? heightCm,
    int? weightKg,
    String? presentation,
    String? photoFileName,
    bool clearPhoto = false,
  }) {
    return UserProfile(
      undertone: clearUndertone ? null : undertone ?? this.undertone,
      heightBand: clearHeightBand ? null : heightBand ?? this.heightBand,
      build: clearBuild ? null : build ?? this.build,
      occasions: occasions ?? this.occasions,
      displayName: displayName ?? this.displayName,
      age: age ?? this.age,
      heightCm: heightCm ?? this.heightCm,
      weightKg: weightKg ?? this.weightKg,
      presentation: presentation ?? this.presentation,
      photoFileName: clearPhoto ? null : photoFileName ?? this.photoFileName,
    );
  }

  factory UserProfile.fromRow(Map<String, Object?> row) {
    final rawOccasions = (row['occasions'] as String?) ?? '';
    return UserProfile(
      undertone: Undertone.fromName(row['undertone'] as String?),
      heightBand: HeightBand.fromName(row['height_band'] as String?),
      build: BuildType.fromName(row['build_type'] as String?),
      occasions:
          rawOccasions.isEmpty
              ? const {}
              : rawOccasions.split(',').map((n) => LookTag.fromName(n)).toSet(),
      displayName: row['display_name'] as String?,
      age: (row['age'] as num?)?.toInt(),
      heightCm: (row['height_cm'] as num?)?.toInt(),
      weightKg: (row['weight_kg'] as num?)?.toInt(),
      presentation: row['presentation'] as String?,
      photoFileName: row['photo_file'] as String?,
    );
  }

  Map<String, Object?> toRow() => {
    'id': 'me',
    'undertone': undertone?.name,
    'height_band': heightBand?.name,
    'build_type': build?.name,
    'occasions': occasions.map((o) => o.name).join(','),
    'display_name': displayName,
    'age': age,
    'height_cm': heightCm,
    'weight_kg': weightKg,
    'presentation': presentation,
    'photo_file': photoFileName,
  };
}
