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
}
