import 'package:flutter/material.dart';
import 'package:universa/core/theme/app_colors.dart';
import 'package:universa/core/theme/app_typography.dart';
import 'package:universa/core/widgets/status_pill.dart';
import 'package:universa/core/widgets/pipeline_stepper.dart';

/// A card for summarizing a case.
class CaseCard extends StatelessWidget {
  final String caseId;
  final String title;
  final StatusType status;
  final int currentStage;
  final String evidenceSource;
  final String oemFormat;
  final String lastUpdated;
  final VoidCallback? onTap;

  const CaseCard({
    super.key,
    required this.caseId,
    required this.title,
    required this.status,
    required this.currentStage,
    required this.evidenceSource,
    required this.oemFormat,
    required this.lastUpdated,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      color: AppColors.surface,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: AppColors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        hoverColor: Colors.white.withValues(alpha: 0.05),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      caseId,
                      style: AppTypography.monoSmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  StatusPill(
                    label: status.name.toUpperCase(),
                    status: status,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                title,
                style: AppTypography.bodyMedium,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 12),
              PipelineStepper(currentStage: currentStage),
              const SizedBox(height: 12),
              Text(
                '$evidenceSource • $oemFormat • $lastUpdated',
                style: AppTypography.labelSmall.copyWith(color: AppColors.textMuted),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
