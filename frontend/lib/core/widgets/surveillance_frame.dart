import 'dart:math';
import 'package:flutter/material.dart';
import 'package:universa/core/theme/app_colors.dart';
import 'package:universa/core/theme/app_typography.dart';

/// A realistic-looking surveillance camera frame with AI detection overlays.
/// Uses gradients, noise patterns, and HUD elements to simulate CCTV footage.
class SurveillanceFrame extends StatelessWidget {
  final String cameraName;
  final String timestamp;
  final double? confidence;
  final String? objectLabel;
  final Color? boundingBoxColor;
  final bool showHud;
  final bool showBoundingBox;
  final bool isCarved;
  final int variant; // 0-5, different visual styles
  final VoidCallback? onTap;

  const SurveillanceFrame({
    super.key,
    this.cameraName = 'CAM-03',
    this.timestamp = '20:14:32',
    this.confidence,
    this.objectLabel,
    this.boundingBoxColor,
    this.showHud = true,
    this.showBoundingBox = true,
    this.isCarved = false,
    this.variant = 0,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: AspectRatio(
          aspectRatio: 16 / 9,
          child: CustomPaint(
            painter: _SurveillancePainter(variant: variant),
            child: Stack(
              children: [
                // Scanline overlay
                Positioned.fill(
                  child: CustomPaint(painter: _ScanlinePainter()),
                ),

                // HUD overlay
                if (showHud) ...[
                  // Top-left: Camera ID + REC indicator
                  Positioned(
                    top: 6,
                    left: 8,
                    child: Row(
                      children: [
                        Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: AppColors.error,
                            boxShadow: [
                              BoxShadow(
                                color: AppColors.error.withValues(alpha: 0.6),
                                blurRadius: 4,
                                spreadRadius: 1,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'REC',
                          style: AppTypography.monoSmall.copyWith(
                            color: AppColors.error,
                            fontSize: 8,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          cameraName,
                          style: AppTypography.monoSmall.copyWith(
                            color: AppColors.white.withValues(alpha: 0.7),
                            fontSize: 8,
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Top-right: Timestamp
                  Positioned(
                    top: 6,
                    right: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(2),
                      ),
                      child: Text(
                        timestamp,
                        style: AppTypography.monoSmall.copyWith(
                          color: AppColors.white.withValues(alpha: 0.8),
                          fontSize: 9,
                        ),
                      ),
                    ),
                  ),
                ],

                // AI Bounding Box
                if (showBoundingBox) ...[
                  Positioned(
                    left: _boxPositions[variant % _boxPositions.length]['left']!,
                    top: _boxPositions[variant % _boxPositions.length]['top']!,
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        return _AiBoundingBox(
                          width: _boxPositions[variant % _boxPositions.length]['width']!,
                          height: _boxPositions[variant % _boxPositions.length]['height']!,
                          color: boundingBoxColor ?? AppColors.rustAmberLight,
                          label: objectLabel ?? 'Person',
                          confidence: confidence ?? 96.8,
                        );
                      },
                    ),
                  ),
                ],

                // Carved indicator
                if (isCarved)
                  Positioned(
                    bottom: 6,
                    left: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppColors.rustAmber.withValues(alpha: 0.8),
                        borderRadius: BorderRadius.circular(3),
                      ),
                      child: Text(
                        'CARVED',
                        style: AppTypography.monoSmall.copyWith(
                          color: AppColors.white,
                          fontSize: 7,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),

                // Bottom-right: AI badge
                if (confidence != null)
                  Positioned(
                    bottom: 6,
                    right: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppColors.emerald.withValues(alpha: 0.85),
                        borderRadius: BorderRadius.circular(3),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.emerald.withValues(alpha: 0.3),
                            blurRadius: 4,
                          ),
                        ],
                      ),
                      child: Text(
                        '${confidence!.toStringAsFixed(1)}%',
                        style: AppTypography.monoSmall.copyWith(
                          color: AppColors.white,
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static const List<Map<String, double>> _boxPositions = [
    {'left': 30, 'top': 15, 'width': 50, 'height': 70},
    {'left': 60, 'top': 10, 'width': 45, 'height': 65},
    {'left': 15, 'top': 20, 'width': 55, 'height': 60},
    {'left': 80, 'top': 12, 'width': 40, 'height': 72},
    {'left': 40, 'top': 18, 'width': 48, 'height': 62},
    {'left': 20, 'top': 8, 'width': 52, 'height': 75},
  ];
}

class _AiBoundingBox extends StatelessWidget {
  final double width, height;
  final Color color;
  final String label;
  final double confidence;

  const _AiBoundingBox({
    required this.width,
    required this.height,
    required this.color,
    required this.label,
    required this.confidence,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: height,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // Main border
          Container(
            decoration: BoxDecoration(
              border: Border.all(color: color, width: 1.5),
            ),
          ),
          // Corner markers
          ..._corners(color),
          // Label above box
          Positioned(
            top: -14,
            left: 0,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              color: color,
              child: Text(
                '$label ${confidence.toStringAsFixed(1)}%',
                style: AppTypography.monoSmall.copyWith(
                  color: Colors.black,
                  fontSize: 7,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _corners(Color c) {
    const size = 6.0;
    const w = 2.0;
    return [
      Positioned(top: 0, left: 0, child: Container(width: size, height: w, color: c)),
      Positioned(top: 0, left: 0, child: Container(width: w, height: size, color: c)),
      Positioned(top: 0, right: 0, child: Container(width: size, height: w, color: c)),
      Positioned(top: 0, right: 0, child: Container(width: w, height: size, color: c)),
      Positioned(bottom: 0, left: 0, child: Container(width: size, height: w, color: c)),
      Positioned(bottom: 0, left: 0, child: Container(width: w, height: size, color: c)),
      Positioned(bottom: 0, right: 0, child: Container(width: size, height: w, color: c)),
      Positioned(bottom: 0, right: 0, child: Container(width: w, height: size, color: c)),
    ];
  }
}

/// Paints a realistic dark surveillance scene with gradients and shapes.
class _SurveillancePainter extends CustomPainter {
  final int variant;
  _SurveillancePainter({this.variant = 0});

  @override
  void paint(Canvas canvas, Size size) {
    final rng = Random(variant * 42 + 7);

    // Base gradient — dark surveillance scene
    final colors = _sceneColors[variant % _sceneColors.length];
    final bgPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: colors,
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), bgPaint);

    // Add some architectural shapes (corridors, walls, doorways)
    final shapePaint = Paint()..style = PaintingStyle.fill;

    // Floor plane
    shapePaint.color = colors[0].withValues(alpha: 0.3);
    canvas.drawRect(Rect.fromLTWH(0, size.height * 0.6, size.width, size.height * 0.4), shapePaint);

    // Wall/corridor lines
    final linePaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.04)
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;

    for (int i = 0; i < 3; i++) {
      final y = size.height * (0.3 + i * 0.15);
      canvas.drawLine(Offset(0, y), Offset(size.width, y + rng.nextDouble() * 10 - 5), linePaint);
    }

    // Silhouette shapes (people, objects)
    final silhouettePaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.06)
      ..style = PaintingStyle.fill;

    // Person-like silhouette
    final px = size.width * (0.25 + rng.nextDouble() * 0.4);
    final py = size.height * 0.25;
    canvas.drawOval(Rect.fromCenter(center: Offset(px, py), width: 12, height: 14), silhouettePaint);
    canvas.drawRect(Rect.fromCenter(center: Offset(px, py + 25), width: 16, height: 35), silhouettePaint);

    // Additional environmental shapes
    for (int i = 0; i < 4; i++) {
      shapePaint.color = Colors.white.withValues(alpha: 0.02 + rng.nextDouble() * 0.03);
      final rx = rng.nextDouble() * size.width;
      final ry = rng.nextDouble() * size.height * 0.8;
      final rw = 15.0 + rng.nextDouble() * 40;
      final rh = 20.0 + rng.nextDouble() * 50;
      canvas.drawRect(Rect.fromLTWH(rx, ry, rw, rh), shapePaint);
    }

    // Vignette effect
    final vignettePaint = Paint()
      ..shader = RadialGradient(
        center: Alignment.center,
        radius: 0.9,
        colors: [Colors.transparent, Colors.black.withValues(alpha: 0.4)],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), vignettePaint);
  }

  static const List<List<Color>> _sceneColors = [
    [Color(0xFF0D1B2A), Color(0xFF1B2838), Color(0xFF0A1628)], // Night corridor
    [Color(0xFF162028), Color(0xFF1A2A32), Color(0xFF0E1A22)], // Teal security
    [Color(0xFF1A1520), Color(0xFF251A28), Color(0xFF120E18)], // Purple night
    [Color(0xFF181E14), Color(0xFF1E2818), Color(0xFF0E1610)], // Green night vision
    [Color(0xFF1E1810), Color(0xFF281E14), Color(0xFF16120C)], // Amber interior
    [Color(0xFF101820), Color(0xFF142028), Color(0xFF0C1418)], // Blue parking
  ];

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Subtle horizontal scanline overlay for CRT/surveillance feel.
class _ScanlinePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.black.withValues(alpha: 0.08)
      ..strokeWidth = 1;
    for (double y = 0; y < size.height; y += 3) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
