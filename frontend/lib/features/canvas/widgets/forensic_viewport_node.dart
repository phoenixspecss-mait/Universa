import 'package:flutter/material.dart';
import 'package:universa/core/theme/app_colors.dart';
import 'package:universa/core/theme/app_typography.dart';

/// Right panel for inspecting a forensic viewport
class ForensicViewportNode extends StatelessWidget {
  const ForensicViewportNode({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.borderLight, width: 1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Text(
                'GRAPH INSPECTION NODE #03',
                style: AppTypography.labelSmall.copyWith(color: AppColors.textMuted),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  border: Border.all(color: AppColors.electricCyan.withValues(alpha: 0.3)),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  '4X OPTICAL ZOOM',
                  style: AppTypography.monoSmall.copyWith(color: AppColors.electricCyan),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Target Forensic Viewport',
            style: AppTypography.headlineMedium.copyWith(
              color: AppColors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Text(
                'NIST SYNC: 48.89ms',
                style: AppTypography.monoSmall.copyWith(color: AppColors.textMuted),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.primaryNavy.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(3),
                ),
                child: Text(
                  'HEVC 4K RAW',
                  style: AppTypography.monoSmall.copyWith(
                    color: AppColors.white,
                    fontSize: 9,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Container(
            height: 160,
            width: double.infinity,
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
                    size: 60,
                  ),
                ),
                Center(
                  child: Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: AppColors.electricCyan.withValues(alpha: 0.5),
                        width: 1,
                      ),
                    ),
                    child: Center(
                      child: Container(
                        width: 60,
                        height: 60,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: AppColors.electricCyan.withValues(alpha: 0.5),
                            width: 1,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  top: 8,
                  right: 8,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        'LENS TARGET:',
                        style: AppTypography.labelSmall.copyWith(
                          color: AppColors.textMuted,
                          fontSize: 7,
                        ),
                      ),
                      Text(
                        'CHEST LOGO',
                        style: AppTypography.labelSmall.copyWith(
                          color: AppColors.electricCyan,
                          fontSize: 8,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.surface,
              border: Border.all(color: AppColors.border),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      'PIXEL ENTROPY & SNR DENSITY',
                      style: AppTypography.labelSmall.copyWith(color: AppColors.textMuted),
                    ),
                    const Spacer(),
                    Text(
                      '48.2 dB (FORENSIC GRADE)',
                      style: AppTypography.monoSmall.copyWith(color: AppColors.emerald),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                SizedBox(
                  height: 50,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      _buildBar(20, AppColors.emerald),
                      _buildBar(35, AppColors.tealGreen),
                      _buildBar(25, AppColors.emerald),
                      _buildBar(40, AppColors.tealGreen),
                      _buildBar(30, AppColors.emerald),
                      _buildBar(45, AppColors.tealGreen),
                      _buildBar(28, AppColors.emerald),
                      _buildBar(15, AppColors.tealGreen),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.surface,
              border: Border.all(color: AppColors.border),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      'DUAL-CLOCK DRIFT RECONCILIATION',
                      style: AppTypography.labelSmall.copyWith(color: AppColors.textMuted),
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppColors.emerald.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        'CALIBRATED',
                        style: AppTypography.labelSmall.copyWith(color: AppColors.emerald),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                _buildClockRow(
                  'OEM Cam Clock (Hikvision)',
                  '01:44:32 IST (+05:30)',
                  AppColors.textPrimary,
                ),
                const SizedBox(height: 6),
                Divider(height: 1, color: AppColors.border),
                const SizedBox(height: 6),
                _buildClockRow(
                  'Atomic Reference (NIST UTC)',
                  '20:14:32.410 UTC',
                  AppColors.electricCyan,
                ),
                const SizedBox(height: 6),
                Divider(height: 1, color: AppColors.border),
                const SizedBox(height: 6),
                _buildClockRow(
                  'Calculated Drift Delta',
                  '0.000 ms (Zero Drift)',
                  AppColors.emerald,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBar(double height, Color color) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Container(
          width: 12,
          height: height,
          decoration: BoxDecoration(
            color: color,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(2)),
          ),
        ),
        const SizedBox(height: 2),
        Container(
          width: 12,
          height: 3,
          color: AppColors.surface,
        ),
      ],
    );
  }

  Widget _buildClockRow(String label, String value, Color valueColor) {
    return Row(
      children: [
        Text(
          label,
          style: AppTypography.bodySmall.copyWith(color: AppColors.textSecondary),
        ),
        const Spacer(),
        Text(
          value,
          style: AppTypography.monoSmall.copyWith(color: valueColor),
        ),
      ],
    );
  }
}
