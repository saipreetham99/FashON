import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/image_store.dart';
import '../../models/clothing_item.dart';
import '../../models/outfit.dart';
import '../../models/pair_score.dart';
import '../../services/api_key_service.dart';
import '../../theme/app_theme.dart';
import '../../viewmodels/closet_viewmodel.dart';
import '../../viewmodels/looks_viewmodel.dart';
import '../../viewmodels/match_viewmodel.dart';
import '../settings/settings_screen.dart';
import '../widgets/common.dart';
import '../widgets/garment_tile.dart';
import '../widgets/score_ring.dart';

/// The working surface: pick garments, then either rate them or fill a gap.
class MatchScreen extends StatelessWidget {
  const MatchScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final closet = context.watch<ClosetViewModel>();
    final match = context.watch<MatchViewModel>();
    final keys = context.watch<ApiKeyService>();
    final images = context.read<ImageStore>();

    if (closet.all.length < 2) {
      return Scaffold(
        appBar: AppBar(title: const Text('Match')),
        body: const EmptyState(
          icon: Icons.style_outlined,
          headline: 'Two garments minimum',
          body:
              'Scoring compares one garment against another, so there needs '
              'to be a pair to judge. Add another from the Closet tab.',
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Match'),
        actions: [
          if (match.selected.isNotEmpty)
            TextButton(
              onPressed: match.clearSelection,
              child: const Text('Clear'),
            ),
          const SizedBox(width: Gap.sm),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: Gap.huge * 2),
        children: [
          if (!keys.hasKey)
            Padding(
              padding: const EdgeInsets.fromLTRB(Gap.xl, 0, Gap.xl, Gap.lg),
              child: ErrorNotice(
                message: 'Scoring needs your own Gemini API key.',
                actionLabel: 'Add a key',
                onAction:
                    () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const SettingsScreen()),
                    ),
              ),
            ),

          const Padding(
            padding: EdgeInsets.symmetric(horizontal: Gap.xl),
            child: _ModeToggle(),
          ),
          const SizedBox(height: Gap.xl),

          // Selection strip
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Gap.xl),
            child: SectionLabel(
              'Chosen',
              trailing:
                  match.selected.isEmpty
                      ? 'tap below to pick'
                      : '${match.selected.length}',
            ),
          ),
          const SizedBox(height: Gap.md),
          _SelectionStrip(match: match, images: images),

          if (match.mode == MatchMode.complete) ...[
            const SizedBox(height: Gap.xl),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: Gap.xl),
              child: SectionLabel('Looking for'),
            ),
            const SizedBox(height: Gap.md),
            FilterRow<GarmentCategory>(
              options: closet.categoriesWithChoice
                  .where((c) => !match.selected.containsKey(c))
                  .toList(growable: false),
              active: match.gap,
              labelOf: (c) => c.label,
              allLabel: null,
              onChanged: match.setGap,
            ),
          ],

          const SizedBox(height: Gap.xl),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Gap.xl),
            child: _ActionBar(match: match, hasKey: keys.hasKey),
          ),

          if (match.error != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(Gap.xl, Gap.lg, Gap.xl, 0),
              child: ErrorNotice(
                message: match.error!,
                actionLabel: match.errorIsAuth ? 'Open Settings' : null,
                onAction:
                    match.errorIsAuth
                        ? () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const SettingsScreen(),
                          ),
                        )
                        : null,
                onDismiss: match.clearError,
              ),
            ),

          if (match.status == MatchStatus.scoring)
            Padding(
              padding: const EdgeInsets.fromLTRB(Gap.xl, Gap.lg, Gap.xl, 0),
              child: ScoringProgress(
                done: match.done,
                total: match.total,
                noun: match.mode == MatchMode.rate ? 'pairs' : 'candidates',
                onCancel: match.cancel,
              ),
            ),

          if (match.mode == MatchMode.rate && match.ownPairs.isNotEmpty)
            _RateResults(match: match, images: images),

          if (match.mode == MatchMode.complete && match.ranked.isNotEmpty)
            _RankedResults(match: match, images: images),

          const SizedBox(height: Gap.xxl),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Gap.xl),
            child: SectionLabel('Your closet'),
          ),
          const SizedBox(height: Gap.md),
          _PickerGrid(closet: closet, match: match, images: images),
        ],
      ),
    );
  }
}

