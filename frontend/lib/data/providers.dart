import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:universa/data/models/case_model.dart';
import 'package:universa/data/models/search_result_model.dart';
import 'package:universa/data/models/report_model.dart';
import 'package:universa/data/models/ai_detection_model.dart';
import 'package:universa/data/api/api_client.dart';
import 'package:universa/data/api/upload_notifier.dart';
import 'package:universa/data/mock_data.dart';

// ──────────────────────────── API ────────────────────────────────

/// Singleton HTTP client shared across providers.
final apiClientProvider = Provider<ApiClient>((ref) {
  final client = ApiClient();
  ref.onDispose(client.dispose);
  return client;
});

// ──────────────────────────── Cases ──────────────────────────────

/// Live case list from `GET /api/cases`.
/// Falls back to mock data when the server is unreachable.
final casesProvider = FutureProvider<List<CaseModel>>((ref) async {
  try {
    final client = ref.watch(apiClientProvider);
    return await client.fetchCases();
  } catch (_) {
    // Graceful fallback so the app still works without a running server.
    return MockData.cases;
  }
});

// ──────────────────────────── Stats ──────────────────────────────

/// Derives dashboard stats from the live case list.
final dashboardStatsProvider = Provider<Map<String, dynamic>>((ref) {
  final casesAsync = ref.watch(casesProvider);
  return casesAsync.when(
    data: (cases) => {
      'activeCases': cases.length,
      'avgExtractionTime': '—',
      'avgExtractionProgress': 0.0,
      'pendingAiTriage': cases.where((c) => c.status == CaseStatus.aiTriage).length,
      'hashVerifiedCases': cases.where((c) => c.status == CaseStatus.hashVerified).length,
    },
    loading: () => MockData.dashboardStats,
    error: (_, __) => MockData.dashboardStats,
  );
});

// ──────────────────────────── Search ─────────────────────────────

final searchQueryProvider = StateProvider<String>((ref) => '');

class SearchResultsNotifier extends StateNotifier<List<SearchResultModel>> {
  SearchResultsNotifier(this._client) : super(MockData.searchResults);

  final ApiClient _client;
  String _lastQuery = '';

  Future<void> search(String query) async {
    if (query == _lastQuery) return;
    _lastQuery = query;

    if (query.trim().isEmpty) {
      state = MockData.searchResults;
      return;
    }

    try {
      final liveResults = await _client.searchSemantic(query);
      if (liveResults.isNotEmpty) {
        state = liveResults;
        return;
      }
    } catch (_) {}

    // Graceful fallback to client-side filtering if server is offline
    state = MockData.searchResults.where((r) =>
      r.description.toLowerCase().contains(query.toLowerCase()) ||
      r.cameraName.toLowerCase().contains(query.toLowerCase()) ||
      r.objectType.toLowerCase().contains(query.toLowerCase())
    ).toList();
  }
}

final searchResultsNotifierProvider =
    StateNotifierProvider<SearchResultsNotifier, List<SearchResultModel>>((ref) {
  final client = ref.watch(apiClientProvider);
  final notifier = SearchResultsNotifier(client);

  ref.listen<String>(searchQueryProvider, (_, next) {
    notifier.search(next);
  });

  return notifier;
});

final searchResultsProvider = Provider<List<SearchResultModel>>((ref) {
  return ref.watch(searchResultsNotifierProvider);
});

// ──────────────────────────── Report ─────────────────────────────

final selectedCaseIdProvider = StateProvider<String?>((ref) => null);

/// Live report from `GET /api/cases/:id/report.json`.
/// Falls back to mock report when server is unreachable.
final reportProvider = FutureProvider.family<ReportModel, String>((ref, caseId) async {
  try {
    final client = ref.watch(apiClientProvider);
    return await client.fetchReport(caseId);
  } catch (_) {
    return MockData.sampleReport;
  }
});

// ──────────────────────────── AI Summary ─────────────────────────

/// Live AI detections from `GET /api/cases/:id/ai_summary`.
final aiSummaryProvider =
    FutureProvider.family<List<AiDetectionModel>, String>((ref, caseId) async {
  try {
    final client = ref.watch(apiClientProvider);
    return await client.fetchAiSummary(caseId);
  } catch (_) {
    return [];
  }
});

// ──────────────────────────── Upload ─────────────────────────────

final uploadProvider =
    StateNotifierProvider<UploadNotifier, UploadState>((ref) {
  return UploadNotifier(ref.watch(apiClientProvider));
});

// ──────────────────────────── Timeline & Correlation ─────────────

final timelineEventsProvider =
    FutureProvider.family<Map<String, dynamic>, String>((ref, caseId) async {
  try {
    final client = ref.watch(apiClientProvider);
    return await client.fetchTimeline(caseId);
  } catch (_) {
    return {'events': [], 'total_events': 0};
  }
});

final correlationsProvider =
    FutureProvider.family<List<dynamic>, String>((ref, caseId) async {
  try {
    final client = ref.watch(apiClientProvider);
    return await client.fetchCorrelations(caseId);
  } catch (_) {
    return [];
  }
});

final pipelineStatusProvider = FutureProvider<Map<String, dynamic>>((ref) async {
  try {
    final client = ref.watch(apiClientProvider);
    return await client.fetchPipelineStatus();
  } catch (_) {
    return {'is_healthy': false};
  }
});

