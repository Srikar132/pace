/// Model for individual app usage statistics
class AppUsageStats {
  final String packageName;
  final String appName;
  final String? appIcon;
  final int totalUsageMinutes;
  final int totalUsageMs;
  final double totalUsageHours;
  final int sessions;
  final int lastUsed;
  final Map<String, int> dailyUsage;
  final AppCategory category;

  const AppUsageStats({
    required this.packageName,
    required this.appName,
    this.appIcon,
    required this.totalUsageMinutes,
    required this.totalUsageMs,
    required this.totalUsageHours,
    required this.sessions,
    required this.lastUsed,
    required this.dailyUsage,
    required this.category,
  });

  factory AppUsageStats.fromMap(Map<String, dynamic> map) {
    return AppUsageStats(
      packageName: map['packageName'] ?? '',
      appName: map['appName'] ?? '',
      appIcon: map['appIcon'],
      totalUsageMinutes: map['totalUsageMinutes'] ?? 0,
      totalUsageMs: map['totalUsageMs'] ?? 0,
      totalUsageHours: (map['totalUsageHours'] ?? 0.0).toDouble(),
      sessions: map['sessions'] ?? 0,
      lastUsed: map['lastUsed'] ?? 0,
      // FIXED: Kotlin already sends minutes, don't convert again
      dailyUsage: Map<String, int>.from(
        (map['dailyUsage'] ?? <String, dynamic>{}).map(
          (key, value) => MapEntry(key, (value is int) ? value : value.toInt()),
        ),
      ),
      category: _getAppCategory(map['packageName'] ?? ''),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'packageName': packageName,
      'appName': appName,
      'appIcon': appIcon,
      'totalUsageMinutes': totalUsageMinutes,
      'totalUsageMs': totalUsageMs,
      'totalUsageHours': totalUsageHours,
      'sessions': sessions,
      'lastUsed': lastUsed,
      'dailyUsage': dailyUsage,
      'category': category.name,
    };
  }

  static AppCategory _getAppCategory(String packageName) {
    // Social media and entertainment apps
    if (packageName.contains('instagram') ||
        packageName.contains('facebook') ||
        packageName.contains('twitter') ||
        packageName.contains('tiktok') ||
        packageName.contains('snapchat') ||
        packageName.contains('youtube') ||
        packageName.contains('netflix') ||
        packageName.contains('spotify')) {
      return AppCategory.distracting;
    }

    // Productivity apps
    if (packageName.contains('office') ||
        packageName.contains('docs') ||
        packageName.contains('sheets') ||
        packageName.contains('slides') ||
        packageName.contains('notion') ||
        packageName.contains('trello') ||
        packageName.contains('slack') ||
        packageName.contains('zoom') ||
        packageName.contains('teams')) {
      return AppCategory.productive;
    }

    // ADDED: Filter out your own app from stats
    if (packageName.contains('pace') || 
        packageName == 'com.example.pace') {
      return AppCategory.others; // Or create a new category to hide it
    }

    return AppCategory.others;
  }

  String get formattedUsageTime {
    if (totalUsageHours >= 1) {
      final hours = totalUsageHours.floor();
      final minutes = ((totalUsageHours - hours) * 60).round();
      if (minutes == 0) {
        return '${hours}h';
      }
      return '${hours}h ${minutes}m';
    } else {
      return '${totalUsageMinutes}m';
    }
  }

  DateTime get lastUsedDateTime =>
      DateTime.fromMillisecondsSinceEpoch(lastUsed);
}

/// Model for usage summary statistics
class UsageSummary {
  final int totalAppsUsed;
  final int totalUsageMinutes;
  final double totalUsageHours;
  final int averageUsagePerApp;
  final String topApp;
  final int daysAnalyzed;
  final String? error;

  const UsageSummary({
    required this.totalAppsUsed,
    required this.totalUsageMinutes,
    required this.totalUsageHours,
    required this.averageUsagePerApp,
    required this.topApp,
    required this.daysAnalyzed,
    this.error,
  });

