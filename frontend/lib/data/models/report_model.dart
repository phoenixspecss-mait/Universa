import 'package:universa/data/models/search_result_model.dart';

class CustodyEntry {
  final String timestamp;
  final String action;
  final String actor;
  final String hash;

  const CustodyEntry({
    required this.timestamp,
    required this.action,
    required this.actor,
    required this.hash,
  });

  factory CustodyEntry.fromJson(Map<String, dynamic> json) {
    return CustodyEntry(
      timestamp: json['timestamp'] as String? ?? '',
      action: json['action'] as String? ?? '',
      actor: json['actor'] as String? ?? 'System',
      hash: json['hash_after'] as String? ?? json['hash_before'] as String? ?? '',
    );
  }
}

class DetectionEntry {
  final String objectType;
  final String timestamp;
  final double confidence;
  final String cameraName;

  const DetectionEntry({
    required this.objectType,
    required this.timestamp,
    required this.confidence,
    required this.cameraName,
  });

  factory DetectionEntry.fromJson(Map<String, dynamic> json) {
    return DetectionEntry(
      objectType: json['object_type'] as String? ?? 'Object',
      timestamp: json['timestamp'] as String? ?? '',
      confidence: (json['confidence'] as num?)?.toDouble() ?? 0.0,
      cameraName: json['camera_name'] as String? ?? 'Unknown',
    );
  }
}

class ReportModel {
  final String caseId;
  final String investigator;
  final String dateRange;
  final bool isHashVerified;
  final String sha256Hash;
  final String detectedBrand;
  final List<CustodyEntry> custodyLog;
  final List<DetectionEntry> detectionLog;
  final List<String> formatLog;
  final List<SearchResultModel> findings;

  const ReportModel({
    required this.caseId,
    required this.investigator,
    required this.dateRange,
    required this.isHashVerified,
    required this.sha256Hash,
    this.detectedBrand = '',
    required this.custodyLog,
    required this.detectionLog,
    required this.formatLog,
    required this.findings,
  });

  /// Construct from the `report.json` produced by the C++ ReportGenerator.
  factory ReportModel.fromJson(Map<String, dynamic> json) {
    // Chain of custody entries
    final custodyRaw = json['chain_of_custody'] as List<dynamic>? ?? [];
    final custodyEntries =
        custodyRaw.map((e) => CustodyEntry.fromJson(e as Map<String, dynamic>)).toList();

    // Detection log from clips array
    final clipsRaw = json['clips'] as List<dynamic>? ?? [];
    final detections = <DetectionEntry>[];
    for (final clip in clipsRaw) {
      final c = clip as Map<String, dynamic>;
      if (c['is_valid'] == true) {
        detections.add(DetectionEntry(
          objectType: 'Clip',
          timestamp: c['relative_timestamp'] as String? ??
              c['capture_window_start'] as String? ?? '',
          confidence: 1.0,
          cameraName: c['output_path'] as String? ?? '',
        ));
      }
    }

    // Format / decoding log lines
    final logLines = <String>[];
    logLines.add('Source: ${json['source_file'] ?? 'Unknown'}');
    logLines.add('Brand: ${json['detected_brand'] ?? 'Unknown'}');
    logLines.add('Hash: ${(json['source_file_hash'] as String? ?? '').substring(0, 16)}...');
    logLines.add('Generated: ${json['generated_at_utc'] ?? ''}');
    logLines.add('Chain verified: ${json['chain_verification_passed'] ?? false}');

    final generatedAt = json['generated_at_utc'] as String? ?? '';
    final caseId = json['case_id'] as String? ?? '';

    return ReportModel(
      caseId: caseId,
      investigator: 'UNIVERSA System',
      dateRange: generatedAt.isNotEmpty ? generatedAt : 'Unknown',
      isHashVerified: json['chain_verification_passed'] as bool? ?? false,
      sha256Hash: json['source_file_hash'] as String? ?? '',
      detectedBrand: json['detected_brand'] as String? ?? '',
      custodyLog: custodyEntries,
      detectionLog: detections,
      formatLog: logLines,
      findings: const [],
    );
  }
}
