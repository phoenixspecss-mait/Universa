import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';

import 'package:universa/core/theme/app_colors.dart';
import 'package:universa/core/theme/app_typography.dart';
import 'package:universa/core/widgets/surveillance_frame.dart';
import 'package:universa/data/providers.dart';
import 'package:universa/features/search/widgets/timeline_strip.dart';

class SearchScreen extends ConsumerStatefulWidget {
  final String? caseId;

  const SearchScreen({super.key, this.caseId});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final TextEditingController _searchController = TextEditingController();
  final Set<String> _selectedFilters = {};

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final results = ref.watch(searchResultsProvider);
    final query = ref.watch(searchQueryProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: _searchController,
                  onChanged: (val) {
                    ref.read(searchQueryProvider.notifier).state = val;
                  },
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.search),
                    hintText: "Search e.g. 'red jacket near gate 3, 8–9 PM'",
                    suffixIcon: query.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear),
                            onPressed: () {
                              _searchController.clear();
                              ref.read(searchQueryProvider.notifier).state = '';
                            },
                          )
                        : null,
                  ),
                ),
                if (query.isNotEmpty)
                  Container(
                    margin: const EdgeInsets.only(top: 6),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppColors.emerald.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.auto_awesome, color: AppColors.emerald, size: 14),
                        const SizedBox(width: 6),
                        Text(
                          'Neural query parsing...',
                          style: AppTypography.bodySmall.copyWith(color: AppColors.emerald),
                        ),
                        const Spacer(),
                        Text(
                          '${results.length} matches',
                          style: AppTypography.monoSmall.copyWith(color: AppColors.emerald),
                        ),
                      ],
                    ),
                  ).animate(onPlay: (controller) => controller.repeat()).shimmer(
                    duration: const Duration(seconds: 2),
                    color: AppColors.emerald.withValues(alpha: 0.3),
                  ),
              ],
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                _buildFilterChip('Camera/Channel', Icons.videocam_outlined),
                const SizedBox(width: 8),
                _buildFilterChip('Time Range', Icons.schedule),
                const SizedBox(width: 8),
                _buildFilterChip('Object Type', Icons.category_outlined),
                const SizedBox(width: 8),
                _buildFilterChip('Confidence >85%', Icons.tune),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Container(
            height: 70,
            margin: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: AppColors.surface,
              border: Border.all(color: AppColors.border),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const TimelineStrip(),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: results.isNotEmpty
                ? GridView.builder(
                    padding: const EdgeInsets.all(16),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      crossAxisSpacing: 10,
                      mainAxisSpacing: 10,
                      childAspectRatio: 0.65,
                    ),
                    itemCount: results.length,
                    itemBuilder: (context, index) {
                      final r = results[index];
                      return Container(
                        decoration: BoxDecoration(
                          color: AppColors.surface,
                          border: Border.all(color: AppColors.border),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Expanded(
                              child: ClipRRect(
                                borderRadius: const BorderRadius.vertical(top: Radius.circular(7)),
                                child: SurveillanceFrame(
                                  cameraName: r.cameraName,
                                  timestamp: r.timestamp,
                                  confidence: r.confidence,
                                  objectLabel: r.objectType,
                                  boundingBoxColor: r.objectType == 'Person'
                                      ? AppColors.rustAmber
                                      : AppColors.electricCyan,
                                  showHud: true,
                                  showBoundingBox: true,
                                  isCarved: index == 0,
                                  variant: index % 6,
                                  onTap: () {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          'Opening ${r.cameraName} analysis at ${r.timestamp} — Confidence: ${r.confidence}%',
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.all(8),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Text(
                                        r.timestamp,
                                        style: AppTypography.monoSmall.copyWith(
                                          color: AppColors.electricCyan,
                                        ),
                                      ),
                                      const Spacer(),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: AppColors.surface,
                                          border: Border.all(color: AppColors.border),
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                        child: Text(
                                          r.objectType,
                                          style: AppTypography.labelSmall.copyWith(
                                            color: AppColors.textPrimary,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    r.description,
                                    style: AppTypography.bodySmall.copyWith(
                                      color: AppColors.textSecondary,
                                    ),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    r.cameraName,
                                    style: AppTypography.labelSmall.copyWith(
                                      color: AppColors.textMuted,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ).animate().fadeIn(delay: Duration(milliseconds: 50 * index)).scale();
                    },
                  )
                : Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.search_off, size: 64, color: AppColors.textMuted),
                        const SizedBox(height: 12),
                        Text(
                          'No matches found',
                          style: AppTypography.bodyLarge.copyWith(color: AppColors.textPrimary),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Try a natural language query like "red jacket near gate 3"',
                          style: AppTypography.bodyMedium.copyWith(color: AppColors.textSecondary),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ).animate().fadeIn().scale(),
          ),
        ],
    );
  }

  Widget _buildFilterChip(String label, IconData icon) {
    final selected = _selectedFilters.contains(label);
    return FilterChip(
      avatar: Icon(
        icon,
        size: 16,
        color: selected ? AppColors.electricCyan : AppColors.textMuted,
      ),
      label: Text(label),
      selected: selected,
      selectedColor: AppColors.electricCyan.withValues(alpha: 0.1),
      checkmarkColor: AppColors.electricCyan,
      side: BorderSide(
        color: selected ? AppColors.electricCyan : AppColors.border,
      ),
      onSelected: (val) {
        setState(() {
          if (val) {
            _selectedFilters.add(label);
          } else {
            _selectedFilters.remove(label);
          }
        });
      },
    );
  }
}
