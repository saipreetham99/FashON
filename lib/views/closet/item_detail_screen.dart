import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/image_store.dart';
import '../../models/clothing_item.dart';
import '../../theme/app_theme.dart';
import '../../viewmodels/closet_viewmodel.dart';
import '../../viewmodels/combinations_viewmodel.dart';
import '../combinations/pair_detail_screen.dart';
import '../widgets/common.dart';
import '../widgets/garment_tile.dart';
import '../widgets/score_ring.dart';

/// One garment: the photo, its name, and what it already goes with.
///
/// The pairings list is cache-only, so opening a garment never costs anything.
class ItemDetailScreen extends StatefulWidget {
  final ClothingItem item;

  const ItemDetailScreen({super.key, required this.item});

  @override
  State<ItemDetailScreen> createState() => _ItemDetailScreenState();
}

class _ItemDetailScreenState extends State<ItemDetailScreen> {
  List<Combination>? _pairings;

  @override
  void initState() {
    super.initState();
    _loadPairings();
  }

  Future<void> _loadPairings() async {
    final combos = await context.read<CombinationsViewModel>().forItem(
      widget.item.id,
    );
    if (!mounted) return;
    setState(() => _pairings = combos);
  }

  @override
  Widget build(BuildContext context) {
    final images = context.read<ImageStore>();
    final item =
        context.watch<ClosetViewModel>().byId(widget.item.id) ?? widget.item;

    final pairings = _pairings;

    return Scaffold(
      appBar: AppBar(
        title: Text(item.category.label),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            tooltip: 'Rename',
            onPressed: () => _rename(context, item),
          ),
          const SizedBox(width: Gap.sm),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(Gap.xl, 0, Gap.xl, Gap.huge),
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(Radii.card),
            child: AspectRatio(
              aspectRatio: 1,
              child: GarmentImage(
                item: item,
                images: images,
                fit: BoxFit.cover,
              ),
            ),
          ),
          const SizedBox(height: Gap.lg),
          Text(
            item.label?.isNotEmpty == true ? item.label! : item.category.label,
            style: Type.title,
          ),
          const SizedBox(height: Gap.xs),
          Text('Added ${_relative(item.createdAt)}', style: Type.small),
          const SizedBox(height: Gap.xxl),
          SectionLabel(
            'Goes with',
            trailing: pairings == null ? null : '${pairings.length}',
          ),
          const SizedBox(height: Gap.lg),
          if (pairings == null)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(Gap.xl),
                child: CircularProgressIndicator(),
              ),
            )
          else if (pairings.isEmpty)
            Panel(
              child: Text(
                'Nothing scored yet. Pick this in Match alongside something '
                'else and its pairings will collect here.',
                style: Type.bodyMuted,
              ),
            )
          else
            for (final combo in pairings)
              _PairingRow(
                combination: combo,
                anchorId: item.id,
                images: images,
              ),
        ],
      ),
    );
  }

  Future<void> _rename(BuildContext context, ClothingItem item) async {
    final controller = TextEditingController(text: item.label ?? '');

    final label = await showDialog<String>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            title: const Text('Name this garment'),
            content: TextField(
              controller: controller,
              autofocus: true,
              style: Type.body,
              decoration: const InputDecoration(hintText: 'the linen one'),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, controller.text),
                child: const Text('Save'),
              ),
            ],
          ),
    );

    if (label == null || !context.mounted) return;
    await context.read<ClosetViewModel>().rename(item, label);
  }

  static String _relative(DateTime when) {
    final days = DateTime.now().difference(when).inDays;
    if (days == 0) return 'today';
    if (days == 1) return 'yesterday';
    if (days < 30) return '$days days ago';
    final months = (days / 30).floor();
    return months == 1 ? 'a month ago' : '$months months ago';
  }
}

class _PairingRow extends StatelessWidget {
  final Combination combination;
  final String anchorId;
  final ImageStore images;

  const _PairingRow({
    required this.combination,
    required this.anchorId,
    required this.images,
  });

  @override
  Widget build(BuildContext context) {
    // Show the *other* garment: the user knows which one they opened.
    final other =
        combination.score.itemA == anchorId ? combination.b : combination.a;

    return Padding(
      padding: const EdgeInsets.only(bottom: Gap.md),
      child: GestureDetector(
        onTap:
            () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => PairDetailScreen(combination: combination),
              ),
            ),
        child: Panel(
          padding: const EdgeInsets.all(Gap.md),
          child: Row(
            children: [
              SizedBox(
                width: 56,
                height: 56,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(Radii.tile * 0.6),
                  child: GarmentImage(item: other, images: images),
                ),
              ),
              const SizedBox(width: Gap.lg),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      other.label?.isNotEmpty == true
                          ? other.label!
                          : other.category.label,
                      style: Type.body,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      scoreVerdict(combination.score.score),
                      style: Type.small.copyWith(
                        color: scoreColor(combination.score.score),
                      ),
                    ),
                  ],
                ),
              ),
              ScorePill(score: combination.score.score),
              const SizedBox(width: Gap.sm),
              const Icon(Icons.chevron_right, color: Bone.faint, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}
