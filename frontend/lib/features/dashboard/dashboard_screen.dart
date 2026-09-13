import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:percent_indicator/percent_indicator.dart';
import 'package:file_picker/file_picker.dart';

import 'package:universa/core/theme/app_colors.dart';
import 'package:universa/core/theme/app_typography.dart';
import 'package:universa/core/widgets/surveillance_frame.dart';
import 'package:universa/core/widgets/status_pill.dart';
import 'package:universa/core/widgets/pipeline_stepper.dart';
import 'package:universa/data/providers.dart';
import 'package:universa/data/models/case_model.dart';
import 'package:universa/data/api/upload_notifier.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  StatusType _mapCaseStatus(CaseStatus status) {
    switch (status) {
      case CaseStatus.hashVerified:
        return StatusType.verified;
      case CaseStatus.aiTriage:
        return StatusType.processing;
      case CaseStatus.processing:
        return StatusType.processing;
      case CaseStatus.inProgress:
        return StatusType.active;
      case CaseStatus.flagged:
        return StatusType.flagged;
    }
  }

  String _mapCaseStatusLabel(CaseStatus status) {
    switch (status) {
      case CaseStatus.hashVerified:
        return 'Hash Verified';
      case CaseStatus.aiTriage:
        return 'AI Triage';
      case CaseStatus.processing:
        return 'Processing';
      case CaseStatus.inProgress:
        return 'In Progress';
      case CaseStatus.flagged:
        return 'Flagged';
    }
  }

  String _relativeTime(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inSeconds < 60) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final casesAsync = ref.watch(casesProvider);
    final stats = ref.watch(dashboardStatsProvider);
    final upload = ref.watch(uploadProvider);

    return Stack(
      children: [
        RefreshIndicator(
          color: AppColors.electricCyan,
          backgroundColor: AppColors.surface,
          onRefresh: () async => ref.invalidate(casesProvider),
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              // 1. Navigation mode switcher
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16.0),
                  child: SizedBox(
                    height: 70,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 16.0),
                      children: [
                        _ModeCard(
                          label: 'Spatial Canvas',
                          icon: Icons.hub,
                          accentColor: AppColors.electricCyan,
                          onTap: () => context.go('/canvas'),
                          selected: false,
                        ),
                        const SizedBox(width: 12),
                        _ModeCard(
                          label: 'Studio Pro',
                          icon: Icons.play_circle,
                          accentColor: AppColors.emerald,
                          onTap: () => context.go('/studio'),
                          selected: false,
                        ),
                        const SizedBox(width: 12),
                        _ModeCard(
                          label: 'AI Triage',
                          icon: Icons.auto_awesome,
                          accentColor: AppColors.rustAmberLight,
                          onTap: () {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Coming soon')),
                            );
                          },
                          selected: false,
                        ),
                      ].animate(interval: 50.ms).fadeIn().slideY(begin: 0.2),
                    ),
                  ),
                ),
              ),

              // 2. Stats row (live)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 24.0),
                  child: SizedBox(
                    height: 110,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 16.0),
                      children: [
                        _StatCard(
                          label: 'Active Cases',
                          value: '${stats['activeCases']}',
                          accentColor: AppColors.primaryNavyLight,
                          percent: null,
                        ),
                        const SizedBox(width: 12),
                        _StatCard(
                          label: 'Hash Verified',
                          value: '${stats['hashVerifiedCases']}',
                          accentColor: AppColors.emerald,
                          percent: casesAsync.maybeWhen(
                            data: (cases) {
                              if (cases.isEmpty) return null;
                              return (stats['hashVerifiedCases'] as int) / cases.length;
                            },
                            orElse: () => null,
                          ),
                        ),
                        const SizedBox(width: 12),
                        _StatCard(
                          label: 'Pending AI Triage',
                          value: '${stats['pendingAiTriage']}',
                          accentColor: AppColors.rustAmber,
                          percent: null,
                        ),
                        const SizedBox(width: 12),
                        _StatCard(
                          label: 'Total Uploaded',
                          value: casesAsync.maybeWhen(
                            data: (cases) => '${cases.length}',
                            orElse: () => '—',
                          ),
                          accentColor: AppColors.tealGreen,
                          percent: null,
                        ),
                      ].animate(interval: 100.ms).fadeIn().scale(),
                    ),
                  ),
                ),
              ),

              // 3. Live AI Feed
              SliverToBoxAdapter(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                      child: Row(
                        children: [
                          const Icon(Icons.auto_awesome, color: AppColors.electricCyan, size: 16),
                          const SizedBox(width: 8),
                          Text(
                            'LIVE AI FEED',
                            style: AppTypography.labelSmall.copyWith(color: AppColors.textPrimary),
                          ),
                          const SizedBox(width: 8),
                          Container(width: 4, height: 4, decoration: const BoxDecoration(color: AppColors.textMuted, shape: BoxShape.circle)),
                          const SizedBox(width: 8),
                          Text(
                            'Last 24h',
                            style: AppTypography.labelSmall.copyWith(color: AppColors.textMuted),
                          ),
                        ],
                      ),
                    ),
                    SizedBox(
                      height: 140,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 16.0),
                        children: [
                          _buildFeedFrame(context, cameraName: 'CAM-03 East Gate', confidence: 96.8, variant: 0),
                          _buildFeedFrame(context, cameraName: 'CAM-07 Corridor', confidence: 94.2, variant: 1),
                          _buildFeedFrame(context, cameraName: 'CAM-12 Service Bay', confidence: 88.1, variant: 2),
                          _buildFeedFrame(context, cameraName: 'CAM-04 Parking', confidence: 91.5, variant: 3),
                        ].animate(interval: 100.ms).fadeIn().slideX(begin: 0.1),
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],
                ),
              ),

              // 4. Cases section header
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                  child: Row(
                    children: [
                      Text(
                        'Cases',
                        style: AppTypography.headlineSmall.copyWith(color: AppColors.textPrimary),
                      ),
                      const SizedBox(width: 12),
                      casesAsync.when(
                        data: (cases) => _CountBadge(count: cases.length),
                        loading: () => const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.electricCyan)),
                        error: (_, __) => const SizedBox.shrink(),
                      ),
                      const Spacer(),
                      // Refresh button
                      GestureDetector(
                        onTap: () => ref.invalidate(casesProvider),
                        child: const Icon(Icons.refresh, color: AppColors.textMuted, size: 18),
                      ),
                    ],
                  ),
                ),
              ),

              // 5. Cases list
              casesAsync.when(
                data: (cases) => cases.isEmpty
                    ? SliverToBoxAdapter(child: _buildEmptyState(context))
                    : SliverList.builder(
                        itemCount: cases.length,
                        itemBuilder: (context, index) {
                          final caseItem = cases[index];
                          return _CaseListItem(
                            caseItem: caseItem,
                            index: index,
                            statusType: _mapCaseStatus(caseItem.status),
                            statusLabel: _mapCaseStatusLabel(caseItem.status),
                            relativeTime: _relativeTime(caseItem.lastUpdated),
                            onTap: () => context.push('/report/${caseItem.id}'),
                          );
                        },
                      ),
                loading: () => SliverList.builder(
                  itemCount: 4,
                  itemBuilder: (_, i) => const _SkeletonCaseCard(),
                ),
                error: (err, _) => SliverToBoxAdapter(
                  child: _buildErrorState(context, err.toString(), () => ref.invalidate(casesProvider)),
                ),
              ),

              const SliverToBoxAdapter(child: SizedBox(height: 100)),
            ],
          ),
        ),

        // Upload progress overlay
        if (upload.status == UploadStatus.uploading)
          Positioned(
            bottom: 90,
            left: 16,
            right: 16,
            child: _UploadProgressBanner(progress: upload.progress),
          ),

        // FAB
        Positioned(
          bottom: 24,
          right: 20,
          child: FloatingActionButton.extended(
            backgroundColor: AppColors.electricCyan,
            foregroundColor: AppColors.background,
            icon: const Icon(Icons.upload_file),
            label: Text(
              'New Case',
              style: AppTypography.labelSmall.copyWith(
                color: AppColors.background,
                fontWeight: FontWeight.bold,
              ),
            ),
            onPressed: upload.status == UploadStatus.uploading
                ? null
                : () => _showUploadSheet(context, ref),
          ).animate().scale(delay: 300.ms),
        ),
      ],
    );
  }

  Widget _buildFeedFrame(BuildContext context, {required String cameraName, required double confidence, required int variant}) {
    return Container(
      width: 220,
      margin: const EdgeInsets.only(right: 10.0),
      child: SurveillanceFrame(
        cameraName: cameraName,
        timestamp: 'LIVE',
        confidence: confidence,
        objectLabel: 'Subject',
        boundingBoxColor: AppColors.electricCyan,
        showHud: true,
        showBoundingBox: true,
        isCarved: false,
        variant: variant,
        onTap: () => context.push('/search'),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(24),
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.borderLight),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          const Icon(Icons.folder_open, color: AppColors.textMuted, size: 48),
          const SizedBox(height: 16),
          Text('No Cases Yet', style: AppTypography.headlineSmall.copyWith(color: AppColors.textPrimary)),
          const SizedBox(height: 8),
          Text(
            'Tap "New Case" to upload a disk image and start forensic analysis.',
            style: AppTypography.bodySmall.copyWith(color: AppColors.textMuted),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    ).animate().fadeIn();
  }

  Widget _buildErrorState(BuildContext context, String error, VoidCallback onRetry) {
    return Container(
      margin: const EdgeInsets.all(24),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.error.withValues(alpha: 0.4)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          const Icon(Icons.wifi_off, color: AppColors.error, size: 40),
          const SizedBox(height: 12),
          Text('Server Unreachable', style: AppTypography.bodyLarge.copyWith(color: AppColors.textPrimary)),
          const SizedBox(height: 6),
          Text(
            'Start the API server (./dvr_api_server) and pull to refresh.',
            style: AppTypography.bodySmall.copyWith(color: AppColors.textMuted),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh, size: 16, color: AppColors.electricCyan),
            label: Text('Retry', style: AppTypography.bodySmall.copyWith(color: AppColors.electricCyan)),
            style: OutlinedButton.styleFrom(side: const BorderSide(color: AppColors.electricCyan)),
          ),
        ],
      ),
    );
  }

  Future<void> _showUploadSheet(BuildContext context, WidgetRef ref) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.any,
      allowMultiple: false,
    );

    if (result == null || result.files.single.path == null) return;
    final filePath = result.files.single.path!;

    if (!context.mounted) return;
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      isDismissible: false,
      builder: (_) => _UploadSheet(filePath: filePath),
    );

    final notifier = ref.read(uploadProvider.notifier);
    final report = await notifier.upload(filePath);

    if (!context.mounted) return;
    Navigator.of(context, rootNavigator: true).pop();

    if (report != null) {
      ref.invalidate(casesProvider);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppColors.emerald,
          content: Text('Analysis complete: ${report.caseId}',
              style: AppTypography.bodySmall.copyWith(color: AppColors.background)),
          action: SnackBarAction(
            label: 'View',
            textColor: AppColors.background,
            onPressed: () => context.push('/report/${report.caseId}'),
          ),
        ),
      );
    }
    notifier.reset();
  }
}

