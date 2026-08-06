import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/app_settings.dart';
import '../../services/backfill_service.dart';
import '../../theme/app_theme.dart';
import '../../viewmodels/closet_viewmodel.dart';
import '../settings/settings_screen.dart';
import 'common.dart';

/// Shows what the background scorer is doing, and lets the user stop it.
///
/// Visible whenever there is outstanding work, not only while running. Spending
/// someone's API quota in the background is only acceptable if they can always
/// see it happening and stop it in one tap.
class BackfillBanner extends StatelessWidget {
  const BackfillBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final backfill = context.watch<BackfillService>();
    final settings = context.watch<AppSettings>();
    final closet = context.read<ClosetViewModel>();

    if (!backfill.hasWork && backfill.message == null) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(Gap.xl, 0, Gap.xl, Gap.lg),
      child: switch (backfill.status) {
        BackfillStatus.running => _Running(backfill: backfill),
        BackfillStatus.throttled => _Stopped(
          icon: Icons.timer_outlined,
          color: Accent.amber,
          message: backfill.message ?? 'Paused — your key hit its rate limit.',
          actionLabel: 'Resume',
          onAction: () => backfill.start(closet.all),
        ),
        BackfillStatus.blocked => _Stopped(
          icon: Icons.key_off_outlined,
          color: Accent.clay,
          message: backfill.message ?? 'Scoring needs an API key.',
          actionLabel: 'Open Settings',
          onAction:
              () => Navigator.of(
                context,
              ).push(MaterialPageRoute(builder: (_) => const SettingsScreen())),
        ),
        BackfillStatus.paused => _Stopped(
          icon: Icons.pause_circle_outline,
          color: Bone.muted,
          message: backfill.message ?? 'Paused.',
          actionLabel: 'Resume',
          onAction: () => backfill.start(closet.all),
        ),
        BackfillStatus.idle => _Idle(
          backfill: backfill,
          autoOn: settings.backfillEnabled,
        ),
      },
    );
  }
}

class _Running extends StatelessWidget {
  final BackfillService backfill;

  const _Running({required this.backfill});

  @override
  Widget build(BuildContext context) {
    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: Gap.md),
              Expanded(
                child: Text('Learning your closet', style: Type.section),
              ),
              Text(
                '${backfill.done} / ${backfill.total}',
                style: Type.numeralSmall.copyWith(color: Accent.brass),
              ),
            ],
          ),
          const SizedBox(height: Gap.md),
          ClipRRect(
            borderRadius: const BorderRadius.all(Radius.circular(Radii.pill)),
            child: LinearProgressIndicator(
              value: backfill.progress,
              minHeight: 4,
            ),
          ),
          const SizedBox(height: Gap.sm),
          Text(
            'Scoring pairings you have not asked about yet, so suggestions can '
            'spot a better option later.',
            style: Type.small,
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: backfill.pause,
              child: const Text('Stop'),
            ),
          ),
        ],
      ),
    );
  }
}

class _Stopped extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String message;
  final String actionLabel;
  final VoidCallback onAction;

  const _Stopped({
    required this.icon,
    required this.color,
    required this.message,
    required this.actionLabel,
    required this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Panel(
      borderColor: color.withValues(alpha: 0.4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(icon, size: 18, color: color),
          ),
          const SizedBox(width: Gap.md),
          Expanded(child: Text(message, style: Type.body)),
          TextButton(onPressed: onAction, child: Text(actionLabel)),
        ],
      ),
    );
  }
}

class _Idle extends StatelessWidget {
  final BackfillService backfill;
  final bool autoOn;

  const _Idle({required this.backfill, required this.autoOn});

  @override
  Widget build(BuildContext context) {
    final closet = context.read<ClosetViewModel>();
    final pending = backfill.pending;

    if (pending == 0) {
      final message = backfill.message;
      if (message == null) return const SizedBox.shrink();
      return Panel(
        child: Row(
          children: [
            const Icon(Icons.check, size: 18, color: Accent.eucalyptus),
            const SizedBox(width: Gap.md),
            Expanded(child: Text(message, style: Type.small)),
            IconButton(
              icon: const Icon(Icons.close, size: 16, color: Bone.muted),
              onPressed: backfill.clearMessage,
              visualDensity: VisualDensity.compact,
            ),
          ],
        ),
      );
    }

    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                '$pending',
                style: Type.numeralSmall.copyWith(
                  fontSize: 22,
                  color: Accent.brass,
                ),
              ),
              const SizedBox(width: Gap.sm),
              Expanded(
                child: Text(
                  pending == 1
                      ? 'pairing not judged yet'
                      : 'pairings not judged yet',
                  style: Type.body,
                ),
              ),
            ],
          ),
          const SizedBox(height: Gap.sm),
          Text(
            autoOn
                ? 'These get scored as you add garments. Suggestions improve as '
                    'the number falls.'
                : 'Scoring these lets the app suggest a better option without '
                    'being asked. Each one spends against your key.',
            style: Type.small,
          ),
          const SizedBox(height: Gap.md),
          OutlinedButton(
            onPressed: () => backfill.start(closet.all),
            child: Text(
              pending > AppSettings.defaultCap
                  ? 'Score the next ${AppSettings.defaultCap}'
                  : 'Score them now',
            ),
          ),
        ],
      ),
    );
  }
}
