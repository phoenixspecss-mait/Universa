enum CaseStatus { aiTriage, hashVerified, processing, inProgress, flagged }

class CaseModel {
  final String id;
  final String title;
  final CaseStatus status;
  final int pipelineStage;
  final String evidenceSource;
  final String oemFormat;
  final DateTime lastUpdated;
  final String sha256Hash;
  final String investigator;
  final DateTime startDate;
  final DateTime endDate;
  final int totalFrames;
  final int detectionCount;

  const CaseModel({
    required this.id,
    required this.title,
    required this.status,
    required this.pipelineStage,
    required this.evidenceSource,
    required this.oemFormat,
    required this.lastUpdated,
    required this.sha256Hash,
    required this.investigator,
    required this.startDate,
    required this.endDate,
    required this.totalFrames,
    required this.detectionCount,
  });

  /// Construct from the `case_meta.json` shape produced by the C++ backend.
  factory CaseModel.fromJson(Map<String, dynamic> json) {
    final statusStr = (json['status'] as String?)?.toUpperCase() ?? 'SUCCESS';
    final chainVerified = json['chain_verified'] as bool? ?? false;
    final validClips = (json['valid_clips'] as num?)?.toInt() ?? 0;
    final carvedChunks = (json['carved_chunks'] as num?)?.toInt() ?? 0;

    CaseStatus status;
    int pipelineStage;
    if (statusStr == 'SUCCESS' && chainVerified) {
      status = CaseStatus.hashVerified;
      pipelineStage = 5;
    } else if (statusStr == 'SUCCESS') {
      status = CaseStatus.aiTriage;
      pipelineStage = 4;
    } else if (statusStr == 'PROCESSING') {
      status = CaseStatus.processing;
      pipelineStage = 2;
    } else {
      status = CaseStatus.inProgress;
      pipelineStage = 3;
    }

    DateTime createdAt;
    try {
      createdAt = DateTime.parse(json['created_at'] as String? ?? '');
    } catch (_) {
      createdAt = DateTime.now();
    }

    return CaseModel(
      id: json['case_id'] as String? ?? 'UNKNOWN',
      title: json['source_filename'] as String? ?? 'Untitled Case',
      status: status,
      pipelineStage: pipelineStage,
      evidenceSource: json['source_filename'] as String? ?? 'Unknown Source',
      oemFormat: 'Raw Disk Image',
      lastUpdated: createdAt,
      sha256Hash: json['source_file_hash'] as String? ?? '',
      investigator: 'UNIVERSA System',
      startDate: createdAt,
      endDate: createdAt,
      totalFrames: carvedChunks,
      detectionCount: validClips,
    );
  }
}
