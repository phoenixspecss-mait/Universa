import 'package:flutter/material.dart';
import 'package:universa/core/theme/app_colors.dart';
import 'package:universa/core/theme/app_typography.dart';

/// The toolset bar below the toolbar in the Spatial Dossier Canvas.
class CanvasToolsetBar extends StatelessWidget {
  const CanvasToolsetBar({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      color: Colors.transparent,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _buildLeftSection(),
            const SizedBox(width: 24),
            _buildRightSection(),
          ],
        ),
      ),
    );
  }

  Widget _buildLeftSection() {
    return Row(
      children: [
        Text(
          'CANVAS TOOLSET:',
          style: AppTypography.labelSmall.copyWith(color: AppColors.textMuted),
        ),
        const SizedBox(width: 12),
        _buildToolButton(
          text: 'Select',
          icon: Icons.near_me,
          isSelected: true,
        ),
        const SizedBox(width: 8),
        _buildToolButton(
          text: 'Path Link',
          icon: Icons.timeline,
        ),
        const SizedBox(width: 8),
        _buildToolButton(
          text: 'Frame Carve',
          icon: Icons.crop,
        ),
        const SizedBox(width: 8),
        _buildToolButton(
          text: 'Annotation',
          icon: Icons.edit_note,
        ),
      ],
    );
  }

  Widget _buildToolButton({
    required String text,
    required IconData icon,
    bool isSelected = false,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(
        color: isSelected ? AppColors.electricCyan.withValues(alpha: 0.15) : AppColors.surface,
        border: Border.all(
          color: isSelected ? AppColors.electricCyan : AppColors.border,
        ),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        children: [
          Icon(
            icon,
            size: 14,
            color: isSelected ? AppColors.electricCyan : AppColors.textSecondary,
          ),
          const SizedBox(width: 6),
          Text(
            text,
            style: AppTypography.monoSmall.copyWith(
              color: isSelected ? AppColors.electricCyan : AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRightSection() {
    return Row(
      children: [
        Text(
          'Spatial Engine: ',
          style: AppTypography.labelSmall.copyWith(color: AppColors.textMuted),
        ),
        Text(
          'Active Trajectory',
          style: AppTypography.labelSmall.copyWith(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(width: 16),
        Row(
          children: [
            Text('−', style: AppTypography.bodyMedium.copyWith(color: AppColors.textMuted)),
            const SizedBox(width: 4),
            Text('100%', style: AppTypography.monoSmall.copyWith(color: AppColors.textPrimary)),
            const SizedBox(width: 4),
            Text('+', style: AppTypography.bodyMedium.copyWith(color: AppColors.textMuted)),
          ],
        ),
        const SizedBox(width: 16),
        Text(
          'Merkle Leaf: ',
          style: AppTypography.labelSmall.copyWith(color: AppColors.textMuted),
        ),
        Text(
          '8a9de37f',
          style: AppTypography.monoSmall.copyWith(color: AppColors.electricCyan),
        ),
      ],
    );
  }
}
