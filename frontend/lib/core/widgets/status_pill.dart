import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:universa/core/theme/app_colors.dart';
import 'package:universa/core/theme/app_typography.dart';

/// Represents the status type for the pill widget
enum StatusType { verified, processing, active, flagged, offline }

/// A pill widget that displays a label with a colored background based on status
class StatusPill extends StatelessWidget {
  final String label;
  final StatusType status;

  const StatusPill({
    super.key,
    required this.label,
    required this.status,
  });

  Color _getStatusColor() {
    switch (status) {
      case StatusType.verified:
        return AppColors.tealGreen;
      case StatusType.processing:
        return AppColors.rustAmber;
      case StatusType.active:
        return AppColors.primaryNavyLight;
      case StatusType.flagged:
        return AppColors.error;
      case StatusType.offline:
        return AppColors.textMuted;
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = _getStatusColor();
    
    Widget pill = Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(100),
      ),
      child: Text(
        label,
        style: AppTypography.labelSmall.copyWith(color: color),
      ),
    );

    if (status == StatusType.processing) {
      pill = pill.animate(onPlay: (controller) => controller.repeat(reverse: true))
          .shimmer(duration: 1000.ms, color: color.withValues(alpha: 0.5));
    }

    return pill;
  }
}
