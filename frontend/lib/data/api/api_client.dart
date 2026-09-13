import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:universa/data/models/case_model.dart';
import 'package:universa/data/models/report_model.dart';
import 'package:universa/data/models/ai_detection_model.dart';

/// HTTP client for the UNIVERSA C++ backend API (default: http://localhost:8080).
class ApiClient {
  ApiClient({String? baseUrl})
      : _base = Uri.parse(baseUrl ?? 'http://localhost:8080');

  final Uri _base;
  final _client = http.Client();

  // ─────────────────────────── Cases ──────────────────────────────

  /// Returns all processed cases from `GET /api/cases`.
  Future<List<CaseModel>> fetchCases() async {
    final uri = _base.replace(path: '/api/cases');
    final response = await _client.get(uri).timeout(const Duration(seconds: 10));
    _assertOk(response, uri);
    final list = jsonDecode(response.body) as List<dynamic>;
    return list
        .map((e) => CaseModel.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  // ─────────────────────────── Report ─────────────────────────────

  /// Returns the full forensic report for a case from `GET /api/cases/:id/report.json`.
  Future<ReportModel> fetchReport(String caseId) async {
    final uri = _base.replace(path: '/api/cases/$caseId/report.json');
    final response = await _client.get(uri).timeout(const Duration(seconds: 10));
    _assertOk(response, uri);
    final map = jsonDecode(response.body) as Map<String, dynamic>;
    return ReportModel.fromJson(map);
  }

  // ─────────────────────────── AI Summary ─────────────────────────

  /// Returns the AI detection summary from `GET /api/cases/:id/ai_summary`.
  Future<List<AiDetectionModel>> fetchAiSummary(String caseId) async {
    final uri = _base.replace(path: '/api/cases/$caseId/ai_summary');
    final response = await _client.get(uri).timeout(const Duration(seconds: 10));
    if (response.statusCode == 404) return [];
    _assertOk(response, uri);
    final list = jsonDecode(response.body) as List<dynamic>;
    return list
        .map((e) => AiDetectionModel.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  // ─────────────────────────── Export bytes ───────────────────────

  /// Fetches the PDF export bytes for a case.
  Future<List<int>> fetchReportPdf(String caseId) async {
    final uri = _base.replace(path: '/api/cases/$caseId/report.pdf');
    final response = await _client.get(uri).timeout(const Duration(seconds: 15));
    _assertOk(response, uri);
    return response.bodyBytes;
  }

  /// Fetches the JSON export string for a case.
  Future<String> fetchReportJson(String caseId) async {
    final uri = _base.replace(path: '/api/cases/$caseId/report.json');
    final response = await _client.get(uri).timeout(const Duration(seconds: 10));
    _assertOk(response, uri);
    return response.body;
  }

  // ─────────────────────────── Upload ─────────────────────────────

  /// Uploads a disk image file to `POST /api/analyze`.
  /// Calls [onProgress] with bytes-sent / total when available.
  Future<ReportModel> uploadDiskImage(
    String filePath, {
    void Function(int sent, int total)? onProgress,
  }) async {
    final uri = _base.replace(path: '/api/analyze');
    final file = File(filePath);
    final bytes = await file.readAsBytes();
    final total = bytes.length;

    final request = http.MultipartRequest('POST', uri);
    request.files.add(http.MultipartFile.fromBytes(
      'file',
      bytes,
      filename: file.uri.pathSegments.last,
    ));

    onProgress?.call(0, total);
    final streamed = await _client.send(request).timeout(const Duration(minutes: 5));
    onProgress?.call(total, total);

    final response = await http.Response.fromStream(streamed);
    _assertOk(response, uri);

    final dynamic decoded = jsonDecode(response.body);
    if (decoded is List) {
      return ReportModel.fromJson(decoded.first as Map<String, dynamic>);
    }
    return ReportModel.fromJson(decoded as Map<String, dynamic>);
  }

  // ─────────────────────────── Helpers ────────────────────────────

  void _assertOk(http.Response response, Uri uri) {
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException(
        uri: uri,
        statusCode: response.statusCode,
        body: response.body,
      );
    }
  }

  void dispose() => _client.close();
}

class ApiException implements Exception {
  final Uri uri;
  final int statusCode;
  final String body;

  const ApiException({
    required this.uri,
    required this.statusCode,
    required this.body,
  });

  @override
  String toString() => 'ApiException($statusCode) for $uri: $body';
}
