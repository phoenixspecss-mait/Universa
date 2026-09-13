import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:path_provider/path_provider.dart';
import 'package:universa/core/theme/app_colors.dart';
import 'package:universa/core/theme/app_typography.dart';
import 'package:universa/core/widgets/surveillance_frame.dart';
import 'package:universa/core/widgets/status_pill.dart';
import 'package:universa/core/widgets/hash_display.dart';
import 'package:universa/data/providers.dart';
import 'package:universa/data/models/report_model.dart';
import 'package:universa/data/models/ai_detection_model.dart';

class ReportScreen extends ConsumerWidget {
  final String caseId;

  const ReportScreen({
    super.key,
    required this.caseId,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reportAsync = ref.watch(reportProvider(caseId));
    final aiAsync = ref.watch(aiSummaryProvider(caseId));

    return reportAsync.when(
      loading: () => const _ReportLoading(),
      error: (err, _) => _ReportError(error: err.toString(), onRetry: () => ref.invalidate(reportProvider(caseId))),
      data: (report) => _ReportBody(
        caseId: caseId,
        report: report,
        aiAsync: aiAsync,
      ),
    );
  }
}

// ──────────────────────────── States ────────────────────────────────────────

class _ReportLoading extends StatelessWidget {
  const _ReportLoading();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: List.generate(
        4,
        (i) => Container(
          height: 80,
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.borderLight),
          ),
        ).animate(onPlay: (c) => c.repeat()).shimmer(
              color: AppColors.surfaceLight,
              duration: 1200.ms,
              delay: (i * 100).ms,
            ),
      ),
    );
  }
}

class _ReportError extends StatelessWidget {
  final String error;
  final VoidCallback onRetry;
  const _ReportError({required this.error, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: AppColors.error, size: 48),
            const SizedBox(height: 16),
            Text('Report unavailable', style: AppTypography.bodyLarge.copyWith(color: AppColors.textPrimary)),
            const SizedBox(height: 8),
            Text(error, style: AppTypography.bodySmall.copyWith(color: AppColors.textMuted), textAlign: TextAlign.center),
            const SizedBox(height: 20),
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh, size: 16, color: AppColors.electricCyan),
              label: Text('Retry', style: AppTypography.bodySmall.copyWith(color: AppColors.electricCyan)),
              style: OutlinedButton.styleFrom(side: const BorderSide(color: AppColors.electricCyan)),
            ),
          ],
        ),
      ),
    );
  }
}

// ──────────────────────────── Body ──────────────────────────────────────────

class _ReportBody extends ConsumerWidget {
  final String caseId;
  final ReportModel report;
  final AsyncValue<List<AiDetectionModel>> aiAsync;

