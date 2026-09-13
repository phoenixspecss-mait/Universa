import 'package:flutter/material.dart';
import 'package:universa/core/theme/app_colors.dart';
import 'package:universa/core/theme/app_typography.dart';

/// Bottom status bar showing tamper seal, latency, and legal compliance status.
class CanvasStatusBar extends StatelessWidget {
  const CanvasStatusBar({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      color: AppColors.canvasBlack,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
          // Tamper seal
          Container(
            width: 6,
            height: 6,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.emerald,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            'TAMPER SEAL: UNBROKEN (HARDWARE ENCLAVE)',
            style: AppTypography.monoSmall.copyWith(
              fontSize: 9,
              color: AppColors.textMuted,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(width: 20),

          // Divider
          Container(width: 1, height: 10, color: AppColors.border),
          const SizedBox(width: 20),

          // Latency
          Text(
            'LATENCY: ',
            style: AppTypography.monoSmall.copyWith(
              fontSize: 9,
              color: AppColors.textMuted,
              letterSpacing: 0.5,
            ),
          ),
          Text(
            '12ms',
            style: AppTypography.monoSmall.copyWith(
              fontSize: 9,
              color: AppColors.textPrimary,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(width: 20),

          // Divider
          Container(width: 1, height: 10, color: AppColors.border),
          const SizedBox(width: 20),

          // FP16
          Text(
            'FP16 ACCELERATION: ',
            style: AppTypography.monoSmall.copyWith(
              fontSize: 9,
              color: AppColors.textMuted,
              letterSpacing: 0.5,
            ),
          ),
          Text(
            'TENSORRT LOCKED',
            style: AppTypography.monoSmall.copyWith(
              fontSize: 9,
              color: AppColors.emerald,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.5,
            ),
          ),

          const SizedBox(width: 24),

          // Section 63 compliance
          Text(
            'SECTION 63 BHARATIYA SAKSHYA ADMISSIBLE',
            style: AppTypography.monoSmall.copyWith(
              fontSize: 9,
              color: AppColors.textMuted,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(width: 8),
          Container(
            width: 6,
            height: 6,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.emerald,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            'READY',
            style: AppTypography.monoSmall.copyWith(
              fontSize: 9,
              color: AppColors.emerald,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.5,
            ),
          ),
          ],
        ),
      ),
    );
  }
}
