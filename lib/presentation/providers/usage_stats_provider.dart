import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pace/models/usage_stats_models.dart';
import 'package:pace/services/native_service.dart';

/// State class for usage stats view
class UsageStatsState {
  final UsageStatsResponse? data;
  final bool isLoading;
  final String? error;
  final UsageStatsViewMode viewMode;
  final AppCategory? selectedFilter;

  const UsageStatsState({
    this.data,
    this.isLoading = false,
    this.error,
    this.viewMode = UsageStatsViewMode.daily,
    this.selectedFilter,
  });

  UsageStatsState copyWith({
    UsageStatsResponse? data,
    bool? isLoading,
    String? error,
    UsageStatsViewMode? viewMode,
    AppCategory? selectedFilter,
  }) {
    return UsageStatsState(
      data: data ?? this.data,
      isLoading: isLoading ?? this.isLoading,
      error: error,
      viewMode: viewMode ?? this.viewMode,
      selectedFilter: selectedFilter ?? this.selectedFilter,
    );
  }

  List<AppUsageStats> get filteredApps {
    if (data == null || selectedFilter == null) {
      return data?.apps ?? [];
    }

    switch (selectedFilter!) {
      case AppCategory.distracting:
        return data!.distractingApps;
      case AppCategory.productive:
        return data!.productiveApps;
      case AppCategory.others:
        return data!.otherApps;
    }
  }
}

/// Notifier for usage statistics
class UsageStatsNotifier extends Notifier<UsageStatsState> {
  @override
  UsageStatsState build() {
    // Return initial state and load data after build
    Future.microtask(() => _loadUsageStats());
    return const UsageStatsState(isLoading: true);
  }

  /// Load usage statistics based on current view mode
  Future<void> _loadUsageStats() async {
    state = state.copyWith(isLoading: true, error: null);

    try {
      final days = state.viewMode == UsageStatsViewMode.daily ? 1 : 7;
      final Map<String, dynamic> rawData;

      if (state.viewMode == UsageStatsViewMode.daily) {
        rawData = await NativeService.getTodayUsageStats();
      } else {
        rawData = await NativeService.getAppUsageStats(days: days);
      }

      final usageStats = UsageStatsResponse.fromMap(rawData);
      state = state.copyWith(data: usageStats, isLoading: false);
    } catch (e) {
      debugPrint('Error loading usage stats: $e');
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  /// Refresh usage statistics
  Future<void> refresh() async {
    await _loadUsageStats();
  }

  /// Switch between daily and weekly view
  void setViewMode(UsageStatsViewMode mode) {
    if (state.viewMode != mode) {
      state = state.copyWith(viewMode: mode);
      _loadUsageStats();
    }
  }

  /// Set category filter
  void setFilter(AppCategory? category) {
    state = state.copyWith(selectedFilter: category);
  }

  /// Clear filter
  void clearFilter() {
    setFilter(null);
  }
}

// Providers
final usageStatsProvider =
    NotifierProvider<UsageStatsNotifier, UsageStatsState>(
      UsageStatsNotifier.new,
    );

/// Today usage stats provider (simple future provider)
final todayUsageStatsProvider = FutureProvider<UsageStatsResponse>((ref) async {
  final rawData = await NativeService.getTodayUsageStats();
  
  // Debug: Print the raw data structure
  debugPrint('📊 Raw Today Usage Data: $rawData');
  debugPrint('📱 Apps count: ${(rawData['apps'] as List?)?.length ?? 0}');
  debugPrint('📈 Summary: ${rawData['summary']}');
  
  return UsageStatsResponse.fromMap(rawData);
});

/// Weekly usage stats provider
final weeklyUsageStatsProvider = FutureProvider<UsageStatsResponse>((
  ref,
) async {
  final rawData = await NativeService.getAppUsageStats(days: 7);
  
  // Debug: Print the raw data structure
  debugPrint('📊 Raw Weekly Usage Data: $rawData');
  debugPrint('📱 Apps count: ${(rawData['apps'] as List?)?.length ?? 0}');
  debugPrint('📈 Summary: ${rawData['summary']}');
  
  return UsageStatsResponse.fromMap(rawData);
});

/// Usage patterns provider
final todayUsagePatternsProvider = FutureProvider<UsagePatternsResponse>((
  ref,
) async {
  final rawData = await NativeService.getTodayUsagePatterns();
  return UsagePatternsResponse.fromMap(rawData);
});

/// Weekly chart data provider
final weeklyChartDataProvider = FutureProvider<List<DailyUsageChartData>>((
  ref,
) async {
  final rawData = await NativeService.getAppUsageStats(days: 7);
  final usageStats = UsageStatsResponse.fromMap(rawData);

  // Process data for chart
  return _processWeeklyData(usageStats);
});

/// Process usage stats into chart data
List<DailyUsageChartData> _processWeeklyData(UsageStatsResponse usageStats) {
  final now = DateTime.now();
  final chartData = <DailyUsageChartData>[];

  for (int i = 6; i >= 0; i--) {
    final date = now.subtract(Duration(days: i));
    final dayKey =
        '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    final dayLabel = _getDayLabel(date);

    int distractingMinutes = 0;
    int productiveMinutes = 0;
    int othersMinutes = 0;

    for (final app in usageStats.apps) {
      final dayUsage = app.dailyUsage[dayKey] ?? 0;

      switch (app.category) {
        case AppCategory.distracting:
          distractingMinutes += dayUsage;
          break;
        case AppCategory.productive:
          productiveMinutes += dayUsage;
          break;
        case AppCategory.others:
          othersMinutes += dayUsage;
          break;
      }
    }

    final totalMinutes = distractingMinutes + productiveMinutes + othersMinutes;

    chartData.add(
      DailyUsageChartData(
        day: dayLabel,
        totalMinutes: totalMinutes,
        distractingMinutes: distractingMinutes,
        productiveMinutes: productiveMinutes,
        othersMinutes: othersMinutes,
      ),
    );
  }

  return chartData;
}

String _getDayLabel(DateTime date) {
  const weekdays = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
  return weekdays[date.weekday - 1];
}

/// Specific app usage provider
final appSpecificUsageProvider =
    FutureProvider.family<Map<String, dynamic>, String>((
      ref,
      packageName,
    ) async {
      return await NativeService.getAppSpecificUsage(
        packageName: packageName,
        days: 7,
      );
    });

/// Quick stats provider for dashboard
final quickStatsProvider = FutureProvider<Map<String, dynamic>>((ref) async {
  try {
    final todayData = await NativeService.getTodayUsageStats();
    final weeklyData = await NativeService.getAppUsageStats(days: 7);

    final today = UsageStatsResponse.fromMap(todayData);
    final weekly = UsageStatsResponse.fromMap(weeklyData);

    return {
      'todayTotal': today.summary.formattedTotalTime,
      'todayDistracting': today.formattedDistractingTime,
      'weeklyAverage': '${(weekly.summary.totalUsageMinutes / 7).round()}m',
      'topAppToday': today.apps.isNotEmpty ? today.apps.first.appName : 'None',
      'totalAppsUsedToday': today.apps.length,
    };
  } catch (e) {
    return {
      'todayTotal': '0m',
      'todayDistracting': '0m',
      'weeklyAverage': '0m',
      'topAppToday': 'None',
      'totalAppsUsedToday': 0,
      'error': e.toString(),
    };
  }
});
