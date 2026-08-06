import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

/// The signature element: a score drawn as a swept arc rather than a bar.
///
/// A bar reads as "progress toward finishing something", which is wrong — a
/// score is a judgement, not a task. The arc opens at the bottom like the gap
/// in a tape measure looped around itself, sweeps clockwise, and carries the
/// verdict colour so the number and the hue say the same thing twice.
class ScoreRing extends StatelessWidget {
  final double score;
  final double size;

  /// Shows the one-word verdict under the numeral. Off in dense grids.
  final bool showVerdict;

  const ScoreRing({
    super.key,
    required this.score,
    this.size = 96,
    this.showVerdict = true,
  });

  @override
  Widget build(BuildContext context) {
    final color = scoreColor(score);

    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _RingPainter(score: score, color: color),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                score.toStringAsFixed(1),
                style: Type.numeral.copyWith(
                  fontSize: size * 0.30,
                  color: Bone.full,
                ),
              ),
              if (showVerdict && size >= 84) ...[
                const SizedBox(height: Gap.xs),
                Text(
                  scoreVerdict(score).toUpperCase(),
                  style: Type.tag.copyWith(
                    color: color,
                    fontSize: size * 0.085,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  final double score;
  final Color color;

  /// Sweep starts at the bottom-left and runs clockwise, leaving a gap at the
  /// bottom. 240 degrees of travel: enough to read as a gauge, short enough
  /// that the opening is obviously deliberate.
  static const double _startAngle = math.pi * 0.75;
  static const double _sweepRange = math.pi * 1.5;

  const _RingPainter({required this.score, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = size.width * 0.055;
    final rect = Rect.fromLTWH(
      stroke / 2,
      stroke / 2,
      size.width - stroke,
      size.height - stroke,
    );

    final track =
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke
          ..strokeCap = StrokeCap.round
          ..color = Bone.hairline;

    canvas.drawArc(rect, _startAngle, _sweepRange, false, track);

    final fraction = (score / 10).clamp(0.0, 1.0);
    if (fraction <= 0) return;

    // Sweep gradient so the arc gains weight as it climbs, rather than sitting
    // flat. Rotated to line up with the arc's own start angle.
    final shader = SweepGradient(
      startAngle: _startAngle,
      endAngle: _startAngle + _sweepRange,
      colors: [color.withValues(alpha: 0.35), color],
      transform: GradientRotation(_startAngle),
    ).createShader(rect);

    final sweep =
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke
          ..strokeCap = StrokeCap.round
          ..shader = shader;

    canvas.drawArc(rect, _startAngle, _sweepRange * fraction, false, sweep);
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.score != score || old.color != color;
}

/// Compact score chip for grids and list rows, where a ring would be too heavy.
class ScorePill extends StatelessWidget {
  final double score;

  const ScorePill({super.key, required this.score});

  @override
  Widget build(BuildContext context) {
    final color = scoreColor(score);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Gap.sm, vertical: 3),
      decoration: BoxDecoration(
        color: Ink0.sunken.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(Radii.pill),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Text(
        score.toStringAsFixed(1),
        style: Type.numeralSmall.copyWith(color: color),
      ),
    );
  }
}
