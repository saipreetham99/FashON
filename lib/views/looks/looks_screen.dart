import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/image_store.dart';
import '../../models/clothing_item.dart';
import '../../models/outfit.dart';
import '../../theme/app_theme.dart';
import '../../viewmodels/closet_viewmodel.dart';
import '../../viewmodels/looks_viewmodel.dart';
import '../widgets/common.dart';
import '../widgets/garment_tile.dart';
import '../widgets/score_ring.dart';

/// Saved outfits. The home tab, and the one screen that is purely a reward for
/// having used the others.
class LooksScreen extends StatelessWidget {
  const LooksScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final looks = context.watch<LooksViewModel>();
    final images = context.read<ImageStore>();

    return Scaffold(
      appBar: AppBar(title: const Text('Looks')),
      body:
          looks.loading
              ? const Center(child: CircularProgressIndicator())
              : looks.isEmpty
              ? const EmptyState(
                icon: Icons.photo_library_outlined,
                headline: 'No looks saved',
                body:
                    'Score a combination in Match, then save it. Saved '
                    'looks keep their score and their rendered preview.',
              )
              : RefreshIndicator(
                onRefresh: looks.load,
                color: Accent.brass,
                backgroundColor: Ink0.card,
                child: CustomScrollView(
                  slivers: [
                    if (looks.usedTags.length > 1)
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.only(bottom: Gap.lg),
                          child: FilterRow<LookTag>(
                            options: looks.usedTags,
                            active: looks.tag,
                            labelOf: (t) => t.label,
                            onChanged: looks.setTag,
                          ),
                        ),
                      ),
                    SliverPadding(
                      padding: const EdgeInsets.symmetric(horizontal: Gap.xl),
                      sliver: SliverList.separated(
                        itemCount: looks.visible.length,
                        separatorBuilder:
                            (_, __) => const SizedBox(height: Gap.lg),
                        itemBuilder:
                            (context, index) => _LookCard(
                              look: looks.visible[index],
                              images: images,
                            ),
                      ),
                    ),
                    const SliverToBoxAdapter(child: SizedBox(height: Gap.huge)),
                  ],
                ),
              ),
    );
  }
}

class _LookCard extends StatelessWidget {
  final Look look;
  final ImageStore images;

  const _LookCard({required this.look, required this.images});

  @override
  Widget build(BuildContext context) {
    final closet = context.watch<ClosetViewModel>();
    final garments = look.itemIds
        .map(closet.byId)
        .whereType<ClothingItem>()
        .toList(growable: false);

    final preview = look.previewFileName;

    return GestureDetector(
      onTap:
          () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => LookDetailScreen(look: look)),
          ),
      onLongPress: () => _confirmDelete(context),
      child: Container(
        decoration: BoxDecoration(
          color: Ink0.card,
          borderRadius: BorderRadius.circular(Radii.card),
          border: Border.all(color: Bone.hairline),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (preview != null)
              AspectRatio(
                aspectRatio: 3 / 4,
                child: Image.file(
                  File(images.previewPathSync(preview)),
                  fit: BoxFit.cover,
                  cacheWidth: 900,
                  errorBuilder:
                      (_, __, ___) => const ColoredBox(
                        color: Ink0.sunken,
                        child: Center(
                          child: Icon(
                            Icons.broken_image_outlined,
                            color: Bone.faint,
                          ),
                        ),
                      ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.all(Gap.lg),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(look.tag.label.toUpperCase(), style: Type.tag),
                        const SizedBox(height: Gap.xs),
                        Text(
                          '${garments.length} '
                          '${garments.length == 1 ? 'garment' : 'garments'}',
                          style: Type.bodyMuted,
                        ),
                      ],
                    ),
                  ),
                  if (look.score != null)
                    ScoreRing(score: look.score!, size: 56, showVerdict: false),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            title: const Text('Delete look?'),
            content: const Text(
              'The look and its rendered preview will be removed. Your garments '
              'and their scores stay.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Keep'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                style: FilledButton.styleFrom(backgroundColor: Accent.clay),
                child: const Text('Delete'),
              ),
            ],
          ),
    );

    if (confirmed != true || !context.mounted) return;
    await context.read<LooksViewModel>().remove(look);
  }
}

/// One saved look, larger, with the garments that made it.
class LookDetailScreen extends StatelessWidget {
  final Look look;

  const LookDetailScreen({super.key, required this.look});

  @override
  Widget build(BuildContext context) {
    final images = context.read<ImageStore>();
    final closet = context.watch<ClosetViewModel>();

    final garments = look.itemIds
        .map(closet.byId)
        .whereType<ClothingItem>()
        .toList(growable: false);

    final preview = look.previewFileName;

    return Scaffold(
      appBar: AppBar(title: Text(look.tag.label)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(Gap.xl, 0, Gap.xl, Gap.huge),
        children: [
          if (preview != null)
            ClipRRect(
              borderRadius: BorderRadius.circular(Radii.card),
              child: Image.file(
                File(images.previewPathSync(preview)),
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const SizedBox.shrink(),
              ),
            )
          else
            Panel(
              child: Text(
                'This look was saved without a rendered preview.',
                style: Type.bodyMuted,
              ),
            ),

          if (look.score != null) ...[
            const SizedBox(height: Gap.xxl),
            Center(child: ScoreRing(score: look.score!, size: 132)),
          ],

          const SizedBox(height: Gap.xxl),
          SectionLabel('Garments', trailing: '${garments.length}'),
          const SizedBox(height: Gap.md),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: garments.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              crossAxisSpacing: Gap.md,
              mainAxisSpacing: Gap.md,
              childAspectRatio: 0.78,
            ),
            itemBuilder:
                (context, index) =>
                    GarmentTile(item: garments[index], images: images),
          ),

          if (garments.length < look.itemIds.length) ...[
            const SizedBox(height: Gap.lg),
            Text(
              '${look.itemIds.length - garments.length} garment(s) from this '
              'look have since been removed from your closet.',
              style: Type.small,
            ),
          ],
        ],
      ),
    );
  }
}