/// Rate what you picked, or find what is missing. Two verbs, one selection.
class _ModeToggle extends StatelessWidget {
  const _ModeToggle();

  @override
  Widget build(BuildContext context) {
    final match = context.watch<MatchViewModel>();

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Ink0.sunken,
        borderRadius: BorderRadius.circular(Radii.pill),
        border: Border.all(color: Bone.hairline),
      ),
      child: Row(
        children: [
          _tab(context, 'Rate my pick', MatchMode.rate, match.mode),
          _tab(context, 'Find a piece', MatchMode.complete, match.mode),
        ],
      ),
    );
  }

  Widget _tab(
    BuildContext context,
    String label,
    MatchMode mode,
    MatchMode active,
  ) {
    final isActive = mode == active;
    return Expanded(
      child: GestureDetector(
        onTap: () => context.read<MatchViewModel>().setMode(mode),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(vertical: Gap.md),
          decoration: BoxDecoration(
            color: isActive ? Accent.brass : Colors.transparent,
            borderRadius: BorderRadius.circular(Radii.pill),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
              color: isActive ? Ink0.sunken : Bone.muted,
            ),
          ),
        ),
      ),
    );
  }
}

class _SelectionStrip extends StatelessWidget {
  final MatchViewModel match;
  final ImageStore images;

  const _SelectionStrip({required this.match, required this.images});

