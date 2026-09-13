import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:universa/core/theme/app_colors.dart';
import 'package:universa/core/theme/app_typography.dart';

/// The top toolbar for the Spatial Dossier Canvas.
class CanvasToolbar extends StatelessWidget {
  const CanvasToolbar({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(
          bottom: BorderSide(color: AppColors.border, width: 1),
        ),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _buildLeftSection(),
            const SizedBox(width: 8),
            _buildCenterSection(context),
            const SizedBox(width: 8),
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
          'UNIVERSA',
          style: GoogleFonts.playfairDisplay(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: AppColors.white,
          ),
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: AppColors.surface,
            border: Border.all(color: AppColors.border),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            'CANVAS v3.4',
            style: AppTypography.monoSmall.copyWith(
              color: AppColors.electricCyan,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: AppColors.surface,
            border: Border.all(
              color: AppColors.rustAmber.withValues(alpha: 0.3),
            ),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            'CASE #CR-2026-8841',
            style: AppTypography.mono.copyWith(
              color: AppColors.rustAmber,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Row(
          children: [
            Text('Sector-04', style: AppTypography.bodySmall.copyWith(color: AppColors.textMuted)),
            Text(' / ', style: AppTypography.bodySmall.copyWith(color: AppColors.textMuted)),
            Text('Vault Breach', style: AppTypography.bodySmall.copyWith(color: AppColors.textSecondary)),
          ],
        ),
        const SizedBox(width: 8),
        Row(
          children: [
            Text('Spatial', style: AppTypography.bodySmall.copyWith(color: AppColors.textMuted)),
            Text(' / ', style: AppTypography.bodySmall.copyWith(color: AppColors.textMuted)),
            Text('Node Graph', style: AppTypography.bodySmall.copyWith(color: AppColors.textSecondary)),
          ],
        ),
      ],
    );
  }

  Widget _buildCenterSection(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
          _buildTab('Graph Canvas', isSelected: true, icon: Icons.hub),
          _buildTab('Studio Pro', icon: Icons.play_circle, onTap: () {
            GoRouter.of(context).go('/studio');
          }),
          _buildTab('Dashboard', icon: Icons.dashboard, onTap: () {
            GoRouter.of(context).go('/');
          }),
          _buildTab('§63 Dossier', icon: Icons.gavel, onTap: () {
            GoRouter.of(context).go('/report/CASE-2026-0143');
          }),
        ],
      );
  }

  Widget _buildTab(String text, {bool isSelected = false, IconData? icon, VoidCallback? onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: MouseRegion(
        cursor: onTap != null ? SystemMouseCursors.click : SystemMouseCursors.basic,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 4),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: isSelected ? AppColors.electricCyan.withValues(alpha: 0.15) : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(
                  icon,
                  size: 14,
                  color: isSelected ? AppColors.electricCyan : AppColors.textMuted,
                ),
                const SizedBox(width: 6),
              ],
              Text(
                text,
                style: AppTypography.monoSmall.copyWith(
                  color: isSelected ? AppColors.electricCyan : AppColors.textMuted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRightSection() {
    return Row(
      children: [
        Container(
          width: 220,
          height: 32,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: AppColors.surface,
            border: Border.all(color: AppColors.border),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Row(
            children: [
              const Icon(Icons.search, size: 14, color: AppColors.textMuted),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'red jacket near gate 3',
                  style: AppTypography.bodySmall.copyWith(color: AppColors.textMuted),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  '⌘K',
                  style: AppTypography.monoSmall.copyWith(color: AppColors.textMuted),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: AppColors.error.withValues(alpha: 0.15),
            border: Border.all(color: AppColors.error),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 6,
                height: 6,
                decoration: const BoxDecoration(
                  color: AppColors.error,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 4),
              Text(
                'HSM LOCKED',
                style: AppTypography.monoSmall.copyWith(color: AppColors.error),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        const CircleAvatar(
          radius: 14,
          backgroundColor: AppColors.surfaceLight,
          child: Icon(Icons.person, size: 16, color: AppColors.textPrimary),
        ),
      ],
    );
  }
}
