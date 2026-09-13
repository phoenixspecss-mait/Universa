import 'package:flutter/material.dart';
import 'package:universa/core/theme/app_colors.dart';
import 'package:universa/core/theme/app_typography.dart';

/// A card displaying a frame thumbnail with a bounding box and confidence score.
class FrameThumbnailCard extends StatelessWidget {
  final String cameraName;
  final String timestamp;
  final double confidence;
  final Color boundingBoxColor;
  final VoidCallback? onTap;

  const FrameThumbnailCard({
    super.key,
    required this.cameraName,
    required this.timestamp,
    required this.confidence,
    this.boundingBoxColor = AppColors.rustAmber,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      color: Colors.transparent,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: AppColors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        hoverColor: Colors.white.withValues(alpha: 0.05),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            AspectRatio(
              aspectRatio: 16 / 9,
              child: Container(
                color: AppColors.canvasBlack,
                child: Stack(
                  children: [
                    const Center(
                      child: Icon(Icons.videocam, color: AppColors.textMuted),
                    ),
                    Center(
                      child: FractionallySizedBox(
                        widthFactor: 0.6,
                        heightFactor: 0.7,
                        child: Container(
                          decoration: BoxDecoration(
                            border: Border.all(
                              color: boundingBoxColor,
                              width: 2,
                              strokeAlign: BorderSide.strokeAlignInside,
                            ),
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      top: 8,
                      right: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppColors.rustAmber.withValues(alpha: 0.9),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          '${confidence.toStringAsFixed(1)}%',
                          style: AppTypography.monoSmall.copyWith(
                            color: AppColors.canvasBlack,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    timestamp,
                    style: AppTypography.monoSmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    cameraName,
                    style: AppTypography.labelSmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
