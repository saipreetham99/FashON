import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/image_store.dart';
import '../../models/clothing_item.dart';
import '../../theme/app_theme.dart';
import '../../viewmodels/combinations_viewmodel.dart';
import '../widgets/backfill_banner.dart';
import '../widgets/common.dart';
import '../widgets/garment_tile.dart';
import 'pair_detail_screen.dart';

/// Every pairing the app has ever judged, browsable.
///
/// Nothing here calls the model. The grid is pure cache readback, so it opens
/// instantly and costs nothing however often it is used — the whole reason for
/// storing scores rather than recomputing them.
class CombinationsScreen extends StatelessWidget {
  const CombinationsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final combos = context.watch<CombinationsViewModel>();
    final images = context.read<ImageStore>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Combos'),
        actions: [
          IconButton(
            icon: const Icon(Icons.sort),
            tooltip: 'Sort',
            onPressed: () => _pickSort(context, combos),
          ),
          const SizedBox(width: Gap.sm),
        ],
      ),
      body: Column(
        children: [
          // Above the body rather than inside the scroll view: on a fresh
          // closet the grid is empty, and that is exactly when the offer to
          // score pending pairings is most useful.
          const Padding(
            padding: EdgeInsets.only(top: Gap.sm),
            child: BackfillBanner(),
          ),
          Expanded(
            child:
                combos.loading
                    ? const Center(child: CircularProgressIndicator())
                    : combos.totalCached == 0
                    ? const EmptyState(
                      icon: Icons.grid_view_outlined,
                      headline: 'No pairings yet',
                      body:
                          'Score something in Match and it lands here. Once a '
                          'pairing is judged, looking at it again is free.',
                    )
                    : RefreshIndicator(
                      onRefresh: combos.load,
                      color: Accent.brass,
                      backgroundColor: Ink0.card,
                      child: CustomScrollView(
                        slivers: [
                          SliverToBoxAdapter(
                            child: _Summary(combos: combos, images: images),
                          ),
                          SliverToBoxAdapter(
                            child: Padding(
                              padding: const EdgeInsets.only(bottom: Gap.lg),
                              child: FilterRow<GarmentCategory>(
                                options: combos.availableCategories,
                                active: combos.filter,
                                labelOf: (c) => c.label,
                                onChanged: combos.setFilter,
                              ),
                            ),
                          ),
                          SliverPadding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: Gap.xl,
                            ),
                            sliver: SliverGrid(
                              gridDelegate:
                                  const SliverGridDelegateWithFixedCrossAxisCount(
                                    crossAxisCount: 2,
                                    crossAxisSpacing: Gap.md,
                                    mainAxisSpacing: Gap.md,
                                    childAspectRatio: 0.82,
                                  ),
                              delegate: SliverChildBuilderDelegate(
                                childCount: combos.visible.length,
                                (context, index) => _ComboCard(
                                  combination: combos.visible[index],
                                  images: images,
                                ),
                              ),
                            ),
                          ),
                          const SliverToBoxAdapter(
                            child: SizedBox(height: Gap.huge),
                          ),
                        ],
                      ),
                    ),
          ),
        ],
      ),
    );
  }

  Future<void> _pickSort(
    BuildContext context,
    CombinationsViewModel combos,
  ) async {
    final choice = await showModalBottomSheet<CombinationSort>(
      context: context,
      builder:
          (_) => SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                Gap.xl,
                Gap.xl,
                Gap.xl,
                Gap.lg,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Sort by', style: Type.title),
                  const SizedBox(height: Gap.xl),
                  for (final entry
                      in const {
                        CombinationSort.bestFirst: 'Best first',
                        CombinationSort.worstFirst: 'Worst first',
                        CombinationSort.newestFirst: 'Recently scored',
                      }.entries)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(entry.value, style: Type.body),
                      trailing:
                          combos.sort == entry.key
                              ? const Icon(
                                Icons.check,
                                color: Accent.brass,
                                size: 20,
                              )
                              : null,
                      onTap: () => Navigator.pop(context, entry.key),
                    ),
                ],
              ),
            ),
          ),
    );

    if (choice != null) combos.setSort(choice);
  }
}

class _Summary extends StatelessWidget {
  final CombinationsViewModel combos;
  final ImageStore images;

  const _Summary({required this.combos, required this.images});

  @override
  Widget build(BuildContext context) {
    final best = combos.best;
    final average = combos.averageScore;

    return Padding(
      padding: const EdgeInsets.fromLTRB(Gap.xl, 0, Gap.xl, Gap.xl),
      child: Panel(
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${combos.totalCached}', style: Type.display),
                  const SizedBox(height: Gap.xs),
                  Text(
                    combos.totalCached == 1
                        ? 'PAIRING JUDGED'
                        : 'PAIRINGS JUDGED',
                    style: Type.tag,
                  ),
                  if (average != null) ...[
                    const SizedBox(height: Gap.lg),
                    Text(
                      'Averaging ${average.toStringAsFixed(1)}',
                      style: Type.small.copyWith(color: scoreColor(average)),
                    ),
                  ],
                ],
              ),
            ),
            if (best != null)
              Column(
                children: [
                  SwatchPair(a: best.a, b: best.b, images: images, height: 88),
                  const SizedBox(height: Gap.sm),
                  Text(
                    'BEST ${best.score.score.toStringAsFixed(1)}',
                    style: Type.tag.copyWith(color: Accent.brass),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _ComboCard extends StatelessWidget {
  final Combination combination;
  final ImageStore images;

  const _ComboCard({required this.combination, required this.images});

  @override
  Widget build(BuildContext context) {
    final score = combination.score.score;

    return GestureDetector(
      onTap:
          () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => PairDetailScreen(combination: combination),
            ),
          ),
      child: Container(
        decoration: BoxDecoration(
          color: Ink0.card,
          borderRadius: BorderRadius.circular(Radii.card),
          border: Border.all(color: Bone.hairline),
        ),
        padding: const EdgeInsets.all(Gap.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Row(
                children: [
                  Expanded(child: _half(combination.a, topLeft: true)),
                  const SizedBox(width: 3),
                  Expanded(child: _half(combination.b, topLeft: false)),
                ],
              ),
            ),
            const SizedBox(height: Gap.md),
            Row(
              children: [
                Text(
                  score.toStringAsFixed(1),
                  style: Type.numeralSmall.copyWith(
                    fontSize: 20,
                    color: scoreColor(score),
                  ),
                ),
                const SizedBox(width: Gap.sm),
                Expanded(
                  child: Text(
                    scoreVerdict(score),
                    style: Type.small,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              '${combination.a.category.label} + ${combination.b.category.label}',
              style: Type.tag.copyWith(fontSize: 9.5),
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  /// Two garments split down the middle of one frame, so the card reads as a
  /// single pairing rather than two unrelated photos side by side.
  Widget _half(ClothingItem item, {required bool topLeft}) {
    return ClipRRect(
      borderRadius: BorderRadius.only(
        topLeft: Radius.circular(topLeft ? Radii.tile * 0.7 : 0),
        bottomLeft: Radius.circular(topLeft ? Radii.tile * 0.7 : 0),
        topRight: Radius.circular(topLeft ? 0 : Radii.tile * 0.7),
        bottomRight: Radius.circular(topLeft ? 0 : Radii.tile * 0.7),
      ),
      child: GarmentImage(item: item, images: images),
    );
  }
}
