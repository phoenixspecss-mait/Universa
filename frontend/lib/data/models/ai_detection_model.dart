/// Represents the AI object-detection summary for a single carved clip,
/// as returned by `GET /api/cases/:id/ai_summary`.
class AiDetectionModel {
  final String clipPath;
  final int totalDetections;
  final List<String> distinctClasses;

  const AiDetectionModel({
    required this.clipPath,
    required this.totalDetections,
    required this.distinctClasses,
  });

  factory AiDetectionModel.fromJson(Map<String, dynamic> json) {
    final classes = (json['distinct_classes'] as List<dynamic>?)
            ?.map((e) => e.toString())
            .toList() ??
        [];
    return AiDetectionModel(
      clipPath: json['clip_path'] as String? ?? '',
      totalDetections: (json['total_detections'] as num?)?.toInt() ?? 0,
      distinctClasses: classes,
    );
  }
}
