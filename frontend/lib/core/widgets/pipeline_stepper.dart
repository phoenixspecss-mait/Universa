import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:universa/core/theme/app_colors.dart';
import 'package:universa/core/theme/app_typography.dart';

/// A horizontal stepper widget to represent processing stages.
class PipelineStepper extends StatelessWidget {
  final int currentStage;
  final List<String> stages;

  const PipelineStepper({
    super.key,
    required this.currentStage,
    this.stages = const [
      'Zero-Write',
      'Format Fingerprinting',
      'Parsing & Carving',
      'Normalization',
      'AI Triage',
      'Signed Export',
    ],
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final showLabels = constraints.maxWidth > 400;

        return Row(
          children: List.generate(stages.length, (index) {
            final isCompleted = index < currentStage;
            final isCurrent = index == currentStage;
            final isLast = index == stages.length - 1;

            Widget dot = Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isCompleted
                    ? AppColors.tealGreen
                    : (isCurrent ? AppColors.rustAmber : Colors.transparent),
                border: isCompleted || isCurrent
                    ? null
                    : Border.all(color: AppColors.border),
              ),
            );

            if (isCurrent) {
              dot = dot.animate(onPlay: (controller) => controller.repeat(reverse: true))
                  .scale(duration: 800.ms, begin: const Offset(1, 1), end: const Offset(1.2, 1.2))
                  .fade(duration: 800.ms, begin: 0.8, end: 1.0);
            }

            final stageWidget = Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      dot,
                      if (!isLast)
                        Expanded(
                          child: Container(
                            height: 2,
                            color: isCompleted ? AppColors.tealGreen : AppColors.border,
                          ),
                        ),
                    ],
                  ),
                  if (showLabels) ...[
                    const SizedBox(height: 4),
                    Text(
                      stages[index],
                      style: AppTypography.labelSmall.copyWith(
                        fontSize: 8,
                        color: isCompleted || isCurrent ? AppColors.textPrimary : AppColors.textMuted,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            );

            return stageWidget;
          }),
        );
      },
    );
  }
}
