import 'dart:ui';

class SearchResultModel {
  final String id;
  final String cameraName;
  final String timestamp;
  final double confidence;
  final String objectType;
  final String description;
  final Rect boundingBox;

  const SearchResultModel({
    required this.id,
    required this.cameraName,
    required this.timestamp,
    required this.confidence,
    required this.objectType,
    required this.description,
    required this.boundingBox,
  });

  factory SearchResultModel.fromJson(Map<String, dynamic> json) {
    Rect bbox = const Rect.fromLTWH(0.1, 0.1, 0.8, 0.8);
    if (json['boundingBox'] is Map) {
      final b = json['boundingBox'] as Map<String, dynamic>;
      final xmin = (b['xmin'] as num?)?.toDouble() ?? 0.0;
      final ymin = (b['ymin'] as num?)?.toDouble() ?? 0.0;
      final xmax = (b['xmax'] as num?)?.toDouble() ?? 1.0;
      final ymax = (b['ymax'] as num?)?.toDouble() ?? 1.0;
      bbox = Rect.fromLTRB(xmin, ymin, xmax, ymax);
    }

    return SearchResultModel(
      id: json['id']?.toString() ?? 'RES-UNKNOWN',
      cameraName: json['cameraName']?.toString() ?? 'CAM-01',
      timestamp: json['timestamp']?.toString() ?? '00:00:00 UTC',
      confidence: (json['confidence'] as num?)?.toDouble() ?? 90.0,
      objectType: json['objectType']?.toString() ?? 'Detection',
      description: json['description']?.toString() ?? '',
      boundingBox: bbox,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'cameraName': cameraName,
    'timestamp': timestamp,
    'confidence': confidence,
    'objectType': objectType,
    'description': description,
    'boundingBox': {
      'xmin': boundingBox.left,
      'ymin': boundingBox.top,
      'xmax': boundingBox.right,
      'ymax': boundingBox.bottom,
    },
  };
}
