import 'dart:io';

import 'package:flutter/material.dart';

import '../../data/image_store.dart';
import '../../models/clothing_item.dart';
import '../../theme/app_theme.dart';

/// A garment photo.
///
/// Selection is shown with a brass frame and a filled corner mark rather than a
/// floating checkbox: the frame reads at thumbnail size, and the mark sits in
/// dead space instead of covering the garment being judged.
class GarmentTile extends StatelessWidget {
  final ClothingItem item;
  final ImageStore images;
  final bool selected;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  /// Overlay shown top-left, usually a [ScorePill].
  final Widget? badge;

  final double radius;

  const GarmentTile({
    super.key,
    required this.item,
    required this.images,
    this.selected = false,
    this.onTap,
    this.onLongPress,
    this.badge,
    this.radius = Radii.tile,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOut,
        decoration: BoxDecoration(
          color: Ink0.card,
          borderRadius: BorderRadius.circular(radius),
          border: Border.all(
            color: selected ? Accent.brass : Bone.hairline,
            width: selected ? 2 : 1,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          fit: StackFit.expand,
          children: [
            GarmentImage(item: item, images: images),

            // Keeps the badge and label legible over a pale garment.
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color(0x55000000),
                    Color(0x00000000),
                    Color(0x66000000),
                  ],
                  stops: [0.0, 0.45, 1.0],
                ),
              ),
              child: SizedBox.expand(),
            ),

            if (badge != null)
              Positioned(top: Gap.sm, left: Gap.sm, child: badge!),

            if (selected)
              Positioned(
                top: 0,
                right: 0,
                child: CustomPaint(
                  size: const Size(30, 30),
                  painter: _CornerMark(),
                  child: const SizedBox(
                    width: 30,
                    height: 30,
                    child: Align(
                      alignment: Alignment(0.45, -0.45),
                      child: Icon(Icons.check, size: 13, color: Ink0.sunken),
                    ),
                  ),
                ),
              ),

            if (item.label != null && item.label!.isNotEmpty)
              Positioned(
                left: Gap.sm,
                right: Gap.sm,
                bottom: Gap.sm,
                child: Text(
                  item.label!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: Bone.full,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// The photo itself, with a graceful fallback if the file has gone missing.
class GarmentImage extends StatelessWidget {
  final ClothingItem item;
  final ImageStore images;
  final BoxFit fit;

  const GarmentImage({
    super.key,
    required this.item,
    required this.images,
    this.fit = BoxFit.cover,
  });

  @override
  Widget build(BuildContext context) {
    return Image.file(
      File(images.itemPathSync(item.fileName)),
      fit: fit,
      // Photos are already downscaled to 1024px on disk; decoding them at
      // thumbnail size keeps a long closet scroll off the raster budget.
      cacheWidth: 512,
      filterQuality: FilterQuality.medium,
      errorBuilder:
          (_, __, ___) => const ColoredBox(
            color: Ink0.card,
            child: Center(
              child: Icon(
                Icons.image_not_supported_outlined,
                color: Bone.faint,
                size: 22,
              ),
            ),
          ),
    );
  }
}

/// Filled triangle in the top-right corner, holding the selection tick.
class _CornerMark extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final path =
        Path()
          ..moveTo(size.width, 0)
          ..lineTo(size.width, size.height)
          ..lineTo(0, 0)
          ..close();
    canvas.drawPath(path, Paint()..color = Accent.brass);
  }

  @override
  bool shouldRepaint(_CornerMark oldDelegate) => false;
}

/// Two garments shown as clipped fabric swatches, angled and overlapping.
///
/// Used wherever a pairing is the subject rather than a single garment. Reading
/// as swatch cards rather than two square thumbnails makes it obvious at a
/// glance that the unit being judged is the combination.
class SwatchPair extends StatelessWidget {
  final ClothingItem a;
  final ClothingItem b;
  final ImageStore images;
  final double height;

  const SwatchPair({
    super.key,
    required this.a,
    required this.b,
    required this.images,
    this.height = 120,
  });

  @override
  Widget build(BuildContext context) {
    final swatch = height * 0.86;

    return SizedBox(
      height: height,
      child: Stack(
        children: [
          Positioned(
            left: 0,
            top: 0,
            child: Transform.rotate(angle: -0.06, child: _swatch(a, swatch)),
          ),
          Positioned(
            left: swatch * 0.58,
            top: height - swatch,
            child: Transform.rotate(angle: 0.07, child: _swatch(b, swatch)),
          ),
        ],
      ),
    );
  }

  Widget _swatch(ClothingItem item, double size) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(Radii.tile * 0.7),
        border: Border.all(color: Ink0.ground, width: 3),
        boxShadow: const [
          BoxShadow(
            color: Color(0x66000000),
            blurRadius: 10,
            offset: Offset(0, 3),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: GarmentImage(item: item, images: images),
    );
  }
}
