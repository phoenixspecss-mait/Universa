import 'package:flutter/material.dart';
import 'package:percent_indicator/circular_percent_indicator.dart';
import 'package:universa/core/theme/app_colors.dart';
import 'package:universa/core/theme/app_typography.dart';

/// A card for displaying an aggregate stat, optionally with a progress indicator.
class StatCard extends StatelessWidget {
  final String label;
  final String value;
  final Color accentColor;
  final double? progress;

  const StatCard({
    super.key,
    required this.label,
    required this.value,
    this.accentColor = AppColors.primaryNavyLight,
    this.progress,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: AppTypography.labelSmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: AppTypography.headlineLarge.copyWith(color: accentColor),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          if (progress != null) ...[
            const SizedBox(width: 16),
            CircularPercentIndicator(
              radius: 20.0,
              lineWidth: 3.0,
              percent: progress!.clamp(0.0, 1.0),
              progressColor: accentColor,
              backgroundColor: AppColors.border,
              circularStrokeCap: CircularStrokeCap.round,
            ),
          ],
        ],
      ),
    );
  }
}
