import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:universa/core/theme/app_colors.dart';
import 'package:universa/core/theme/app_typography.dart';

/// Top bar for the Studio screen
class StudioTopBar extends StatelessWidget {
  const StudioTopBar({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(
          bottom: BorderSide(color: AppColors.border),
        ),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
          const CircleAvatar(
            radius: 20,
            backgroundColor: AppColors.primaryNavy,
            child: Icon(Icons.play_circle_fill, color: AppColors.electricCyan, size: 20),
          ),
          const SizedBox(width: 8),
          Text(
            'UNIVERSA',
            style: GoogleFonts.playfairDisplay(
              fontWeight: FontWeight.bold,
              fontSize: 16,
              color: AppColors.white,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            'STUDIO',
            style: AppTypography.labelSmall.copyWith(
              color: AppColors.textMuted,
              letterSpacing: 2,
            ),
          ),
          const SizedBox(width: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.surface,
              border: Border.all(color: AppColors.rustAmber.withValues(alpha: 0.3)),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Row(
              children: [
                Text(
                  '#CR-2026-8841',
                  style: AppTypography.mono.copyWith(
                    color: AppColors.rustAmberLight,
                    fontSize: 11,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  'Nightwatch Metro Vault',
                  style: AppTypography.bodySmall.copyWith(color: AppColors.textSecondary),
                ),
                const Icon(Icons.arrow_drop_down, color: AppColors.textMuted, size: 16),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.emerald.withValues(alpha: 0.15),
              border: Border.all(color: AppColors.emerald),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Row(
              children: [
                Container(
                  width: 6,
                  height: 6,
                  decoration: const BoxDecoration(
                    color: AppColors.emerald,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 4),
                Text(
                  'ENCLAVE SECURE',
                  style: AppTypography.monoSmall.copyWith(
                    color: AppColors.emerald,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 24),
          const Icon(Icons.search, color: AppColors.textMuted, size: 18),
          const SizedBox(width: 4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
            decoration: BoxDecoration(
              color: AppColors.surface,
              border: Border.all(color: AppColors.border),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              '3K',
              style: AppTypography.monoSmall.copyWith(color: AppColors.textMuted),
            ),
          ),
          const SizedBox(width: 16),
          const Icon(Icons.speed, color: AppColors.textMuted, size: 14),
          const SizedBox(width: 4),
          Text(
            'LATENCY: ',
            style: AppTypography.labelSmall.copyWith(color: AppColors.textMuted),
          ),
          Text(
            '8ms',
            style: AppTypography.monoSmall.copyWith(color: AppColors.emerald),
          ),
          const SizedBox(width: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.electricCyan,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(
              children: [
                const Icon(Icons.auto_awesome, color: AppColors.canvasBlack, size: 14),
                const SizedBox(width: 6),
                Text(
                  'Run Neural Query',
                  style: AppTypography.labelSmall.copyWith(
                    color: AppColors.canvasBlack,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                'Det. Alex Vance',
                style: AppTypography.bodySmall.copyWith(color: AppColors.textPrimary),
              ),
              Text(
                'Lead Forensic • #8942',
                style: AppTypography.monoSmall.copyWith(color: AppColors.textMuted),
              ),
            ],
          ),
          ],
        ),
      ),
    );
  }
}