  factory UsageSummary.fromMap(Map<String, dynamic> map) {
    return UsageSummary(
      totalAppsUsed: map['totalAppsUsed'] ?? 0,
      totalUsageMinutes: map['totalUsageMinutes'] ?? 0,
      totalUsageHours: (map['totalUsageHours'] ?? 0.0).toDouble(),
      averageUsagePerApp: map['averageUsagePerApp'] ?? 0,
      topApp: map['topApp'] ?? 'None',
      daysAnalyzed: map['daysAnalyzed'] ?? 0,
      error: map['error'],
    );
  }

  String get formattedTotalTime {
    if (totalUsageHours >= 1) {
      final hours = totalUsageHours.floor();
      final minutes = ((totalUsageHours - hours) * 60).round();
      if (minutes == 0) {
        return '${hours}h';
      }
      return '${hours}h ${minutes}m';
    } else {
      return '${totalUsageMinutes}m';
    }
  }
}

/// Model for usage period information
class UsagePeriod {
  final int startTime;
  final int endTime;
  final int days;

  const UsagePeriod({
    required this.startTime,
    required this.endTime,
    required this.days,
  });

  factory UsagePeriod.fromMap(Map<String, dynamic> map) {
    return UsagePeriod(
      startTime: map['startTime'] ?? 0,
      endTime: map['endTime'] ?? 0,
      days: map['days'] ?? 0,
    );
  }

  DateTime get startDate => DateTime.fromMillisecondsSinceEpoch(startTime);
  DateTime get endDate => DateTime.fromMillisecondsSinceEpoch(endTime);
}

/// Complete usage statistics response model
class UsageStatsResponse {
  final List<AppUsageStats> apps;
  final UsageSummary summary;
  final UsagePeriod period;

  const UsageStatsResponse({
    required this.apps,
    required this.summary,
    required this.period,
  });

  factory UsageStatsResponse.fromMap(Map<String, dynamic> map) {
    final appsList =
        (map['apps'] as List<dynamic>?)
            ?.map(
              (app) => AppUsageStats.fromMap(Map<String, dynamic>.from(app)),
            )
            .toList() ??
        [];

    return UsageStatsResponse(
      apps: appsList,
      summary: UsageSummary.fromMap(
        Map<String, dynamic>.from(map['summary'] ?? {}),
      ),
      period: UsagePeriod.fromMap(
        Map<String, dynamic>.from(map['period'] ?? {}),
      ),
    );
  }

  List<AppUsageStats> get distractingApps =>
      apps.where((app) => app.category == AppCategory.distracting).toList();

  List<AppUsageStats> get productiveApps =>
      apps.where((app) => app.category == AppCategory.productive).toList();

  List<AppUsageStats> get otherApps =>
      apps.where((app) => app.category == AppCategory.others).toList();

  // ADDED: Filter out the pace app from all lists
  List<AppUsageStats> get appsExcludingSelf =>
      apps.where((app) => !app.packageName.contains('pace')).toList();

  int get totalDistractingTime =>
      distractingApps.fold(0, (sum, app) => sum + app.totalUsageMinutes);

  int get totalProductiveTime =>
      productiveApps.fold(0, (sum, app) => sum + app.totalUsageMinutes);

  int get totalOthersTime =>
      otherApps.fold(0, (sum, app) => sum + app.totalUsageMinutes);

  // ADDED: Total time excluding the pace app
  int get totalUsageExcludingSelf =>
      appsExcludingSelf.fold(0, (sum, app) => sum + app.totalUsageMinutes);

  String get formattedDistractingTime {
    final hours = totalDistractingTime / 60;
    if (hours >= 1) {
      final h = hours.floor();
      final m = (totalDistractingTime % 60);
      if (m == 0) return '${h}h';
      return '${h}h ${m}m';
    }
    return '${totalDistractingTime}m';
  }

  String get formattedProductiveTime {
    final hours = totalProductiveTime / 60;
    if (hours >= 1) {
      final h = hours.floor();
      final m = (totalProductiveTime % 60);
      if (m == 0) return '${h}h';
      return '${h}h ${m}m';
    }
    return '${totalProductiveTime}m';
  }

