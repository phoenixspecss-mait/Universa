import 'package:flutter/material.dart';
import 'package:universa/core/theme/app_colors.dart';
import 'package:universa/core/theme/app_typography.dart';

/// Bottom floating bar for the Admissibility Dock
class AdmissibilityDock extends StatelessWidget {
  const AdmissibilityDock({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.surfaceLight,
        border: Border.all(color: AppColors.borderLight, width: 1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
          const Icon(
            Icons.verified_user,
            color: AppColors.electricCyan,
            size: 18,
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Text(
                    'COURT-ADMISSIBILITY HASH LEDGER',
                    style: AppTypography.labelSmall.copyWith(
                      color: AppColors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppColors.rustAmber.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(3),
                    ),
                    child: Text(
                      '§63 BSA CERTIFIED',
                      style: AppTypography.labelSmall.copyWith(
                        color: AppColors.rustAmberLight,
                        fontSize: 9,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Text(
                    'Merkle Root: ',
                    style: AppTypography.labelSmall.copyWith(color: AppColors.textMuted),
                  ),
                  Text(
                    '8a9d7c4f10a0e291c784920...f8102',
                    style: AppTypography.monoSmall.copyWith(color: AppColors.electricCyan),
                  ),
                ],
              ),
            ],
          ),
          _buildVerticalDivider(),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'CUSTODY INTEGRITY',
                style: AppTypography.labelSmall.copyWith(
                  color: AppColors.textMuted,
                  fontSize: 8,
                ),
              ),
              const SizedBox(height: 2),
              Row(
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
                    'Node-04 Enclave ',
                    style: AppTypography.bodySmall.copyWith(color: AppColors.textPrimary),
                  ),
                  Text(
                    'Sealed',
                    style: AppTypography.bodySmall.copyWith(color: AppColors.emerald),
                  ),
                ],
              ),
            ],
          ),
          _buildVerticalDivider(),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'SIGN-OFF OFFICER',
                style: AppTypography.labelSmall.copyWith(
                  color: AppColors.textMuted,
                  fontSize: 8,
                ),
              ),
              const SizedBox(height: 2),
              Row(
                children: [
                  Text(
                    'Det. Vance ',
                    style: AppTypography.bodySmall.copyWith(color: AppColors.textPrimary),
                  ),
                  Text(
                    '#8942',
                    style: AppTypography.monoSmall.copyWith(color: AppColors.textMuted),
                  ),
                ],
              ),
            ],
          ),
          _buildVerticalDivider(),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'ADMISSIBILITY STANDARD',
                style: AppTypography.labelSmall.copyWith(
                  color: AppColors.textMuted,
                  fontSize: 8,
                ),
              ),
              const SizedBox(height: 2),
              Row(
                children: [
                  Text(
                    'Standard ',
                    style: AppTypography.bodySmall.copyWith(color: AppColors.textSecondary),
                  ),
                  Text(
                    'ISO/IEC 27037',
                    style: AppTypography.monoSmall.copyWith(color: AppColors.textPrimary),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(width: 24),
          OutlinedButton(
            onPressed: () {},
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              minimumSize: const Size(0, 34),
              side: const BorderSide(color: AppColors.borderLight),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.description_outlined, size: 14, color: AppColors.textSecondary),
                const SizedBox(width: 4),
                Text(
                  'Export Cert',
                  style: AppTypography.monoSmall.copyWith(color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          ElevatedButton(
            onPressed: () {},
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.emerald,
              foregroundColor: AppColors.canvasBlack,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              minimumSize: const Size(0, 34),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.gavel, size: 14),
                const SizedBox(width: 4),
                Text(
                  'Commit To Evidentiary Dossier',
                  style: AppTypography.monoSmall.copyWith(fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
          ],
        ),
      ),
    );
  }

  Widget _buildVerticalDivider() {
    return Container(
      width: 1,
      height: 30,
      color: AppColors.border,
      margin: const EdgeInsets.symmetric(horizontal: 16),
    );
  }
}
