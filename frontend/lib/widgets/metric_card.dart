import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class MetricCard extends StatelessWidget {
  final String label;
  final String value;
  final String? subValue;
  final IconData icon;
  final Color accentColor;
  final double? progressValue; // 0.0 – 1.0

  const MetricCard({
    super.key,
    required this.label,
    required this.value,
    this.subValue,
    required this.icon,
    required this.accentColor,
    this.progressValue,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.borderColor, width: 1),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(icon, color: accentColor, size: 18),
                    const SizedBox(width: 8),
                    Text(
                      label,
                      style: TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        letterSpacing: 0.8,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  value,
                  style: TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 26,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (subValue != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    subValue!,
                    style: TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (progressValue != null) ...[
            const SizedBox(width: 12),
            SizedBox(
              width: 76,
              height: 76,
              child: _ArcGauge(
                value: progressValue!.clamp(0.0, 1.0),
                color: accentColor,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ArcGauge extends StatelessWidget {
  final double value; // already clamped 0.0 – 1.0
  final Color color;

  const _ArcGauge({required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _ArcPainter(value: value, color: color),
      child: Center(
        child: Text(
          '${(value * 100).toInt()}%',
          style: TextStyle(
            color: color,
            fontSize: 13,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.5,
          ),
        ),
      ),
    );
  }
}

class _ArcPainter extends CustomPainter {
  final double value;
  final Color color;

  const _ArcPainter({required this.value, required this.color});

  // 135° start (7:30 position) → 270° sweep → gap at top
  static const _start = 135.0 * math.pi / 180.0;
  static const _sweep = 270.0 * math.pi / 180.0;

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 8.0;
    final radius = size.shortestSide / 2 - stroke / 2 - 2;
    final center = Offset(size.width / 2, size.height / 2);
    final rect = Rect.fromCircle(center: center, radius: radius);

    // Background track
    canvas.drawArc(
      rect,
      _start,
      _sweep,
      false,
      Paint()
        ..color = AppTheme.surfaceColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round,
    );

    if (value <= 0) return;

    final fillSweep = _sweep * value;

    // Glow
    canvas.drawArc(
      rect,
      _start,
      fillSweep,
      false,
      Paint()
        ..color = color.withValues(alpha: 0.28)
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke + 8
        ..strokeCap = StrokeCap.round
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
    );

    // Main arc
    canvas.drawArc(
      rect,
      _start,
      fillSweep,
      false,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_ArcPainter old) =>
      old.value != value || old.color != color;
}
