import 'package:flutter/material.dart';
import 'package:universa/core/theme/app_colors.dart';
import 'package:universa/core/theme/app_typography.dart';

class TrajectoryNode extends StatelessWidget {
  const TrajectoryNode({super.key});

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
          // Top Row
          Row(
            children: [
              Text(
                'GRAPH WORKFLOW NODE #02',
                style: AppTypography.labelSmall.copyWith(color: AppColors.textMuted),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  border: Border.all(color: AppColors.borderLight),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  'PEAK: 20:14 − 20:24 UTC',
                  style: AppTypography.monoSmall.copyWith(color: AppColors.textSecondary),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Title
          Text(
            'Multi-Cam Trajectory Reconstruction',
            style: AppTypography.headlineMedium.copyWith(
              color: AppColors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          // Path Info Row
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
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  'Reconstructed Ingress & Egress Path',
                  style: AppTypography.bodySmall.copyWith(color: AppColors.textSecondary),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  '18 min 17 sec Total Interval',
                  style: AppTypography.bodySmall.copyWith(
                    color: AppColors.emerald,
                    fontWeight: FontWeight.bold,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Timeline Section
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Flexible(
                child: _buildMilestoneColumn(
                  number: '01',
                  color: AppColors.electricCyan,
                  cam: 'CAM-03',
                  time: '20:14:32 UTC',
                  location: 'East Gate',
                  event: 'Ingress',
                ),
              ),
              Flexible(child: _buildTransitIndicator('+3m 33s transit')),
              Flexible(
                child: _buildMilestoneColumn(
                  number: '02',
                  color: AppColors.emerald,
                  cam: 'CAM-07',
                  time: '20:18:05 UTC',
                  location: 'Vault Corridor',
                  event: '',
                ),
              ),
              Flexible(child: _buildTransitIndicator('+6m 44s transit')),
              Flexible(
                child: _buildMilestoneColumn(
                  number: '03',
                  color: AppColors.rustAmberLight,
                  cam: 'CAM-12',
                  time: '20:24:49 UTC',
                  location: 'Service Bay',
                  event: 'Egress',
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Divider(color: AppColors.border, height: 1),
          const SizedBox(height: 16),
          // Frame Comparison Strip
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildFrameNode(
                nodeId: 'NODE A',
                isCyan: true,
                time: '20:14:32',
                locationTitle: 'EAST GATE',
                matchDesc: 'Identified',
                matchPct: '96.8%',
                pctColor: AppColors.emerald,
              ),
              const SizedBox(width: 8),
              _buildFrameNode(
                nodeId: 'NODE B',
                isCyan: false,
                time: '20:18:05',
                locationTitle: 'VAULT HALL',
                matchDesc: 'Partial View',
                matchPct: '94.2%',
                pctColor: AppColors.emerald,
              ),
              const SizedBox(width: 8),
              _buildFrameNode(
                nodeId: 'NODE C',
                isCyan: false,
                time: '20:24:49',
                locationTitle: 'SERVICE BAY',
                matchDesc: 'Occluded',
                matchPct: '91.5%',
                pctColor: AppColors.rustAmberLight,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMilestoneColumn({
    required String number,
    required Color color,
    required String cam,
    required String time,
    required String location,
    required String event,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: color, width: 2),
          ),
          child: Center(
            child: Text(
              number,
              style: AppTypography.mono.copyWith(
                color: AppColors.white,
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          cam,
          style: AppTypography.labelSmall.copyWith(
            color: AppColors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(
          time,
          style: AppTypography.monoSmall.copyWith(color: AppColors.electricCyan),
        ),
        Text(
          location,
          style: AppTypography.labelSmall.copyWith(color: AppColors.textMuted),
        ),
        if (event.isNotEmpty)
          Text(
            event,
            style: AppTypography.labelSmall.copyWith(color: AppColors.textSecondary),
          ),
      ],
    );
  }

  Widget _buildTransitIndicator(String text) {
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Row(
        children: [
          Expanded(
            child: Divider(
              color: AppColors.electricCyan.withValues(alpha: 0.3),
              thickness: 1,
            ),
          ),
          const SizedBox(width: 4),
          Flexible(
            flex: 0,
            child: Text(
              text,
              style: AppTypography.monoSmall.copyWith(color: AppColors.textMuted),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Divider(
              color: AppColors.electricCyan.withValues(alpha: 0.3),
              thickness: 1,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFrameNode({
    required String nodeId,
    required bool isCyan,
    required String time,
    required String locationTitle,
    required String matchDesc,
    required String matchPct,
    required Color pctColor,
  }) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.all(4.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: isCyan ? AppColors.electricCyan.withValues(alpha: 0.15) : AppColors.surface,
                    borderRadius: BorderRadius.circular(4),
                    border: isCyan ? null : Border.all(color: AppColors.borderLight),
                  ),
                  child: Text(
                    nodeId,
                    style: AppTypography.monoSmall.copyWith(
                      color: isCyan ? AppColors.electricCyan : AppColors.textSecondary,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  time,
                  style: AppTypography.monoSmall.copyWith(color: AppColors.textMuted),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Container(
              height: 80,
              decoration: BoxDecoration(
                color: AppColors.canvasBlack,
                border: Border.all(color: AppColors.borderLight),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.videocam, color: AppColors.textMuted, size: 20),
                    const SizedBox(height: 2),
                    Text(
                      locationTitle,
                      style: AppTypography.labelSmall.copyWith(
                        color: AppColors.textMuted,
                        fontSize: 8,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: Text(
                    matchDesc,
                    style: AppTypography.labelSmall.copyWith(color: AppColors.textMuted),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      'MATCH',
                      style: AppTypography.labelSmall.copyWith(
                        color: AppColors.textMuted,
                        fontSize: 8,
                      ),
                    ),
                    Text(
                      matchPct,
                      style: AppTypography.monoSmall.copyWith(color: pctColor),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