  const _ReportBody({
    required this.caseId,
    required this.report,
    required this.aiAsync,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildHeroCard(report).animate().fadeIn(duration: 400.ms),
                _buildEvidenceGallery(report, context),
                _buildAiSummarySection(aiAsync),
                _buildChainOfCustody(report),
                _buildDetectionLog(report),
                _buildFormatLog(report),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
        _buildBottomBar(context, ref),
      ],
    );
  }

  // ─────────────────── Hero card ───────────────────────────────────

  Widget _buildHeroCard(ReportModel report) {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surfaceLight,
        border: Border.all(color: AppColors.borderLight),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  report.caseId,
                  style: AppTypography.monoLarge.copyWith(fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              StatusPill(
                label: report.isHashVerified ? 'Hash Verified' : 'Chain Failed',
                status: report.isHashVerified ? StatusType.verified : StatusType.flagged,
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(child: _metaField('Investigator', report.investigator)),
              Expanded(child: _metaField('Generated', report.dateRange)),
            ],
          ),
          if (report.detectedBrand.isNotEmpty) ...[
            const SizedBox(height: 6),
            _metaField('Detected Brand', report.detectedBrand),
          ],
          const SizedBox(height: 14),
          if (report.sha256Hash.isNotEmpty) HashDisplay(hash: report.sha256Hash, compact: false),
          const SizedBox(height: 10),
          Row(
            children: [
              _buildMiniBadge('Findings: ${report.findings.length}', AppColors.electricCyan),
              const SizedBox(width: 8),
              _buildMiniBadge('Detections: ${report.detectionLog.length}', AppColors.rustAmberLight),
              const SizedBox(width: 8),
              _buildMiniBadge('Log Entries: ${report.custodyLog.length}', AppColors.tealGreen),
            ],
          ),
        ],
      ),
    );
  }

  Widget _metaField(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: AppTypography.bodySmall.copyWith(color: AppColors.textMuted)),
        const SizedBox(height: 2),
        Text(value, style: AppTypography.bodyMedium.copyWith(color: AppColors.textPrimary)),
      ],
    );
  }

  Widget _buildMiniBadge(String text, Color dotColor) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.borderLight),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 6, height: 6, decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle)),
          const SizedBox(width: 4),
          Text(text, style: AppTypography.monoSmall.copyWith(color: AppColors.textSecondary)),
        ],
      ),
    );
  }

  // ─────────────────── Evidence Gallery ───────────────────────────

  Widget _buildEvidenceGallery(ReportModel report, BuildContext context) {
    if (report.findings.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
          child: Row(
            children: [
              const Icon(Icons.photo_library, color: AppColors.electricCyan, size: 20),
              const SizedBox(width: 8),
              Text('EVIDENCE GALLERY', style: AppTypography.labelSmall.copyWith(color: AppColors.textSecondary)),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(color: AppColors.surfaceLight, borderRadius: BorderRadius.circular(10)),
                child: Text('${report.findings.length}', style: AppTypography.monoSmall.copyWith(color: AppColors.textPrimary)),
              ),
            ],
          ),
        ),
        SizedBox(
          height: 140,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: report.findings.length,
            itemBuilder: (context, index) {
              final finding = report.findings[index];
              return Container(
                width: 200,
                margin: const EdgeInsets.only(right: 10),
                child: SurveillanceFrame(
                  cameraName: finding.cameraName,
                  timestamp: finding.timestamp,
                  confidence: finding.confidence,
                  objectLabel: finding.objectType,
                  variant: index % 6,
                  showHud: true,
                  showBoundingBox: true,
                  isCarved: false,
                  onTap: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Viewing evidence ${index + 1}')),
                    );
                  },
                ),
              );
            },
          ),
        ).animate().fadeIn(duration: 400.ms).slideX(begin: 0.1, end: 0, duration: 400.ms),
      ],
    );
  }

  // ─────────────────── AI Summary ─────────────────────────────────

  Widget _buildAiSummarySection(AsyncValue<List<AiDetectionModel>> aiAsync) {
    return aiAsync.when(
      loading: () => Container(
        height: 60,
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.borderLight),
        ),
      ).animate(onPlay: (c) => c.repeat()).shimmer(color: AppColors.surfaceLight, duration: 1200.ms),
      error: (_, __) => const SizedBox.shrink(),
      data: (detections) {
        if (detections.isEmpty) return const SizedBox.shrink();

        final totalDetections = detections.fold<int>(0, (sum, d) => sum + d.totalDetections);
        final allClasses = detections.expand((d) => d.distinctClasses).toSet().toList();

        return Card(
          color: AppColors.surface,
          margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: const BorderSide(color: AppColors.borderLight),
          ),
          child: Theme(
            data: ThemeData(dividerColor: Colors.transparent),
            child: ExpansionTile(
              initiallyExpanded: true,
              iconColor: AppColors.textPrimary,
              collapsedIconColor: AppColors.textSecondary,
              title: Row(
                children: [
                  const Icon(Icons.psychology, color: AppColors.rustAmberLight, size: 20),
                  const SizedBox(width: 8),
                  Text('AI Object Detection', style: AppTypography.bodyLarge.copyWith(color: AppColors.textPrimary, fontWeight: FontWeight.bold)),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppColors.rustAmber.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text('$totalDetections detections',
                        style: AppTypography.monoSmall.copyWith(color: AppColors.rustAmberLight)),
                  ),
                ],
              ),
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (allClasses.isNotEmpty) ...[
                        Text('Detected classes:', style: AppTypography.bodySmall.copyWith(color: AppColors.textMuted)),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 6,
                          children: allClasses.map((cls) => Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: AppColors.rustAmber.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: AppColors.rustAmber.withValues(alpha: 0.4)),
                            ),
                            child: Text(cls, style: AppTypography.monoSmall.copyWith(color: AppColors.rustAmberLight)),
                          )).toList(),
                        ),
                        const SizedBox(height: 12),
                      ],
                      ...detections.map((det) => Container(
                        margin: const EdgeInsets.only(bottom: 6),
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: AppColors.surfaceLight,
                          border: Border.all(color: AppColors.borderLight),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.videocam, color: AppColors.textMuted, size: 16),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                det.clipPath.split('/').last,
                                style: AppTypography.monoSmall.copyWith(color: AppColors.textSecondary),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              '${det.totalDetections} obj',
                              style: AppTypography.monoSmall.copyWith(color: AppColors.rustAmberLight),
                            ),
                          ],
                        ),
                      )),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ).animate().fadeIn(duration: 400.ms);
      },
    );
  }

  // ─────────────────── Chain of Custody ───────────────────────────

  Widget _buildChainOfCustody(ReportModel report) {
    return Card(
      color: AppColors.surface,
      margin: const EdgeInsets.all(16),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: AppColors.borderLight),
      ),
      child: Theme(
        data: ThemeData(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: true,
          iconColor: AppColors.textPrimary,
          collapsedIconColor: AppColors.textSecondary,
          title: Row(
            children: [
              const Icon(Icons.link, color: AppColors.emerald, size: 20),
              const SizedBox(width: 8),
              Text('Chain of Custody', style: AppTypography.bodyLarge.copyWith(color: AppColors.textPrimary, fontWeight: FontWeight.bold)),
            ],
          ),
          children: [
            if (report.custodyLog.isEmpty)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text('No custody entries.', style: TextStyle(color: AppColors.textMuted)),
              )
            else
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: Column(
                  children: List.generate(report.custodyLog.length, (index) {
                    final entry = report.custodyLog[index];
                    final isLast = index == report.custodyLog.length - 1;
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Column(
                          children: [
                            Container(
                              width: 10,
                              height: 10,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(color: AppColors.emerald, width: 2),
                              ),
                            ),
                            if (!isLast) Container(width: 2, height: 40, color: AppColors.emerald),
                          ],
                        ),
                        Expanded(
                          child: Container(
                            margin: const EdgeInsets.only(left: 12, bottom: 8),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: AppColors.surfaceLight,
                              border: Border.all(color: AppColors.borderLight),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(entry.action, style: AppTypography.bodySmall.copyWith(color: AppColors.textPrimary, fontWeight: FontWeight.bold)),
                                const SizedBox(height: 2),
                                Text(entry.timestamp, style: AppTypography.monoSmall.copyWith(color: AppColors.textMuted)),
                                const SizedBox(height: 4),
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(entry.actor,
                                          style: AppTypography.monoSmall.copyWith(color: AppColors.textMuted),
                                          overflow: TextOverflow.ellipsis),
                                    ),
                                    if (entry.hash.isNotEmpty)
                                      Text(
                                        entry.hash.length > 12 ? entry.hash.substring(0, 12) : entry.hash,
                                        style: AppTypography.monoSmall.copyWith(color: AppColors.textMuted),
                                      ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ).animate().fadeIn(delay: (index * 100).ms).slideX(begin: 0.1, end: 0);
                  }),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ─────────────────── Detection log ──────────────────────────────

  Widget _buildDetectionLog(ReportModel report) {
    if (report.detectionLog.isEmpty) return const SizedBox.shrink();
    return Card(
      color: AppColors.surface,
      margin: const EdgeInsets.symmetric(horizontal: 16),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: AppColors.borderLight),
      ),
      child: Theme(
        data: ThemeData(dividerColor: Colors.transparent),
        child: ExpansionTile(
          iconColor: AppColors.textPrimary,
          collapsedIconColor: AppColors.textSecondary,
          title: Row(
            children: [
              const Icon(Icons.smart_toy_outlined, color: AppColors.rustAmberLight, size: 20),
              const SizedBox(width: 8),
              Text('Extracted Clips', style: AppTypography.bodyLarge.copyWith(color: AppColors.textPrimary, fontWeight: FontWeight.bold)),
            ],
          ),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(
                children: report.detectionLog.map((entry) {
                  return Container(
                    margin: const EdgeInsets.only(bottom: 6),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceLight,
                      border: Border.all(color: AppColors.borderLight),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.video_file, color: AppColors.textSecondary, size: 20),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(entry.cameraName.split('/').last,
                                  style: AppTypography.bodySmall.copyWith(color: AppColors.textPrimary)),
                              const SizedBox(height: 2),
                              Text(entry.timestamp, style: AppTypography.monoSmall.copyWith(color: AppColors.textMuted)),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: AppColors.emerald.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text('Valid', style: AppTypography.monoSmall.copyWith(color: AppColors.emerald)),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─────────────────── Format log ─────────────────────────────────

  Widget _buildFormatLog(ReportModel report) {
    return Card(
      color: AppColors.surface,
      margin: const EdgeInsets.all(16),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: AppColors.borderLight),
      ),
      child: Theme(
        data: ThemeData(dividerColor: Colors.transparent),
        child: ExpansionTile(
          iconColor: AppColors.textPrimary,
          collapsedIconColor: AppColors.textSecondary,
          title: Row(
            children: [
              const Icon(Icons.terminal, color: AppColors.textSecondary, size: 20),
              const SizedBox(width: 8),
              Text('Analysis Log', style: AppTypography.bodyLarge.copyWith(color: AppColors.textPrimary, fontWeight: FontWeight.bold)),
            ],
          ),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.canvasBlack,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: List.generate(report.formatLog.length, (index) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text(
                        report.formatLog[index],
                        style: AppTypography.monoSmall.copyWith(color: AppColors.emerald, fontSize: 10),
                      ),
                    ).animate().fadeIn(delay: (index * 150).ms);
                  }),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─────────────────── Bottom bar ─────────────────────────────────

  Widget _buildBottomBar(BuildContext context, WidgetRef ref) {
    return Container(
      color: AppColors.surface,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton.icon(
                  onPressed: () => _downloadPdf(context, ref),
                  icon: const Icon(Icons.lock, color: AppColors.background),
                  label: Text(
                    'Export Signed Report (PDF)',
                    style: AppTypography.bodyMedium.copyWith(color: AppColors.background, fontWeight: FontWeight.bold),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.emerald,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {},
                      icon: const Icon(Icons.gavel, color: AppColors.emerald, size: 18),
                      label: Text('Add to Court Dossier', style: AppTypography.bodySmall.copyWith(color: AppColors.emerald)),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: AppColors.emerald),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _downloadJson(context, ref),
                      icon: const Icon(Icons.data_object, color: AppColors.textSecondary, size: 18),
                      label: Text('JSON Export', style: AppTypography.bodySmall.copyWith(color: AppColors.textSecondary)),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: AppColors.textMuted),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _downloadPdf(BuildContext context, WidgetRef ref) async {
    try {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Downloading PDF…')),
      );
      final apiClient = ref.read(apiClientProvider);
      final bytes = await apiClient.fetchReportPdf(caseId);
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/$caseId-report.pdf');
      await file.writeAsBytes(Uint8List.fromList(bytes));
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppColors.emerald,
          content: Text('PDF saved to ${file.path}', style: AppTypography.bodySmall.copyWith(color: AppColors.background)),
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppColors.error,
          content: Text('Export failed: $e', style: AppTypography.bodySmall.copyWith(color: AppColors.white)),
        ),
      );
    }
  }

  Future<void> _downloadJson(BuildContext context, WidgetRef ref) async {
    try {
      final apiClient = ref.read(apiClientProvider);
      final json = await apiClient.fetchReportJson(caseId);
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/$caseId-report.json');
      await file.writeAsString(json);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppColors.emerald,
          content: Text('JSON saved to ${file.path}', style: AppTypography.bodySmall.copyWith(color: AppColors.background)),
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppColors.error,
          content: Text('Export failed: $e', style: AppTypography.bodySmall.copyWith(color: AppColors.white)),
        ),
      );
    }
  }
}