  @override
  Widget build(BuildContext context) {
    if (match.selected.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: Gap.xl),
        child: Panel(
          padding: const EdgeInsets.symmetric(vertical: Gap.xl),
          child: Center(
            child: Text('Nothing chosen yet', style: Type.bodyMuted),
          ),
        ),
      );
    }

    return SizedBox(
      height: 104,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: Gap.xl),
        children: [
          for (final item in match.selectedItems)
            Padding(
              padding: const EdgeInsets.only(right: Gap.md),
              child: SizedBox(
                width: 82,
                child: GarmentTile(
                  item: item,
                  images: images,
                  selected: true,
                  onTap: () => match.toggle(item),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ActionBar extends StatelessWidget {
  final MatchViewModel match;
  final bool hasKey;

  const _ActionBar({required this.match, required this.hasKey});

  @override
  Widget build(BuildContext context) {
    final isRate = match.mode == MatchMode.rate;
    final enabled =
        hasKey &&
        (isRate ? match.canRate : match.canComplete) &&
        match.status != MatchStatus.scoring;

    final hint = switch ((isRate, match.selected.length, match.gap)) {
      (true, 0, _) => 'Pick two garments to rate them together.',
      (true, 1, _) => 'Pick one more garment.',
      (false, 0, _) => 'Pick what you already have.',
      (false, _, null) => 'Choose the category to search.',
      _ => null,
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FilledButton(
          onPressed:
              enabled ? (isRate ? match.rateSelection : match.findBest) : null,
          child: Text(isRate ? 'Score this pairing' : 'Find the best match'),
        ),
        if (hint != null)
          Padding(
            padding: const EdgeInsets.only(top: Gap.sm),
            child: Text(hint, style: Type.small),
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Rate results
// ---------------------------------------------------------------------------

class _RateResults extends StatelessWidget {
  final MatchViewModel match;
  final ImageStore images;

  const _RateResults({required this.match, required this.images});

  @override
  Widget build(BuildContext context) {
    final overall = match.selectionScore;

    return Padding(
      padding: const EdgeInsets.fromLTRB(Gap.xl, Gap.xxl, Gap.xl, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (overall != null)
            Center(
              child: Column(
                children: [
                  ScoreRing(score: overall, size: 132),
                  const SizedBox(height: Gap.md),
                  Text(
                    match.ownPairs.length == 1
                        ? 'One pairing judged'
                        : 'Average of ${match.ownPairs.length} pairings',
                    style: Type.small,
                  ),
                ],
              ),
            ),

          if (match.upgrades.isNotEmpty) ...[
            const SizedBox(height: Gap.xxl),
            const SectionLabel('Already in your closet'),
            const SizedBox(height: Gap.md),
            for (final upgrade in match.upgrades)
              _UpgradeCard(upgrade: upgrade, images: images, match: match),
          ],

          const SizedBox(height: Gap.xxl),
          const SectionLabel('Verdict'),
          const SizedBox(height: Gap.lg),
          for (final pair in match.ownPairs)
            _VerdictCard(pair: pair, match: match, images: images),

          const SizedBox(height: Gap.xl),
          _SaveRow(match: match),
        ],
      ),
    );
  }
}

/// Suggests a swap the cache already knows is better.
///
/// This is the payoff of caching everything: the app can tell you a different
/// garment scores higher without spending anything, and it gets smarter the
/// longer you use it.
class _UpgradeCard extends StatelessWidget {
  final Upgrade upgrade;
  final ImageStore images;
  final MatchViewModel match;

  const _UpgradeCard({
    required this.upgrade,
    required this.images,
    required this.match,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: Gap.md),
      child: Panel(
        borderColor: const Color(0x557FA9A0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.trending_up,
                  size: 16,
                  color: Accent.eucalyptus,
                ),
                const SizedBox(width: Gap.sm),
                Text(
                  '+${upgrade.gain.toStringAsFixed(1)} available',
                  style: Type.tag.copyWith(color: Accent.eucalyptus),
                ),
              ],
            ),
            const SizedBox(height: Gap.lg),
            Row(
              children: [
                _thumb(upgrade.replace, dimmed: true),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: Gap.md),
                  child: Icon(Icons.arrow_forward, size: 16, color: Bone.muted),
                ),
                _thumb(upgrade.with_, dimmed: false),
                const SizedBox(width: Gap.lg),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${upgrade.currentScore.toStringAsFixed(1)} → '
                        '${upgrade.betterScore.toStringAsFixed(1)}',
                        style: Type.numeralSmall.copyWith(
                          color: Accent.eucalyptus,
                          fontSize: 17,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Swap the ${upgrade.replace.category.singular}',
                        style: Type.small,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: Gap.lg),
            OutlinedButton(
              onPressed: () => match.applyUpgrade(upgrade),
              child: const Text('Use it instead'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _thumb(ClothingItem item, {required bool dimmed}) {
    final tile = SizedBox(
      width: 48,
      height: 48,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(Radii.tile * 0.55),
        child: GarmentImage(item: item, images: images),
      ),
    );
    if (!dimmed) return tile;
    return Opacity(opacity: 0.45, child: tile);
  }
}

class _VerdictCard extends StatelessWidget {
  final PairScore pair;
  final MatchViewModel match;
  final ImageStore images;

  const _VerdictCard({
    required this.pair,
    required this.match,
    required this.images,
  });

  @override
  Widget build(BuildContext context) {
    final closet = context.read<ClosetViewModel>();
    final a = closet.byId(pair.itemA);
    final b = closet.byId(pair.itemB);

    return Padding(
      padding: const EdgeInsets.only(bottom: Gap.lg),
      child: Panel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (a != null && b != null)
                  Expanded(
                    child: SwatchPair(a: a, b: b, images: images, height: 76),
                  ),
                ScoreRing(score: pair.score, size: 76, showVerdict: false),
              ],
            ),
            const SizedBox(height: Gap.xl),
            AdviceList(
              title: 'Earning points',
              entries: pair.boosting,
              color: Accent.eucalyptus,
              icon: Icons.add_circle_outline,
            ),
            if (pair.boosting.isNotEmpty && pair.costing.isNotEmpty)
              const SizedBox(height: Gap.lg),
            AdviceList(
              title: 'Costing points',
              entries: pair.costing,
              color: Accent.clay,
              icon: Icons.remove_circle_outline,
            ),
            if (pair.improve.isNotEmpty) ...[
              const SizedBox(height: Gap.lg),
              AdviceList(
                title: 'To improve',
                entries: pair.improve,
                color: Accent.brass,
                icon: Icons.auto_fix_high_outlined,
              ),
            ],
            if (pair.shoes.isNotEmpty) ...[
              const SizedBox(height: Gap.lg),
              AdviceList(
                title: 'Shoes',
                entries: pair.shoes,
                color: Bone.muted,
                icon: Icons.hiking_outlined,
              ),
            ],
            if (pair.accessories.isNotEmpty) ...[
              const SizedBox(height: Gap.lg),
              AdviceList(
                title: 'Accessories',
                entries: pair.accessories,
                color: Bone.muted,
                icon: Icons.watch_outlined,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Ranked results
// ---------------------------------------------------------------------------

class _RankedResults extends StatelessWidget {
  final MatchViewModel match;
  final ImageStore images;

  const _RankedResults({required this.match, required this.images});

  @override
  Widget build(BuildContext context) {
    final closet = context.read<ClosetViewModel>();
    final ranked = match.ranked;

    return Padding(
      padding: const EdgeInsets.fromLTRB(Gap.xl, Gap.xxl, Gap.xl, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionLabel('Best match', trailing: '${ranked.length} scored'),
          const SizedBox(height: Gap.lg),
          for (var i = 0; i < ranked.length; i++)
            _CandidateRow(
              rank: i + 1,
              candidate: ranked[i],
              item: closet.byId(ranked[i].itemId),
              images: images,
              onAccept: () => match.acceptCandidate(ranked[i].itemId),
            ),
        ],
      ),
    );
  }
}

class _CandidateRow extends StatelessWidget {
  final int rank;
  final ScoredCandidate candidate;
  final ClothingItem? item;
  final ImageStore images;
  final VoidCallback onAccept;

  const _CandidateRow({
    required this.rank,
    required this.candidate,
    required this.item,
    required this.images,
    required this.onAccept,
  });

  @override
  Widget build(BuildContext context) {
    final garment = item;
    if (garment == null) return const SizedBox.shrink();

    final isTop = rank == 1;

    return Padding(
      padding: const EdgeInsets.only(bottom: Gap.md),
      child: Panel(
        borderColor: isTop ? Accent.brass : Bone.hairline,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                SizedBox(
                  width: 64,
                  height: 64,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(Radii.tile * 0.6),
                    child: GarmentImage(item: garment, images: images),
                  ),
                ),
                const SizedBox(width: Gap.lg),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (isTop)
                        Text(
                          'BEST',
                          style: Type.tag.copyWith(color: Accent.brass),
                        )
                      else
                        Text('#$rank', style: Type.tag),
                      const SizedBox(height: Gap.xs),
                      Text(
                        garment.label?.isNotEmpty == true
                            ? garment.label!
                            : garment.category.label,
                        style: Type.body,
                      ),
                      if (candidate.pairs.length > 1)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            'across ${candidate.pairs.length} pairings',
                            style: Type.small,
                          ),
                        ),
                    ],
                  ),
                ),
                ScoreRing(
                  score: candidate.averageScore,
                  size: 62,
                  showVerdict: false,
                ),
              ],
            ),
            if (isTop) ...[
              if (candidate.allImprove.isNotEmpty) ...[
                const SizedBox(height: Gap.xl),
                AdviceList(
                  title: 'To improve',
                  entries: candidate.allImprove.take(3).toList(),
                  color: Accent.brass,
                  icon: Icons.auto_fix_high_outlined,
                ),
              ],
              if (candidate.allShoes.isNotEmpty) ...[
                const SizedBox(height: Gap.lg),
                AdviceList(
                  title: 'Shoes',
                  entries: candidate.allShoes.take(3).toList(),
                  color: Bone.muted,
                  icon: Icons.hiking_outlined,
                ),
              ],
              if (candidate.allAccessories.isNotEmpty) ...[
                const SizedBox(height: Gap.lg),
                AdviceList(
                  title: 'Accessories',
                  entries: candidate.allAccessories.take(3).toList(),
                  color: Bone.muted,
                  icon: Icons.watch_outlined,
                ),
              ],
              const SizedBox(height: Gap.lg),
              OutlinedButton(
                onPressed: onAccept,
                child: const Text('Add to selection'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Preview and save
// ---------------------------------------------------------------------------

class _SaveRow extends StatelessWidget {
  final MatchViewModel match;

  const _SaveRow({required this.match});

  @override
  Widget build(BuildContext context) {
    final preview = match.preview;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (preview != null) ...[
          const SectionLabel('Worn together'),
          const SizedBox(height: Gap.md),
          ClipRRect(
            borderRadius: BorderRadius.circular(Radii.card),
            child: Image.memory(preview, fit: BoxFit.cover),
          ),
          const SizedBox(height: Gap.lg),
        ],
        if (match.status == MatchStatus.rendering)
          const Panel(
            child: Row(
              children: [
                SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                SizedBox(width: Gap.lg),
                Expanded(
                  child: Text(
                    'Rendering the outfit. This takes a moment.',
                    style: Type.bodyMuted,
                  ),
                ),
              ],
            ),
          )
        else
          OutlinedButton.icon(
            onPressed: match.canRender ? match.renderPreview : null,
            icon: const Icon(Icons.auto_awesome_outlined, size: 18),
            label: Text(preview == null ? 'See it worn' : 'Render again'),
          ),
        const SizedBox(height: Gap.md),
        FilledButton(
          onPressed:
              match.canSave ? () => _pickTagAndSave(context, match) : null,
          child: const Text('Save this look'),
        ),
      ],
    );
  }

  Future<void> _pickTagAndSave(
    BuildContext context,
    MatchViewModel match,
  ) async {
    final tag = await showModalBottomSheet<LookTag>(
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
                  const Text('When would you wear it?', style: Type.title),
                  const SizedBox(height: Gap.xl),
                  for (final option in LookTag.values)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(option.label, style: Type.body),
                      trailing: const Icon(
                        Icons.chevron_right,
                        color: Bone.faint,
                        size: 20,
                      ),
                      onTap: () => Navigator.pop(context, option),
                    ),
                ],
              ),
            ),
          ),
    );

    if (tag == null || !context.mounted) return;

    final saved = await match.saveLook(tag);
    if (!context.mounted) return;

    if (saved) {
      await context.read<LooksViewModel>().load();
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Saved to Looks.')));
    }
  }
}

class _PickerGrid extends StatelessWidget {
  final ClosetViewModel closet;
  final MatchViewModel match;
  final ImageStore images;

  const _PickerGrid({
    required this.closet,
    required this.match,
    required this.images,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final entry in closet.grouped.entries) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(Gap.xl, Gap.lg, Gap.xl, Gap.sm),
            child: Text(entry.key.label.toUpperCase(), style: Type.tag),
          ),
          SizedBox(
            height: 96,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: Gap.xl),
              children: [
                for (final item in entry.value)
                  Padding(
                    padding: const EdgeInsets.only(right: Gap.md),
                    child: SizedBox(
                      width: 76,
                      child: GarmentTile(
                        item: item,
                        images: images,
                        selected: match.isSelected(item),
                        onTap: () => match.toggle(item),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}
