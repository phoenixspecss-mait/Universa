import 'package:flutter/material.dart';
import 'package:universa/core/theme/app_colors.dart';
import 'package:universa/core/theme/app_typography.dart';

class StudioViewport extends StatelessWidget {
  const StudioViewport({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // 1. Camera info bar
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          color: Colors.transparent,
          child: Row(
            children: [
              Text('OPTICAL TENSOR ZONE 1.0x',
                  style: AppTypography.monoSmall.copyWith(
                      color: AppColors.textMuted, fontSize: 9)),
              const SizedBox(width: 16),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('CAM-03 (EAST GATE)',
                      style: AppTypography.monoSmall.copyWith(
                          color: AppColors.electricCyan, fontSize: 10)),
                ],
              ),
              const SizedBox(width: 16),
              Column(
                children: [
                  Text('20:14:32.410',
                      style: AppTypography.mono.copyWith(
                          color: AppColors.textPrimary, fontSize: 13)),
                  Text('UTC',
                      style: AppTypography.labelSmall.copyWith(
                          color: AppColors.textMuted, fontSize: 8),
                      textAlign: TextAlign.center),
                ],
              ),
              const SizedBox(width: 16),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('FRAME',
                      style: AppTypography.labelSmall.copyWith(
                          color: AppColors.textMuted, fontSize: 8)),
                  Text('#481,209',
                      style: AppTypography.monoSmall.copyWith(
                          color: AppColors.textSecondary)),
                ],
              ),
              const SizedBox(width: 16),
              Text('QP-18 • RAW 10-BIT',
                  style: AppTypography.monoSmall.copyWith(
                      color: AppColors.textMuted, fontSize: 9)),
            ],
          ),
        ),
        const SizedBox(height: 4),

        // 3. Main viewport
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              color: AppColors.canvasBlack,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: AppColors.borderLight),
            ),
            child: Stack(
              children: [
                const Center(
                  child: Icon(Icons.videocam,
                      color: AppColors.textMuted, size: 80),
                ),
                Align(
                  alignment: Alignment.topCenter,
                  child: Container(
                    margin: const EdgeInsets.only(top: 8),
                    decoration: BoxDecoration(
                      color: AppColors.surface.withValues(alpha: 0.8),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('Person',
                            style: AppTypography.monoSmall
                                .copyWith(color: AppColors.textPrimary)),
                        const SizedBox(width: 4),
                        Text('96.8%',
                            style: AppTypography.monoSmall
                                .copyWith(color: AppColors.rustAmberLight)),
                        const SizedBox(width: 6),
                        Container(
                          decoration: BoxDecoration(
                            color: AppColors.electricCyan.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(3),
                          ),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 1),
                          child: Text('#TRK-4491',
                              style: AppTypography.monoSmall
                                  .copyWith(color: AppColors.electricCyan)),
                        ),
                      ],
                    ),
                  ),
                ),
                Center(
                  child: FractionallySizedBox(
                    widthFactor: 0.35,
                    heightFactor: 0.45,
                    child: Container(
                      decoration: BoxDecoration(
                        border: Border.all(
                            color: AppColors.rustAmberLight, width: 2),
                      ),
                      child: Stack(
                        children: [
                          Positioned(
                            top: -2,
                            left: -2,
                            child: Container(
                              width: 8,
                              height: 8,
                              decoration: const BoxDecoration(
                                border: Border(
                                  top: BorderSide(
                                      color: AppColors.rustAmberLight, width: 2),
                                  left: BorderSide(
                                      color: AppColors.rustAmberLight, width: 2),
                                ),
                              ),
                            ),
                          ),
                          Positioned(
                            top: -2,
                            right: -2,
                            child: Container(
                              width: 8,
                              height: 8,
                              decoration: const BoxDecoration(
                                border: Border(
                                  top: BorderSide(
                                      color: AppColors.rustAmberLight, width: 2),
                                  right: BorderSide(
                                      color: AppColors.rustAmberLight, width: 2),
                                ),
                              ),
                            ),
                          ),
                          Positioned(
                            bottom: -2,
                            left: -2,
                            child: Container(
                              width: 8,
                              height: 8,
                              decoration: const BoxDecoration(
                                border: Border(
                                  bottom: BorderSide(
                                      color: AppColors.rustAmberLight, width: 2),
                                  left: BorderSide(
                                      color: AppColors.rustAmberLight, width: 2),
                                ),
                              ),
                            ),
                          ),
                          Positioned(
                            bottom: -2,
                            right: -2,
                            child: Container(
                              width: 8,
                              height: 8,
                              decoration: const BoxDecoration(
                                border: Border(
                                  bottom: BorderSide(
                                      color: AppColors.rustAmberLight, width: 2),
                                  right: BorderSide(
                                      color: AppColors.rustAmberLight, width: 2),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                Positioned(
                  top: 8,
                  right: 8,
                  child: Container(
                    width: 80,
                    height: 60,
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      border: Border.all(color: AppColors.borderLight),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Center(
                      child: Icon(Icons.person_outline,
                          color: AppColors.textMuted, size: 24),
                    ),
                  ),
                ),
                Positioned(
                  bottom: 8,
                  left: 8,
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    child: Text('03:47:18',
                        style: AppTypography.monoSmall
                            .copyWith(color: AppColors.textMuted)),
                  ),
                ),
                Positioned(
                  top: 8,
                  left: 8,
                  child: Row(
                    children: [
                      Container(
                          width: 6,
                          height: 6,
                          decoration: const BoxDecoration(
                              color: AppColors.error, shape: BoxShape.circle)),
                      const SizedBox(width: 4),
                      Container(
                          width: 6,
                          height: 6,
                          decoration: const BoxDecoration(
                              color: AppColors.rustAmberLight,
                              shape: BoxShape.circle)),
                      const SizedBox(width: 4),
                      Container(
                          width: 6,
                          height: 6,
                          decoration: const BoxDecoration(
                              color: AppColors.emerald, shape: BoxShape.circle)),
                    ],
                  ),
                ),
                Align(
                  alignment: Alignment.bottomCenter,
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    decoration: BoxDecoration(
                      color: AppColors.surface.withValues(alpha: 0.8),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 4),
                    child: Text('SEARCH: Subject in red jacket near vault gate',
                        style: AppTypography.bodySmall
                            .copyWith(color: AppColors.textSecondary)),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 4),

        // 5. Detection pills row
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              Container(
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  border: Border.all(color: AppColors.border),
                  borderRadius: BorderRadius.circular(4),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Row(
                  children: [
                    const Icon(Icons.label,
                        color: AppColors.textMuted, size: 14),
                    const SizedBox(width: 4),
                    Text('Duffel',
                        style: AppTypography.bodySmall
                            .copyWith(color: AppColors.textPrimary)),
                    const SizedBox(width: 4),
                    Text('92.4%',
                        style: AppTypography.monoSmall
                            .copyWith(color: AppColors.rustAmberLight)),
                  ],
                ),
              ),
              const Spacer(),
              const Icon(Icons.search,
                  color: AppColors.electricCyan, size: 16),
            ],
          ),
        ),
        const SizedBox(height: 4),

        // 7. Related entries
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(4),
          ),
          margin: const EdgeInsets.only(bottom: 4),
          child: Row(
            children: [
              const Icon(Icons.key, color: AppColors.textMuted, size: 14),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                    'Related Entry: Access Log - Authorized Personnel (03:45 GMT)',
                    style: AppTypography.bodySmall
                        .copyWith(color: AppColors.textSecondary)),
              ),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(4),
          ),
          margin: const EdgeInsets.only(bottom: 4),
          child: Row(
            children: [
              const Icon(Icons.sensors, color: AppColors.textMuted, size: 14),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                    'Related Entry: Motion Sensor Trigger - Zone C (03:47 GMT)',
                    style: AppTypography.bodySmall
                        .copyWith(color: AppColors.textSecondary)),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),

        // 9. Scrub bar
        SizedBox(
          height: 12,
          child: LayoutBuilder(
            builder: (context, constraints) {
              return Stack(
                alignment: Alignment.center,
                clipBehavior: Clip.none,
                children: [
                  Container(
                    height: 8,
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  Positioned(
                    left: 0,
                    child: Container(
                      height: 8,
                      width: constraints.maxWidth * 0.4,
                      decoration: BoxDecoration(
                        color: AppColors.electricCyan,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
                  Positioned(
                    left: constraints.maxWidth * 0.35,
                    top: 2,
                    child: Container(
                        width: 4,
                        height: 4,
                        color: AppColors.electricCyan),
                  ),
                  Positioned(
                    left: constraints.maxWidth * 0.55,
                    top: 2,
                    child: Container(
                        width: 4,
                        height: 4,
                        color: AppColors.emerald),
                  ),
                  Positioned(
                    left: constraints.maxWidth * 0.75,
                    top: 2,
                    child: Container(
                        width: 4,
                        height: 4,
                        color: AppColors.rustAmberLight),
                  ),
                ],
              );
            },
          ),
        ),
        const SizedBox(height: 8),

        // 11. Playback controls
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Row(
            children: [
              Container(
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  border: Border.all(color: AppColors.border),
                  borderRadius: BorderRadius.circular(4),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Text('-1F',
                    style: AppTypography.monoSmall
                        .copyWith(color: AppColors.textSecondary)),
              ),
              const SizedBox(width: 8),
              Container(
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  border: Border.all(color: AppColors.border),
                  borderRadius: BorderRadius.circular(4),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Text('+1F',
                    style: AppTypography.monoSmall
                        .copyWith(color: AppColors.textSecondary)),
              ),
              const SizedBox(width: 12),
              const Icon(Icons.play_arrow_rounded,
                  color: AppColors.electricCyan, size: 28),
              const SizedBox(width: 12),
              Container(
                decoration: BoxDecoration(
                  color: AppColors.electricCyan.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(4),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Text('0.25x (SLO-MO)',
                    style: AppTypography.monoSmall
                        .copyWith(color: AppColors.electricCyan)),
              ),
              const SizedBox(width: 16),
              Text('20:14:32.410',
                  style: AppTypography.mono.copyWith(
                      color: AppColors.textPrimary, fontSize: 12)),
              Text(' / ',
                  style: AppTypography.mono.copyWith(
                      color: AppColors.textMuted, fontSize: 12)),
              Text('21:00:00.000',
                  style: AppTypography.mono.copyWith(
                      color: AppColors.textMuted, fontSize: 12)),
              const Spacer(),
              const Row(
                children: [
                  Icon(Icons.grid_view,
                      color: AppColors.textMuted, size: 18),
                  SizedBox(width: 8),
                  Icon(Icons.view_column,
                      color: AppColors.textMuted, size: 18),
                  SizedBox(width: 8),
                  Icon(Icons.fullscreen,
                      color: AppColors.textMuted, size: 18),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}