// ─────────────────────────── Sub-widgets ────────────────────────────────────

class _CountBadge extends StatelessWidget {
  final int count;
  const _CountBadge({required this.count});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.surfaceLight,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.borderLight),
      ),
      child: Text(
        '$count',
        style: AppTypography.labelSmall.copyWith(color: AppColors.textPrimary),
      ),
    );
  }
}

class _CaseListItem extends StatelessWidget {
  final CaseModel caseItem;
  final int index;
  final StatusType statusType;
  final String statusLabel;
  final String relativeTime;
  final VoidCallback onTap;

  const _CaseListItem({
    required this.caseItem,
    required this.index,
    required this.statusType,
    required this.statusLabel,
    required this.relativeTime,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 5.0),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.borderLight),
        borderRadius: BorderRadius.circular(10),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      caseItem.id,
                      style: AppTypography.mono.copyWith(color: AppColors.electricCyan),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  StatusPill(status: statusType, label: statusLabel),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                caseItem.title,
                style: AppTypography.bodyMedium.copyWith(color: AppColors.textPrimary),
              ),
              const SizedBox(height: 10),
              PipelineStepper(currentStage: caseItem.pipelineStage),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '$relativeTime • ${caseItem.evidenceSource}',
                      style: AppTypography.labelSmall.copyWith(color: AppColors.textMuted),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  SizedBox(
                    width: 60,
                    height: 34,
                    child: SurveillanceFrame(
                      cameraName: 'thumb',
                      timestamp: 'now',
                      confidence: 0,
                      objectLabel: '',
                      boundingBoxColor: Colors.transparent,
                      showHud: false,
                      showBoundingBox: false,
                      isCarved: false,
                      variant: index % 6,
                      onTap: () {},
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    ).animate().fadeIn(delay: (index * 50).ms).slideY(begin: 0.1);
  }
}

