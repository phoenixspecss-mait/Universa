import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:universa/data/models/case_model.dart';
import 'package:universa/data/models/search_result_model.dart';
import 'package:universa/data/models/report_model.dart';
import 'package:universa/data/models/ai_detection_model.dart';
import 'package:universa/data/api/api_client.dart';
import 'package:universa/data/api/upload_notifier.dart';
import 'package:universa/data/mock_data.dart';

/// Configurable demo flag: MockData is ONLY loaded when compiled with `--dart-define=DEMO_MODE=true`
const bool _isDemoMode = bool.fromEnvironment('DEMO_MODE', defaultValue: false);

// ──────────────────────────── API ────────────────────────────────

/// Singleton HTTP client shared across providers.
final apiClientProvider = Provider<ApiClient>((ref) {
  final client = ApiClient();
  ref.onDispose(client.dispose);
  return client;
});

// ──────────────────────────── Cases ──────────────────────────────

/// Live case list from `GET /api/cases`.
/// Throws AsyncError when backend is offline unless DEMO_MODE is active.
final casesProvider = FutureProvider<List<CaseModel>>((ref) async {
  try {
    final client = ref.watch(apiClientProvider);
    return await client.fetchCases();
  } catch (e) {
    if (_isDemoMode) {
      debugPrint('[DEMO MODE] Using mock cases due to error: $e');
      return MockData.cases;
    }
    rethrow;
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
    loading: () => {
      'activeCases': 0,
      'avgExtractionTime': '—',
      'avgExtractionProgress': 0.0,
      'pendingAiTriage': 0,
      'hashVerifiedCases': 0,
    },
    error: (e, st) => {
      'activeCases': 0,
      'avgExtractionTime': 'ERR',
      'avgExtractionProgress': 0.0,
      'pendingAiTriage': 0,
      'hashVerifiedCases': 0,
    },
  );
});

// ──────────────────────────── Search ─────────────────────────────

final searchQueryProvider = StateProvider<String>((ref) => '');

class SearchResultsNotifier extends StateNotifier<List<SearchResultModel>> {
  SearchResultsNotifier(this._client) : super(_isDemoMode ? MockData.searchResults : const []);

  final ApiClient _client;
  String _lastQuery = '';

  Future<void> search(String query) async {
    if (query == _lastQuery) return;
    _lastQuery = query;

    if (query.trim().isEmpty) {
      state = _isDemoMode ? MockData.searchResults : const [];
      return;
    }

    try {
      final liveResults = await _client.searchSemantic(query);
      state = liveResults;
    } catch (e) {
      if (_isDemoMode) {
        state = MockData.searchResults.where((r) =>
          r.description.toLowerCase().contains(query.toLowerCase()) ||
          r.cameraName.toLowerCase().contains(query.toLowerCase()) ||
          r.objectType.toLowerCase().contains(query.toLowerCase())
        ).toList();
      } else {
        state = const [];
        rethrow;
      }
    }
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
/// Propagates errors cleanly as AsyncValue.error.
final reportProvider = FutureProvider.family<ReportModel, String>((ref, caseId) async {
  try {
    final client = ref.watch(apiClientProvider);
    return await client.fetchReport(caseId);
  } catch (e) {
    if (_isDemoMode) {
      debugPrint('[DEMO MODE] Using mock report: $e');
      return MockData.sampleReport;
    }
    rethrow;
  }
});

// ──────────────────────────── AI Summary ─────────────────────────

/// Live AI detections from `GET /api/cases/:id/ai_summary`.
final aiSummaryProvider =
    FutureProvider.family<List<AiDetectionModel>, String>((ref, caseId) async {
  try {
    final client = ref.watch(apiClientProvider);
    return await client.fetchAiSummary(caseId);
  } catch (e) {
    if (_isDemoMode) {
      debugPrint('[DEMO MODE] Using empty AI summary fallback: $e');
      return [];
    }
    rethrow;
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
  } catch (e) {
    if (_isDemoMode) {
      return {'events': [], 'total_events': 0};
    }
    rethrow;
  }
});

final correlationsProvider =
    FutureProvider.family<List<dynamic>, String>((ref, caseId) async {
  try {
    final client = ref.watch(apiClientProvider);
    return await client.fetchCorrelations(caseId);
  } catch (e) {
    if (_isDemoMode) {
      return [];
    }
    rethrow;
  }
});

final pipelineStatusProvider = FutureProvider<Map<String, dynamic>>((ref) async {
  try {
    final client = ref.watch(apiClientProvider);
    return await client.fetchPipelineStatus();
  } catch (e) {
    if (_isDemoMode) {
      return {'is_healthy': false};
    }
    rethrow;
  }
});
