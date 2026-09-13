import 'package:flutter/material.dart';
import 'package:universa/core/theme/app_colors.dart';
import 'package:universa/core/theme/app_typography.dart';

class PoiDossierNode extends StatelessWidget {
  const PoiDossierNode({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.borderLight, width: 1),
        borderRadius: BorderRadius.circular(8),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Top Bar
          Row(
            children: [
              Text(
                'GRAPH ENTITY NODE #01',
                style: AppTypography.labelSmall.copyWith(color: AppColors.textMuted),
              ),
              const Spacer(),
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
                    'LOCKED',
                    style: AppTypography.labelSmall.copyWith(color: AppColors.emerald),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Title
          Text(
            'POI Profile Dossier',
            style: AppTypography.headlineMedium.copyWith(
              color: AppColors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          // Subject Area
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Left: Avatar and ID
              Column(
                children: [
                  Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Container(
                        width: 60,
                        height: 70,
                        decoration: BoxDecoration(
                          color: AppColors.canvasBlack,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Center(
                          child: Icon(Icons.person, color: AppColors.textMuted, size: 30),
                        ),
                      ),
                      Positioned(
                        top: -6,
                        right: -6,
                        child: Container(
                          width: 24,
                          height: 24,
                          decoration: BoxDecoration(
                            color: AppColors.emerald.withValues(alpha: 0.15),
                            shape: BoxShape.circle,
                            border: Border.all(color: AppColors.emerald, width: 2),
                          ),
                          child: Center(
                            child: Text(
                              '97',
                              style: AppTypography.labelSmall.copyWith(
                                color: AppColors.white,
                                fontSize: 8,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '#TRK-4491',
                    style: AppTypography.monoSmall.copyWith(color: AppColors.electricCyan),
                  ),
                ],
              ),
              const SizedBox(width: 12),
              // Right: Details
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Subject Alpha',
                      style: AppTypography.headlineSmall.copyWith(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      'Male, approx 180cm',
                      style: AppTypography.bodySmall.copyWith(color: AppColors.textSecondary),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: const Color(0xFFC0392B).withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            'Crimson Windbreaker',
                            style: AppTypography.bodySmall.copyWith(color: const Color(0xFFE74C3C)),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: AppColors.rustAmber.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            'Duffel Bag 92.4%',
                            style: AppTypography.bodySmall.copyWith(color: AppColors.rustAmberLight),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Divider(color: AppColors.border, height: 1),
          const SizedBox(height: 16),
          // Biometric Section
          Row(
            children: [
              Text(
                'BIOMETRIC ATTRIBUTE',
                style: AppTypography.labelSmall.copyWith(color: AppColors.textMuted),
              ),
              const Spacer(),
              Text(
                'VECTOR VALUE',
                style: AppTypography.labelSmall.copyWith(color: AppColors.textMuted),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _buildBiometricRow('Gait Kinematics', 'Asymmetric (Right Load)'),
          const SizedBox(height: 10),
          _buildBiometricRow('Facial Visibility', 'Cowl Obscured (22%)'),
          const SizedBox(height: 10),
          _buildBiometricRow('Spatial Trajectory', '3 Nodes Correlated'),
          const SizedBox(height: 14),
          // Action Row
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 36,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.electricCyan,
                      foregroundColor: AppColors.canvasBlack,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(6),
                      ),
                      padding: EdgeInsets.zero,
                      elevation: 0,
                    ),
                    onPressed: () {},
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.fingerprint, size: 16),
                        const SizedBox(width: 4),
                        Text(
                          'Re-Identify Cluster',
                          style: AppTypography.labelSmall.copyWith(
                            color: AppColors.canvasBlack,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  border: Border.all(color: AppColors.borderLight),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: IconButton(
                  padding: EdgeInsets.zero,
                  icon: const Icon(Icons.push_pin, size: 16, color: AppColors.textSecondary),
                  onPressed: () {},
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Divider(color: AppColors.border, height: 1),
          const SizedBox(height: 16),
          // Active Camera Enclave
          Row(
            children: [
              const Icon(Icons.sensors, size: 14, color: AppColors.textMuted),
              const SizedBox(width: 6),
              Text(
                'ACTIVE CAMERA ENCLAVE',
                style: AppTypography.labelSmall.copyWith(color: AppColors.textMuted),
              ),
              const Spacer(),
              Text(
                '3/4 SYNCED',
                style: AppTypography.labelSmall.copyWith(color: AppColors.emerald),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildCameraPill('CAM-03', '8 Hits', AppColors.electricCyan),
              const SizedBox(width: 8),
              _buildCameraPill('CAM-07', '4 Hits', AppColors.electricCyan),
              const SizedBox(width: 8),
              _buildCameraPill('CAM-12', '2 Hits', AppColors.rustAmberLight),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBiometricRow(String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Container(
            width: 6,
            height: 6,
            decoration: const BoxDecoration(
              color: AppColors.electricCyan,
              shape: BoxShape.circle,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Flexible(
                child: Text(
                  label,
                  style: AppTypography.bodySmall.copyWith(color: AppColors.textSecondary),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  value,
                  style: AppTypography.bodySmall.copyWith(
                    color: AppColors.emerald,
                    fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.right,
              ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildCameraPill(String id, String hits, Color hitsColor) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 6),
        decoration: BoxDecoration(
          color: AppColors.surface,
          border: Border.all(color: AppColors.electricCyan.withValues(alpha: 0.3)),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              id,
              style: AppTypography.monoSmall.copyWith(color: AppColors.textMuted),
            ),
            const SizedBox(height: 2),
            Text(
              hits,
              style: AppTypography.monoSmall.copyWith(color: hitsColor),
            ),
          ],
        ),
      ),
    );
  }
}