class _SkeletonCaseCard extends StatelessWidget {
  const _SkeletonCaseCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 120,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.borderLight),
        borderRadius: BorderRadius.circular(10),
      ),
    ).animate(onPlay: (c) => c.repeat()).shimmer(
          color: AppColors.surfaceLight,
          duration: 1200.ms,
        );
  }
}

class _ModeCard extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color accentColor;
  final VoidCallback onTap;
  final bool selected;

  const _ModeCard({
    required this.label,
    required this.icon,
    required this.accentColor,
    required this.onTap,
    required this.selected,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 150,
        height: 70,
        decoration: BoxDecoration(
          color: AppColors.surfaceLight,
          border: Border.all(
            color: selected ? accentColor : AppColors.border,
            width: selected ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 24, color: accentColor),
            const SizedBox(height: 6),
            Text(label, style: AppTypography.labelSmall.copyWith(color: AppColors.textPrimary)),
          ],
        ),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final Color accentColor;
  final double? percent;

  const _StatCard({
    required this.label,
    required this.value,
    required this.accentColor,
    this.percent,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 170,
      padding: const EdgeInsets.all(14.0),
      decoration: BoxDecoration(
        color: AppColors.surfaceLight,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: AppTypography.labelSmall.copyWith(color: AppColors.textMuted)),
          const Spacer(),
          Row(
            children: [
              Text(value, style: AppTypography.headlineLarge.copyWith(color: accentColor)),
              const Spacer(),
              if (percent != null)
                CircularPercentIndicator(
                  radius: 20.0,
                  lineWidth: 3.0,
                  percent: percent!.clamp(0.0, 1.0),
                  center: Text(
                    '${(percent! * 100).round()}%',
                    style: AppTypography.labelSmall.copyWith(color: AppColors.textPrimary, fontSize: 9),
                  ),
                  progressColor: accentColor,
                  backgroundColor: AppColors.canvasBlack,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _UploadProgressBanner extends StatelessWidget {
  final double progress;
  const _UploadProgressBanner({required this.progress});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.surfaceLight,
        border: Border.all(color: AppColors.electricCyan.withValues(alpha: 0.5)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.upload, color: AppColors.electricCyan, size: 16),
              const SizedBox(width: 8),
              Text('Uploading disk image…', style: AppTypography.bodySmall.copyWith(color: AppColors.textPrimary)),
              const Spacer(),
              Text('${(progress * 100).round()}%', style: AppTypography.monoSmall.copyWith(color: AppColors.electricCyan)),
            ],
          ),
          const SizedBox(height: 8),
          LinearProgressIndicator(
            value: progress,
            backgroundColor: AppColors.border,
            color: AppColors.electricCyan,
            minHeight: 3,
            borderRadius: BorderRadius.circular(2),
          ),
        ],
      ),
    ).animate().fadeIn().slideY(begin: 0.3);
  }
}

