import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

/// Small uppercase label that opens a section, like the print on a garment tag.
class SectionLabel extends StatelessWidget {
  final String text;
  final String? trailing;

  const SectionLabel(this.text, {super.key, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(text.toUpperCase(), style: Type.tag),
        if (trailing != null)
          Text(trailing!, style: Type.tag.copyWith(color: Bone.faint)),
      ],
    );
  }
}

/// A hairline-bordered panel. The default container for grouped content.
class Panel extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? background;
  final Color? borderColor;

  const Panel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(Gap.lg),
    this.background,
    this.borderColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: background ?? Ink0.card,
        borderRadius: BorderRadius.circular(Radii.card),
        border: Border.all(color: borderColor ?? Bone.hairline),
      ),
      child: child,
    );
  }
}

/// An empty screen is an invitation, so this always carries the next action
/// rather than only stating that nothing is here.
class EmptyState extends StatelessWidget {
  final IconData icon;
  final String headline;
  final String body;
  final String? actionLabel;
  final VoidCallback? onAction;

  const EmptyState({
    super.key,
    required this.icon,
    required this.headline,
    required this.body,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: Gap.xxl),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: Ink0.card,
                shape: BoxShape.circle,
                border: Border.all(color: Bone.hairline),
              ),
              child: Icon(icon, color: Accent.brass, size: 26),
            ),
            const SizedBox(height: Gap.xl),
            Text(headline, style: Type.title, textAlign: TextAlign.center),
            const SizedBox(height: Gap.sm),
            Text(body, style: Type.bodyMuted, textAlign: TextAlign.center),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: Gap.xl),
              SizedBox(
                width: 220,
                child: FilledButton(
                  onPressed: onAction,
                  child: Text(actionLabel!),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// A list of short advice lines with a leading marker.
///
/// The marker colour carries the meaning — eucalyptus for what works, clay for
/// what does not — so the reader can skim one column and know the register
/// before reading a word.
class AdviceList extends StatelessWidget {
  final String title;
  final List<String> entries;
  final Color color;
  final IconData icon;

  const AdviceList({
    super.key,
    required this.title,
    required this.entries,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: Gap.sm),
            Text(title.toUpperCase(), style: Type.tag.copyWith(color: color)),
          ],
        ),
        const SizedBox(height: Gap.md),
        for (final entry in entries)
          Padding(
            padding: const EdgeInsets.only(bottom: Gap.sm, left: 22),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  margin: const EdgeInsets.only(top: 7, right: Gap.md),
                  width: 4,
                  height: 4,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                  ),
                ),
                Expanded(child: Text(entry, style: Type.body)),
              ],
            ),
          ),
      ],
    );
  }
}

/// Horizontally scrolling single-choice filter row.
class FilterRow<T> extends StatelessWidget {
  final List<T> options;
  final T? active;
  final String Function(T) labelOf;
  final ValueChanged<T?> onChanged;

  /// Label for the "no filter" chip. Omit to hide it.
  final String? allLabel;

  const FilterRow({
    super.key,
    required this.options,
    required this.active,
    required this.labelOf,
    required this.onChanged,
    this.allLabel = 'All',
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: Gap.xl),
      child: Row(
        children: [
          if (allLabel != null)
            _chip(allLabel!, active == null, () => onChanged(null)),
          for (final option in options)
            _chip(labelOf(option), active == option, () => onChanged(option)),
        ],
      ),
    );
  }

  Widget _chip(String label, bool isActive, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.only(right: Gap.sm),
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          padding: const EdgeInsets.symmetric(
            horizontal: Gap.lg,
            vertical: Gap.md,
          ),
          decoration: BoxDecoration(
            color: isActive ? Accent.brass : Ink0.card,
            borderRadius: BorderRadius.circular(Radii.pill),
            border: Border.all(color: isActive ? Accent.brass : Bone.hairline),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.2,
              color: isActive ? Ink0.sunken : Bone.muted,
            ),
          ),
        ),
      ),
    );
  }
}

/// Inline failure notice.
///
/// Errors here explain what happened and what to do about it, and never
/// apologise — an apology takes the reader's attention without helping them.
class ErrorNotice extends StatelessWidget {
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;
  final VoidCallback? onDismiss;

  const ErrorNotice({
    super.key,
    required this.message,
    this.actionLabel,
    this.onAction,
    this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    return Panel(
      background: const Color(0x22D2766B),
      borderColor: const Color(0x55D2766B),
      padding: const EdgeInsets.fromLTRB(Gap.lg, Gap.md, Gap.sm, Gap.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 2),
            child: Icon(Icons.error_outline, size: 18, color: Accent.clay),
          ),
          const SizedBox(width: Gap.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(message, style: Type.body),
                if (actionLabel != null && onAction != null)
                  Padding(
                    padding: const EdgeInsets.only(top: Gap.xs),
                    child: TextButton(
                      onPressed: onAction,
                      style: TextButton.styleFrom(
                        padding: EdgeInsets.zero,
                        minimumSize: const Size(0, 32),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: Text(actionLabel!),
                    ),
                  ),
              ],
            ),
          ),
          if (onDismiss != null)
            IconButton(
              icon: const Icon(Icons.close, size: 18, color: Bone.muted),
              onPressed: onDismiss,
              visualDensity: VisualDensity.compact,
            ),
        ],
      ),
    );
  }
}

/// Determinate progress with a count, used while scoring runs.
class ScoringProgress extends StatelessWidget {
  final int done;
  final int total;
  final String noun;
  final VoidCallback? onCancel;

  const ScoringProgress({
    super.key,
    required this.done,
    required this.total,
    required this.noun,
    this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Scoring $noun', style: Type.section),
              Text(
                '$done of $total',
                style: Type.numeralSmall.copyWith(color: Accent.brass),
              ),
            ],
          ),
          const SizedBox(height: Gap.md),
          ClipRRect(
            borderRadius: BorderRadius.circular(Radii.pill),
            child: LinearProgressIndicator(
              value: total == 0 ? null : done / total,
              minHeight: 4,
            ),
          ),
          const SizedBox(height: Gap.sm),
          Text(
            'Pairs already judged are reused, so this gets faster the more you '
            'use it.',
            style: Type.small,
          ),
          if (onCancel != null)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(onPressed: onCancel, child: const Text('Stop')),
            ),
        ],
      ),
    );
  }
}
