import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/image_store.dart';
import '../../models/clothing_item.dart';
import '../../theme/app_theme.dart';
import '../../viewmodels/combinations_viewmodel.dart';
import '../widgets/common.dart';
import '../widgets/garment_tile.dart';
import '../widgets/score_ring.dart';

/// The full verdict on one pairing, read from cache.
class PairDetailScreen extends StatelessWidget {
  final Combination combination;

  const PairDetailScreen({super.key, required this.combination});

  @override
  Widget build(BuildContext context) {
    final images = context.read<ImageStore>();
    final score = combination.score;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          '${combination.a.category.label} + ${combination.b.category.label}',
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(Gap.xl, 0, Gap.xl, Gap.huge),
        children: [
          Row(
            children: [
              Expanded(child: _photo(combination.a, images)),
              const SizedBox(width: Gap.md),
              Expanded(child: _photo(combination.b, images)),
            ],
          ),
          const SizedBox(height: Gap.xxl),
          Center(child: ScoreRing(score: score.score, size: 140)),
          const SizedBox(height: Gap.xxl),

          AdviceList(
            title: 'Earning points',
            entries: score.boosting,
            color: Accent.eucalyptus,
            icon: Icons.add_circle_outline,
          ),
          if (score.boosting.isNotEmpty && score.costing.isNotEmpty)
            const SizedBox(height: Gap.xl),
          AdviceList(
            title: 'Costing points',
            entries: score.costing,
            color: Accent.clay,
            icon: Icons.remove_circle_outline,
          ),

          if (score.improve.isNotEmpty) ...[
            const SizedBox(height: Gap.xl),
            AdviceList(
              title: 'To improve',
              entries: score.improve,
              color: Accent.brass,
              icon: Icons.auto_fix_high_outlined,
            ),
          ],

          if (score.shoes.isNotEmpty || score.accessories.isNotEmpty) ...[
            const SizedBox(height: Gap.xxl),
            const Divider(),
            const SizedBox(height: Gap.xl),
            const SectionLabel('Complete it'),
            const SizedBox(height: Gap.lg),
            AdviceList(
              title: 'Shoes',
              entries: score.shoes,
              color: Bone.muted,
              icon: Icons.hiking_outlined,
            ),
            if (score.shoes.isNotEmpty && score.accessories.isNotEmpty)
              const SizedBox(height: Gap.lg),
            AdviceList(
              title: 'Accessories',
              entries: score.accessories,
              color: Bone.muted,
              icon: Icons.watch_outlined,
            ),
          ],

          const SizedBox(height: Gap.xxl),
          Text(
            'Judged by ${score.model}',
            style: Type.small.copyWith(color: Bone.faint),
          ),
        ],
      ),
    );
  }

  Widget _photo(ClothingItem item, ImageStore images) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(Radii.card),
      child: AspectRatio(
        aspectRatio: 0.85,
        child: GarmentImage(item: item, images: images),
      ),
    );
  }
}