  String get formattedOthersTime {
    final hours = totalOthersTime / 60;
    if (hours >= 1) {
      final h = hours.floor();
      final m = (totalOthersTime % 60);
      if (m == 0) return '${h}h';
      return '${h}h ${m}m';
    }
    return '${totalOthersTime}m';
  }

  // ADDED: Formatted time excluding pace app
  String get formattedTotalTimeExcludingSelf {
    final hours = totalUsageExcludingSelf / 60;
    if (hours >= 1) {
      final h = hours.floor();
      final m = (totalUsageExcludingSelf % 60);
      if (m == 0) return '${h}h';
      return '${h}h ${m}m';
    }
    return '${totalUsageExcludingSelf}m';
  }
}

/// Model for hourly usage patterns
class HourlyUsageData {
  final int hour;
  final int usageMinutes;
  final bool isCurrentHour;

  const HourlyUsageData({
    required this.hour,
    required this.usageMinutes,
    required this.isCurrentHour,
  });

  factory HourlyUsageData.fromMap(Map<String, dynamic> map) {
    return HourlyUsageData(
      hour: map['hour'] ?? 0,
      usageMinutes: map['usageMinutes'] ?? 0,
      isCurrentHour: map['isCurrentHour'] ?? false,
    );
  }

  String get hourLabel {
    if (hour == 0) return '12 AM';
    if (hour < 12) return '${hour} AM';
    if (hour == 12) return '12 PM';
    return '${hour - 12} PM';
  }
}

/// Model for usage patterns response
class UsagePatternsResponse {
  final List<HourlyUsageData> hourlyUsage;
  final int totalUsageToday;
  final int peakHour;
  final int peakUsage;
  final int currentHour;

  const UsagePatternsResponse({
    required this.hourlyUsage,
    required this.totalUsageToday,
    required this.peakHour,
    required this.peakUsage,
    required this.currentHour,
  });

  factory UsagePatternsResponse.fromMap(Map<String, dynamic> map) {
    final hourlyList =
        (map['hourlyUsage'] as List<dynamic>?)
            ?.map(
              (hour) =>
                  HourlyUsageData.fromMap(Map<String, dynamic>.from(hour)),
            )
            .toList() ??
        [];

    final summaryMap = Map<String, dynamic>.from(map['summary'] ?? {});

    return UsagePatternsResponse(
      hourlyUsage: hourlyList,
      totalUsageToday: summaryMap['totalUsageToday'] ?? 0,
      peakHour: summaryMap['peakHour'] ?? 0,
      peakUsage: summaryMap['peakUsage'] ?? 0,
      currentHour: summaryMap['currentHour'] ?? 0,
    );
  }
}

/// Enum for app categories
enum AppCategory {
  distracting,
  productive,
  others;

  String get displayName {
    switch (this) {
      case AppCategory.distracting:
        return 'Distracting';
      case AppCategory.productive:
        return 'Productive';
      case AppCategory.others:
        return 'Others';
    }
  }

  String get colorName {
    switch (this) {
      case AppCategory.distracting:
        return 'orange';
      case AppCategory.productive:
        return 'green';
      case AppCategory.others:
        return 'grey';
    }
  }
}

/// Enum for usage stats view mode
enum UsageStatsViewMode {
  daily,
  weekly;

  String get displayName {
    switch (this) {
      case UsageStatsViewMode.daily:
        return 'Daily';
      case UsageStatsViewMode.weekly:
        return 'Weekly';
    }
  }
}

/// Model for daily usage chart data
class DailyUsageChartData {
  final String day;
  final int totalMinutes;
  final int distractingMinutes;
  final int productiveMinutes;
  final int othersMinutes;

  const DailyUsageChartData({
    required this.day,
    required this.totalMinutes,
    required this.distractingMinutes,
    required this.productiveMinutes,
    required this.othersMinutes,
  });

  double get totalHours => totalMinutes / 60.0;
  double get distractingHours => distractingMinutes / 60.0;
  double get productiveHours => productiveMinutes / 60.0;
  double get othersHours => othersMinutes / 60.0;
}