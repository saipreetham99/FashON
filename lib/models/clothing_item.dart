/// The garment categories the app knows about.
///
/// Named `GarmentCategory` rather than plain `GarmentCategory` on purpose: Flutter's
/// `foundation.dart` exports an annotation called `GarmentCategory`, and any file
/// importing both fails to compile with an ambiguous import. Do not rename this
/// back.
///
/// Order matters: it is the order the closet renders in, roughly head to toe,
/// which is how people picture an outfit.
enum GarmentCategory {
  outerwear,
  tops,
  bottoms,
  shoes,
  accessories;

  String get label => switch (this) {
    GarmentCategory.outerwear => 'Outerwear',
    GarmentCategory.tops => 'Tops',
    GarmentCategory.bottoms => 'Bottoms',
    GarmentCategory.shoes => 'Shoes',
    GarmentCategory.accessories => 'Accessories',
  };

  /// Singular, for prompts and sentences like "add a top".
  String get singular => switch (this) {
    GarmentCategory.outerwear => 'outerwear piece',
    GarmentCategory.tops => 'top',
    GarmentCategory.bottoms => 'bottoms',
    GarmentCategory.shoes => 'shoes',
    GarmentCategory.accessories => 'accessory',
  };

  static GarmentCategory fromName(String? name) {
    return GarmentCategory.values.firstWhere(
      (c) => c.name == name,
      orElse: () => GarmentCategory.tops,
    );
  }
}

/// A single garment the user photographed.
///
/// Only [fileName] is stored, never an absolute path: the app documents
/// directory moves between OS updates and reinstalls, so paths are resolved at
/// read time by [ImageStore].
class ClothingItem {
  final String id;
  final GarmentCategory category;
  final String fileName;
  final DateTime createdAt;

  /// Optional user note, e.g. "the linen one".
  final String? label;

  const ClothingItem({
    required this.id,
    required this.category,
    required this.fileName,
    required this.createdAt,
    this.label,
  });

  factory ClothingItem.fromRow(Map<String, Object?> row) => ClothingItem(
    id: row['id'] as String,
    category: GarmentCategory.fromName(row['category'] as String?),
    fileName: row['file_name'] as String,
    createdAt: DateTime.fromMillisecondsSinceEpoch(row['created_at'] as int),
    label: row['label'] as String?,
  );

  Map<String, Object?> toRow() => {
    'id': id,
    'category': category.name,
    'file_name': fileName,
    'created_at': createdAt.millisecondsSinceEpoch,
    'label': label,
  };

  ClothingItem copyWith({String? label}) => ClothingItem(
    id: id,
    category: category,
    fileName: fileName,
    createdAt: createdAt,
    label: label ?? this.label,
  );

  @override
  bool operator ==(Object other) =>
      other is ClothingItem && other.id == id && other.label == label;

  @override
  int get hashCode => Object.hash(id, label);
}
