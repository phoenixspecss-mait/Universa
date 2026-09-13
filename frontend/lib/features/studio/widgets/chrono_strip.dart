import 'package:flutter/material.dart';
import 'package:universa/core/theme/app_colors.dart';
import 'package:universa/core/theme/app_typography.dart';

class ChronoStrip extends StatelessWidget {
  const ChronoStrip({super.key});

  @override
  Widget build(BuildContext context) {
    final matches = [
      {
        'id': '#01',
        'time': '20:14:32 UTC',
        'conf': '96.8% CONF',
        'highConf': true,
        'cam': 'Cam 03: East Gate  #TRK-4491'
      },
      {
        'id': '#02',
        'time': '20:18:05 UTC',
        'conf': '94.2% CONF',
        'highConf': true,
        'cam': 'Cam 07: Vault Cor.. #TRK-4491'
      },
      {
        'id': '#03',
        'time': '20:12:11 UTC',
        'conf': '89.1% CONF',
        'highConf': false,
        'cam': 'Cam 02: North Wing #TRK-4491'
      },
      {
        'id': '#04',
        'time': '20:24:49 UTC',
        'conf': '91.5% CONF',
        'highConf': true,
        'cam': 'Cam 12: Lobby Entry #TRK-4491'
      },
    ];

    return Column(
      children: [
        // 1. Header
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              const Icon(Icons.timeline, color: AppColors.electricCyan, size: 16),
              const SizedBox(width: 6),
              Text('CHRONO-EVENT CORRELATION STRIP',
                  style: AppTypography.labelSmall.copyWith(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1)),
              const SizedBox(width: 12),
              Container(
                  width: 6,
                  height: 6,
                  decoration: const BoxDecoration(
                      color: AppColors.electricCyan, shape: BoxShape.circle)),
              const SizedBox(width: 3),
              Text('Cross-Cam Matches',
                  style: AppTypography.monoSmall.copyWith(
                      color: AppColors.textMuted, fontSize: 8)),
              const SizedBox(width: 10),
              Container(
                  width: 6,
                  height: 6,
                  decoration: const BoxDecoration(
                      color: AppColors.rustAmberLight, shape: BoxShape.circle)),
              const SizedBox(width: 3),
              Text('Carved Hit',
                  style: AppTypography.monoSmall.copyWith(
                      color: AppColors.textMuted, fontSize: 8)),
              const SizedBox(width: 10),
              Container(
                  width: 6,
                  height: 6,
                  decoration: const BoxDecoration(
                      color: AppColors.emerald, shape: BoxShape.circle)),
              const SizedBox(width: 3),
              Text('Active Ingest',
                  style: AppTypography.monoSmall.copyWith(
                      color: AppColors.textMuted, fontSize: 8)),
              const SizedBox(width: 10),
              Text('▼ Threshold: >85%',
                  style: AppTypography.monoSmall.copyWith(
                      color: AppColors.textMuted)),
            ],
          ),
        ),
        const SizedBox(height: 4),

        // 3. Match cards row
        SizedBox(
          height: 130,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: matches.length,
            itemBuilder: (context, index) {
              final match = matches[index];
              final isFirst = index == 0;
              return Container(
                width: 180,
                margin: const EdgeInsets.only(right: 12),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  border: Border.all(color: AppColors.borderLight),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: const BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.vertical(top: Radius.circular(6)),
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: isFirst
                                  ? AppColors.electricCyan.withValues(alpha: 0.15)
                                  : AppColors.surface,
                              borderRadius: BorderRadius.circular(3),
                            ),
                            child: Text('MATCH ${match['id']}',
                                style: AppTypography.monoSmall.copyWith(
                                    color: isFirst
                                        ? AppColors.electricCyan
                                        : AppColors.textMuted)),
                          ),
                          const SizedBox(width: 6),
                          Text(match['time'] as String,
                              style: AppTypography.monoSmall.copyWith(
                                  color: AppColors.textMuted, fontSize: 9)),
                          if (isFirst) ...[
                            const Spacer(),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 4, vertical: 1),
                              decoration: BoxDecoration(
                                color: AppColors.rustAmber.withValues(alpha: 0.20),
                                borderRadius: BorderRadius.circular(3),
                              ),
                              child: Text('CARVED',
                                  style: AppTypography.monoSmall.copyWith(
                                      color: AppColors.rustAmberLight,
                                      fontSize: 8)),
                            ),
                          ],
                        ],
                      ),
                    ),
                    Expanded(
                      child: Container(
                        color: AppColors.canvasBlack,
                        child: const Center(
                          child: Icon(Icons.videocam,
                              color: AppColors.textMuted, size: 24),
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 4),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: (match['highConf'] as bool)
                                  ? AppColors.emerald.withValues(alpha: 0.15)
                                  : AppColors.rustAmberLight.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(3),
                            ),
                            child: Text(match['conf'] as String,
                                style: AppTypography.monoSmall.copyWith(
                                    color: (match['highConf'] as bool)
                                        ? AppColors.emerald
                                        : AppColors.rustAmberLight,
                                    fontSize: 8)),
                          ),
                          const Spacer(),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      alignment: Alignment.centerLeft,
                      child: Text(match['cam'] as String,
                          style: AppTypography.monoSmall.copyWith(
                              color: AppColors.textMuted, fontSize: 8),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
