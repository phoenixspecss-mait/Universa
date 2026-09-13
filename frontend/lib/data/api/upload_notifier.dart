import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:universa/data/models/report_model.dart';
import 'package:universa/data/api/api_client.dart';

enum UploadStatus { idle, picking, uploading, done, error }

class UploadState {
  final UploadStatus status;
  final double progress; // 0.0–1.0
  final String? errorMessage;
  final ReportModel? result;

  const UploadState({
    this.status = UploadStatus.idle,
    this.progress = 0,
    this.errorMessage,
    this.result,
  });

  UploadState copyWith({
    UploadStatus? status,
    double? progress,
    String? errorMessage,
    ReportModel? result,
  }) {
    return UploadState(
      status: status ?? this.status,
      progress: progress ?? this.progress,
      errorMessage: errorMessage ?? this.errorMessage,
      result: result ?? this.result,
    );
  }
}

class UploadNotifier extends StateNotifier<UploadState> {
  UploadNotifier(this._apiClient) : super(const UploadState());

  final ApiClient _apiClient;

  Future<ReportModel?> upload(String filePath) async {
    state = state.copyWith(status: UploadStatus.uploading, progress: 0);
    try {
      final report = await _apiClient.uploadDiskImage(
        filePath,
        onProgress: (sent, total) {
          if (total > 0) {
            state = state.copyWith(progress: sent / total);
          }
        },
      );
      state = state.copyWith(status: UploadStatus.done, progress: 1.0, result: report);
      return report;
    } catch (e) {
      state = state.copyWith(
        status: UploadStatus.error,
        errorMessage: e.toString(),
      );
      return null;
    }
  }

  void reset() => state = const UploadState();
}
