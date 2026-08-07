import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/image_store.dart';
import '../../models/clothing_item.dart';
import '../../theme/app_theme.dart';
import '../../viewmodels/closet_viewmodel.dart';
import '../profile/profile_screen.dart';
import '../settings/settings_screen.dart';
import '../widgets/common.dart';
import '../widgets/garment_tile.dart';
import 'item_detail_screen.dart';

/// Everything the user has photographed, grouped head to toe.
///
/// This is the only place garments enter the app, so it carries the primary
/// add action rather than hiding it behind a tab.
class ClosetScreen extends StatelessWidget {
  const ClosetScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final closet = context.watch<ClosetViewModel>();
    final images = context.read<ImageStore>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Closet'),
        actions: [
          IconButton(
            icon: const Icon(Icons.person_outline),
            tooltip: 'Profile',
            onPressed:
                () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const ProfileScreen()),
                ),
          ),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'Settings',
            onPressed:
                () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const SettingsScreen()),
                ),
          ),
          const SizedBox(width: Gap.sm),
        ],
      ),
      floatingActionButton:
          closet.isEmpty
              ? null
              : FloatingActionButton(
                onPressed: () => _openAddSheet(context),
                backgroundColor: Accent.brass,
                foregroundColor: Ink0.sunken,
                child: const Icon(Icons.add_a_photo_outlined),
              ),
      body: switch (closet.status) {
        ClosetStatus.loading => const Center(
          child: CircularProgressIndicator(),
        ),
        ClosetStatus.error => EmptyState(
          icon: Icons.error_outline,
          headline: 'Closet unavailable',
          body: closet.error ?? 'Something went wrong opening your closet.',
          actionLabel: 'Try again',
          onAction: closet.load,
        ),
        _ =>
          closet.isEmpty
              ? EmptyState(
                icon: Icons.checkroom_outlined,
                headline: 'Start with two garments',
                body:
                    'Photograph a top and a pair of bottoms, and FashON can '
                    'tell you how they work together.',
                actionLabel: 'Add a garment',
                onAction: () => _openAddSheet(context),
              )
              : _ClosetGrid(closet: closet, images: images),
      },
    );
  }

  static Future<void> _openAddSheet(BuildContext context) async {
    final category = await showModalBottomSheet<GarmentCategory>(
      context: context,
      builder: (_) => const _CategorySheet(),
    );
    if (category == null || !context.mounted) return;

    final source = await showModalBottomSheet<_Source>(
      context: context,
      builder: (_) => _SourceSheet(category: category),
    );
    if (source == null || !context.mounted) return;

    final closet = context.read<ClosetViewModel>();
    final item =
        source == _Source.camera
            ? await closet.addFromCamera(category)
            : await closet.addFromGallery(category);

    if (!context.mounted || item == null) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Added to ${category.label.toLowerCase()}.')),
    );
  }
}

class _ClosetGrid extends StatelessWidget {
  final ClosetViewModel closet;
  final ImageStore images;

  const _ClosetGrid({required this.closet, required this.images});

  @override
  Widget build(BuildContext context) {
    final grouped = closet.grouped;

    return RefreshIndicator(
      onRefresh: closet.load,
      color: Accent.brass,
      backgroundColor: Ink0.card,
      child: CustomScrollView(
        slivers: [
          if (closet.error != null)
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(Gap.xl, 0, Gap.xl, Gap.lg),
              sliver: SliverToBoxAdapter(
                child: ErrorNotice(
                  message: closet.error!,
                  onDismiss: closet.clearError,
                ),
              ),
            ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(Gap.xl, 0, Gap.xl, Gap.md),
            sliver: SliverToBoxAdapter(
              child: Text(
                '${closet.all.length} '
                '${closet.all.length == 1 ? 'garment' : 'garments'}',
                style: Type.small,
              ),
            ),
          ),
          for (final entry in grouped.entries) ...[
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(
                Gap.xl,
                Gap.lg,
                Gap.xl,
                Gap.md,
              ),
              sliver: SliverToBoxAdapter(
                child: SectionLabel(
                  entry.key.label,
                  trailing: '${entry.value.length}',
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: Gap.xl),
              sliver: SliverGrid(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  crossAxisSpacing: Gap.md,
                  mainAxisSpacing: Gap.md,
                  childAspectRatio: 0.78,
                ),
                delegate: SliverChildBuilderDelegate(
                  childCount: entry.value.length,
                  (context, index) {
                    final item = entry.value[index];
                    return GarmentTile(
                      item: item,
                      images: images,
                      onTap:
                          () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => ItemDetailScreen(item: item),
                            ),
                          ),
                      onLongPress: () => _confirmDelete(context, item),
                    );
                  },
                ),
              ),
            ),
          ],
          const SliverToBoxAdapter(child: SizedBox(height: Gap.huge * 2)),
        ],
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context, ClothingItem item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            title: const Text('Remove garment?'),
            content: const Text(
              'Its photo and every score it appears in will be deleted. Saved '
              'looks that used it will keep their preview image.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Keep'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                style: FilledButton.styleFrom(backgroundColor: Accent.clay),
                child: const Text('Remove'),
              ),
            ],
          ),
    );

    if (confirmed != true || !context.mounted) return;
    await context.read<ClosetViewModel>().remove(item);
  }
}

// ---------------------------------------------------------------------------
// Add flow
// ---------------------------------------------------------------------------

/// GarmentCategory first, then source. Two small decisions beat one crowded sheet, and
/// knowing the category up front means the photo is filed correctly even if the
/// user abandons the flow halfway and comes back.
class _CategorySheet extends StatelessWidget {
  const _CategorySheet();

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(Gap.xl, Gap.xl, Gap.xl, Gap.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('What is it?', style: Type.title),
            const SizedBox(height: Gap.xl),
            for (final category in GarmentCategory.values)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(category.label, style: Type.body),
                trailing: const Icon(
                  Icons.chevron_right,
                  color: Bone.faint,
                  size: 20,
                ),
                onTap: () => Navigator.pop(context, category),
              ),
          ],
        ),
      ),
    );
  }
}

enum _Source { camera, gallery }

class _SourceSheet extends StatelessWidget {
  final GarmentCategory category;

  const _SourceSheet({required this.category});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(Gap.xl, Gap.xl, Gap.xl, Gap.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Add ${category.singular}', style: Type.title),
            const SizedBox(height: Gap.sm),
            const Text(
              'Lay it flat in even light, filling most of the frame. Scores are '
              'only as good as the photo.',
              style: Type.bodyMuted,
            ),
            const SizedBox(height: Gap.xl),
            FilledButton.icon(
              onPressed: () => Navigator.pop(context, _Source.camera),
              icon: const Icon(Icons.photo_camera_outlined, size: 20),
              label: const Text('Take a photo'),
            ),
            const SizedBox(height: Gap.md),
            OutlinedButton.icon(
              onPressed: () => Navigator.pop(context, _Source.gallery),
              icon: const Icon(Icons.photo_library_outlined, size: 20),
              label: const Text('Choose from photos'),
            ),
          ],
        ),
      ),
    );
  }
}
