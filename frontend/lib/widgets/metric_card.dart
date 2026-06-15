import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class MetricCard extends StatelessWidget {
  final String label;
  final String value;
  final String? subValue;
  final IconData icon;
  final Color accentColor;
  final double? progressValue;
  final List<double>? sparkData;

  const MetricCard({
    super.key,
    required this.label,
    required this.value,
    this.subValue,
    required this.icon,
    required this.accentColor,
    this.progressValue,
    this.sparkData,
  });

  @override
  Widget build(BuildContext context) {
    final hasSpark = sparkData != null && sparkData!.length >= 2;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.borderColor, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
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
              if (hasSpark) ...[
                const SizedBox(width: 8),
                SizedBox(
                  width: 80,
                  height: 50,
                  child: _SparkLine(data: sparkData!, color: accentColor),
                ),
              ],
            ],
          ),
          if (progressValue != null) ...[
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: progressValue!.clamp(0.0, 1.0),
                backgroundColor: AppTheme.surfaceColor,
                valueColor: AlwaysStoppedAnimation<Color>(accentColor),
                minHeight: 6,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _SparkLine extends StatelessWidget {
  final List<double> data;
  final Color color;

  const _SparkLine({required this.data, required this.color});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _SparkPainter(data: data, color: color),
      child: const SizedBox.expand(),
    );
  }
}

class _SparkPainter extends CustomPainter {
  final List<double> data;
  final Color color;

  const _SparkPainter({required this.data, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    if (data.length < 2) return;

    final minV = data.reduce(math.min);
    final maxV = data.reduce(math.max);
    final range = maxV - minV;

    double normY(double v) =>
        range == 0 ? size.height * 0.5 : (1 - (v - minV) / range) * size.height;

    final pts = <Offset>[
      for (int i = 0; i < data.length; i++)
        Offset(i / (data.length - 1) * size.width, normY(data[i])),
    ];

    // Gradient fill below the line
    final fillPath = Path()..moveTo(pts.first.dx, size.height);
    for (final p in pts) fillPath.lineTo(p.dx, p.dy);
    fillPath.lineTo(pts.last.dx, size.height);
    fillPath.close();
    canvas.drawPath(
      fillPath,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            color.withValues(alpha: 0.35),
            color.withValues(alpha: 0.0),
          ],
        ).createShader(Rect.fromLTWH(0, 0, size.width, size.height)),
    );

    // Line
    final linePath = Path()..moveTo(pts.first.dx, pts.first.dy);
    for (final p in pts.skip(1)) linePath.lineTo(p.dx, p.dy);
    canvas.drawPath(
      linePath,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_SparkPainter old) =>
      old.data != data || old.color != color;
}