class _UploadSheet extends ConsumerWidget {
  final String filePath;
  const _UploadSheet({required this.filePath});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final upload = ref.watch(uploadProvider);
    final fileName = filePath.split('/').last;

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 40),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.analytics, color: AppColors.electricCyan),
              const SizedBox(width: 10),
              Text('Forensic Analysis', style: AppTypography.bodyLarge.copyWith(color: AppColors.textPrimary, fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.surfaceLight,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.borderLight),
            ),
            child: Row(
              children: [
                const Icon(Icons.storage, color: AppColors.textMuted, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(fileName, style: AppTypography.mono.copyWith(color: AppColors.textPrimary), overflow: TextOverflow.ellipsis),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          if (upload.status == UploadStatus.uploading) ...[
            Row(
              children: [
                Text('Uploading…', style: AppTypography.bodySmall.copyWith(color: AppColors.textMuted)),
                const Spacer(),
                Text('${(upload.progress * 100).round()}%', style: AppTypography.monoSmall.copyWith(color: AppColors.electricCyan)),
              ],
            ),
            const SizedBox(height: 8),
            LinearProgressIndicator(
              value: upload.progress,
              backgroundColor: AppColors.border,
              color: AppColors.electricCyan,
              minHeight: 4,
              borderRadius: BorderRadius.circular(2),
            ),
            const SizedBox(height: 12),
            Text(
              'Running file carving, AI detection,\nchain-of-custody generation…',
              style: AppTypography.bodySmall.copyWith(color: AppColors.textMuted),
            ),
          ],
          if (upload.status == UploadStatus.error) ...[
            const Icon(Icons.error_outline, color: AppColors.error, size: 32),
            const SizedBox(height: 8),
            Text(upload.errorMessage ?? 'Unknown error',
                style: AppTypography.bodySmall.copyWith(color: AppColors.error)),
          ],
        ],
      ),
    );
  }
}
