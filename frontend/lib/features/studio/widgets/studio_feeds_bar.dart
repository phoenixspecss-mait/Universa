import 'package:flutter/material.dart';
import 'package:universa/core/theme/app_colors.dart';
import 'package:universa/core/theme/app_typography.dart';

/// Feeds bar for the Studio screen
class StudioFeedsBar extends StatelessWidget {
  const StudioFeedsBar({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(
          bottom: BorderSide(color: AppColors.border),
        ),
      ),
      child: Row(
        children: [
          Text(
            'FEEDS:',
            style: AppTypography.labelSmall.copyWith(
              color: AppColors.textMuted,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            'Cam 03 • East Gate Outer',
            style: AppTypography.bodySmall.copyWith(color: AppColors.electricCyan),
          ),
          const SizedBox(width: 12),
          Container(width: 1, height: 12, color: AppColors.border),
          const SizedBox(width: 12),
          Text(
            'HEVC 4K @ 30.00 FPS',
            style: AppTypography.monoSmall.copyWith(color: AppColors.textSecondary),
          ),
          const SizedBox(width: 12),
          Container(width: 1, height: 12, color: AppColors.border),
          const SizedBox(width: 12),
          Row(
            children: [
              Text(
                '• ',
                style: AppTypography.bodySmall.copyWith(color: AppColors.rustAmberLight),
              ),
              Text(
                'Carved Deleted Block Extracted',
                style: AppTypography.bodySmall.copyWith(color: AppColors.rustAmberLight),
              ),
            ],
          ),
          const Spacer(),
          Text(
            'Match 1 of 4',
            style: AppTypography.labelSmall.copyWith(color: AppColors.textMuted),
          ),
          const SizedBox(width: 8),
          Row(
            children: [
              IconButton(
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                icon: const Icon(Icons.chevron_left, color: AppColors.textMuted, size: 16),
                onPressed: () {},
              ),
              const SizedBox(width: 8),
              IconButton(
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                icon: const Icon(Icons.chevron_right, color: AppColors.textMuted, size: 16),
                onPressed: () {},
              ),
            ],
          ),
        ],
      ),
    );
  }
}
