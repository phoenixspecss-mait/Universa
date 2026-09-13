import 'package:flutter/material.dart';
import 'package:universa/core/theme/app_colors.dart';
import 'package:universa/core/theme/app_typography.dart';

/// Right-side drawer panel for forensic inspection.
class ForensicInspector extends StatelessWidget {
  const ForensicInspector({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 300,
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(
          left: BorderSide(
            color: AppColors.borderLight,
            width: 1,
          ),
        ),
      ),
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 1. Header
              Row(
                children: [
                  const Icon(
                    Icons.biotech,
                    color: AppColors.electricCyan,
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'FORENSIC INSPECTOR',
                    style: AppTypography.labelSmall.copyWith(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.5,
                    ),
                  ),
                  const Spacer(),
                  Container(
                    decoration: BoxDecoration(
                      color: AppColors.emerald.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    child: Text(
                      'CARVE VALIDATED',
                      style: AppTypography.monoSmall.copyWith(
                        color: AppColors.emerald,
                        fontSize: 9,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // 3. Optical crop section
              Container(
                height: 120,
                decoration: BoxDecoration(
                  color: AppColors.canvasBlack,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: AppColors.borderLight),
                ),
                child: Stack(
                  children: [
                    const Center(
                      child: Icon(
                        Icons.person_outline,
                        color: AppColors.textMuted,
                        size: 40,
                      ),
                    ),
                    Positioned(
                      top: 8,
                      right: 8,
                      child: Container(
                        decoration: BoxDecoration(
                          color: AppColors.electricCyan.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(3),
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                        child: Text(
                          '4X OPTICAL CROP • INTERPOLATED',
                          style: AppTypography.monoSmall.copyWith(
                            fontSize: 7,
                            color: AppColors.electricCyan,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),

              // 5. Target BBox Vector
              Text(
                'Target BBox Vector:',
                style: AppTypography.labelSmall.copyWith(color: AppColors.textMuted),
              ),
              const SizedBox(height: 2),
              Text(
                '[x:1412, y:898, w:312, h:786]',
                style: AppTypography.mono.copyWith(
                  color: AppColors.textPrimary,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 4),
              Align(
                alignment: Alignment.centerRight,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.crop,
                      color: AppColors.electricCyan,
                      size: 14,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'Deep Crop',
                      style: AppTypography.bodySmall.copyWith(
                        color: AppColors.electricCyan,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // 11. Crypto hash card
              Container(
                decoration: BoxDecoration(
                  color: AppColors.surfaceLight,
                  border: Border.all(color: AppColors.borderLight),
                  borderRadius: BorderRadius.circular(6),
                ),
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          'CRYPTOGRAPHIC FRAME HASH',
                          style: AppTypography.labelSmall.copyWith(
                            color: AppColors.textMuted,
                            letterSpacing: 0.5,
                            fontSize: 9,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          'SHA-256 SECURED',
                          style: AppTypography.monoSmall.copyWith(
                            color: AppColors.emerald,
                            fontSize: 9,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'f4a0e291c78492040b3c661a91e521098df4923...',
                      style: AppTypography.monoSmall.copyWith(
                        color: AppColors.electricCyan,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Text(
                          'Block Sector: #B0841-B',
                          style: AppTypography.monoSmall.copyWith(
                            color: AppColors.textMuted,
                            fontSize: 9,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          'Merkle Leaf: Verified',
                          style: AppTypography.monoSmall.copyWith(
                            color: AppColors.emerald,
                            fontSize: 9,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),

              // 13. Atomic time card
              Container(
                decoration: BoxDecoration(
                  color: AppColors.surfaceLight,
                  border: Border.all(color: AppColors.borderLight),
                  borderRadius: BorderRadius.circular(6),
                ),
                padding: const EdgeInsets.all(12),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Text(
                          'ATOMIC TIME DRIFT CALIBRATION',
                          style: AppTypography.labelSmall.copyWith(
                            color: AppColors.textMuted,
                            fontSize: 9,
                            letterSpacing: 0.5,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          'NIST SYNC',
                          style: AppTypography.monoSmall.copyWith(
                            color: AppColors.emerald,
                            fontSize: 9,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Container(
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      padding: const EdgeInsets.all(8),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              const Icon(
                                Icons.schedule,
                                color: AppColors.textMuted,
                                size: 12,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                'OEM Header (Hikvision):',
                                style: AppTypography.labelSmall.copyWith(
                                  color: AppColors.textMuted,
                                  fontSize: 9,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 2),
                          Row(
                            children: [
                              Text(
                                '2026-03-29  01:44:32.410',
                                style: AppTypography.mono.copyWith(
                                  color: AppColors.textPrimary,
                                  fontSize: 11,
                                ),
                              ),
                              const Spacer(),
                              Container(
                                decoration: BoxDecoration(
                                  color: AppColors.electricCyan.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(3),
                                ),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                child: Text(
                                  '+05:30 IST',
                                  style: AppTypography.monoSmall.copyWith(
                                    color: AppColors.electricCyan,
                                    fontSize: 8,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      padding: const EdgeInsets.all(8),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              const Icon(
                                Icons.public,
                                color: AppColors.textMuted,
                                size: 12,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                'Calibrated Master UTC:',
                                style: AppTypography.labelSmall.copyWith(
                                  color: AppColors.textMuted,
                                  fontSize: 9,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 2),
                          Row(
                            children: [
                              Text(
                                '2026-03-28  20:14:32.410',
                                style: AppTypography.mono.copyWith(
                                  color: AppColors.electricCyan,
                                  fontSize: 11,
                                ),
                              ),
                              const Spacer(),
                              Text(
                                'Δ 0.00ms',
                                style: AppTypography.monoSmall.copyWith(
                                  color: AppColors.emerald,
                                  fontSize: 9,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),

              // 15. Admissibility card
              Container(
                decoration: BoxDecoration(
                  color: AppColors.surfaceLight,
                  border: Border.all(color: AppColors.borderLight),
                  borderRadius: BorderRadius.circular(6),
                ),
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          'ADMISSIBILITY CERTIFICATE',
                          style: AppTypography.labelSmall.copyWith(
                            color: AppColors.textMuted,
                            fontSize: 9,
                          ),
                        ),
                        const Spacer(),
                        const Icon(
                          Icons.check_circle,
                          color: AppColors.emerald,
                          size: 14,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'READY',
                          style: AppTypography.monoSmall.copyWith(
                            color: AppColors.emerald,
                            fontSize: 9,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Text(
                          'BSA §63 Forensic Compliance',
                          style: AppTypography.bodySmall.copyWith(
                            color: AppColors.textPrimary,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          'CERT-AD-2026',
                          style: AppTypography.monoSmall.copyWith(
                            color: AppColors.electricCyan,
                            fontSize: 9,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Chain of custody cryptographically signed by Node-04 enclave. Validated for submission in judicial proceedings.',
                      style: AppTypography.bodySmall.copyWith(
                        color: AppColors.textMuted,
                        fontSize: 10,
                      ),
                      maxLines: 3,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // 17. Action buttons
              Column(
                children: [
                  Container(
                    width: double.infinity,
                    height: 40,
                    decoration: BoxDecoration(
                      color: AppColors.emerald,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Center(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.gavel,
                            color: AppColors.canvasBlack,
                            size: 16,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'Add to Court Dossier',
                            style: AppTypography.labelSmall.copyWith(
                              color: AppColors.canvasBlack,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: Container(
                          height: 36,
                          decoration: BoxDecoration(
                            color: AppColors.surface,
                            border: Border.all(color: AppColors.borderLight),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Center(
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.image,
                                  color: AppColors.textSecondary,
                                  size: 14,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  'Export Raw Keyframe',
                                  style: AppTypography.monoSmall.copyWith(
                                    color: AppColors.textSecondary,
                                    fontSize: 10,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Container(
                          height: 36,
                          decoration: BoxDecoration(
                            color: AppColors.surface,
                            border: Border.all(color: AppColors.borderLight),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Center(
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.data_object,
                                  color: AppColors.textSecondary,
                                  size: 14,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  'JSON BBox',
                                  style: AppTypography.monoSmall.copyWith(
                                    color: AppColors.textSecondary,
                                    fontSize: 10,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
