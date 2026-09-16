import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pace/models/usage_stats_models.dart';
import 'package:pace/presentation/providers/usage_stats_provider.dart';
import 'package:pace/presentation/widgets/usage_stats_widgets.dart';

class UsageStatsScreen extends ConsumerStatefulWidget {
  const UsageStatsScreen({super.key});

  @override
  ConsumerState<UsageStatsScreen> createState() => _UsageStatsScreenState();
}

class _UsageStatsScreenState extends ConsumerState<UsageStatsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  AppCategory? _selectedFilter;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    
    // Load initial data
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Invalidate the providers to trigger fresh data load
      ref.invalidate(todayUsageStatsProvider);
      ref.invalidate(weeklyUsageStatsProvider);
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('Usage Insights'),
        backgroundColor: theme.scaffoldBackgroundColor,
        elevation: 0,
       
        actions: [
          IconButton(
            icon: Icon(Icons.help_outline, color: theme.iconTheme.color),
            onPressed: () {
              _showHelpDialog(context);
            },
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Daily'),
            Tab(text: 'Weekly'),
          ],
          indicatorColor: theme.colorScheme.primary,
          labelColor: Colors.white,
          unselectedLabelColor: const Color(0xFF8A8A8A),
          labelStyle: theme.textTheme.titleMedium,
          unselectedLabelStyle: theme.textTheme.titleMedium,
        ),
      ),
      body: Column(
        children: [
          // Category Filter Chips
          _buildFilterChips(theme),
          
          // Tab Content
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildDailyView(),
                _buildWeeklyView(),
              ],
            ),
          ),
        ],
      ),
    );
  }

Widget _buildFilterChips(ThemeData theme) {
  return SingleChildScrollView(
    scrollDirection: Axis.horizontal, // Enable horizontal scrolling
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    child: Row(
      children: [
        _buildFilterChip('All apps', null, theme, isSelected: _selectedFilter == null),
        const SizedBox(width: 8),
        _buildFilterChip('Distracting', AppCategory.distracting, theme, isSelected: _selectedFilter == AppCategory.distracting),
        const SizedBox(width: 8),
        _buildFilterChip('Productive', AppCategory.productive, theme, isSelected: _selectedFilter == AppCategory.productive),
        const SizedBox(width: 8),
        _buildFilterChip('Others', AppCategory.others, theme, isSelected: _selectedFilter == AppCategory.others),
      ],
    ),
  );
}


  Widget _buildFilterChip(
    String label,
    AppCategory? category,
    ThemeData theme, {
    required bool isSelected,
  }) {
    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedFilter = isSelected ? null : category;
        });
        ref.read(usageStatsProvider.notifier).setFilter(_selectedFilter);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? theme.colorScheme.primary.withOpacity(0.2) : const Color(0xFF2A2A2A),
          borderRadius: BorderRadius.circular(20),
          border: isSelected 
            ? Border.all(color: theme.colorScheme.primary, width: 1)
            : null,
        ),
        child: Text(
          label,
          style: theme.textTheme.labelMedium?.copyWith(
            color: isSelected ? theme.colorScheme.primary : const Color(0xFF8A8A8A),
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
          ),
        ),
      ),
    );
  }

  Widget _buildDailyView() {
    return Consumer(
      builder: (context, ref, child) {
        final todayUsage = ref.watch(todayUsageStatsProvider);
        
        return todayUsage.when(
          data: (data) => _buildDailyContent(data),
          loading: () => const Center(
            child: CircularProgressIndicator(color: Color(0xFF7ED957)),
          ),
          error: (error, _) => Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.error_outline,
                  size: 48,
                  color: Theme.of(context).colorScheme.error,
                ),
                const SizedBox(height: 16),
                Text(
                  'Error loading usage stats',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Text(
                  error.toString(),
                  style: Theme.of(context).textTheme.bodyMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: () {
                    ref.invalidate(todayUsageStatsProvider);
                  },
                  child: const Text('Retry'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildWeeklyView() {
    return Consumer(
      builder: (context, ref, child) {
        final weeklyUsage = ref.watch(weeklyUsageStatsProvider);
        final chartData = ref.watch(weeklyChartDataProvider);
        
        return weeklyUsage.when(
          data: (data) => _buildWeeklyContent(data, chartData),
          loading: () => const Center(
            child: CircularProgressIndicator(color: Color(0xFF7ED957)),
          ),
          error: (error, _) => Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.error_outline,
                  size: 48,
                  color: Theme.of(context).colorScheme.error,
                ),
                const SizedBox(height: 16),
                Text(
                  'Error loading usage stats',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Text(
                  error.toString(),
                  style: Theme.of(context).textTheme.bodyMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: () {
                    ref.invalidate(weeklyUsageStatsProvider);
                    ref.invalidate(weeklyChartDataProvider);
                  },
                  child: const Text('Retry'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildDailyContent(UsageStatsResponse data) {
    final theme = Theme.of(context);
    final filteredApps = _getFilteredApps(data);

    final totalMinutesExcludingSelf = data.totalUsageExcludingSelf;
    final formattedTimeExcludingSelf = data.formattedTotalTimeExcludingSelf;
    
    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(todayUsageStatsProvider);
      },
      color: theme.colorScheme.primary,
      backgroundColor: theme.colorScheme.surface,
      child: CustomScrollView(
        slivers: [
          // Today's Summary
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Main usage time
                  Center(
                    child: Column(
                      children: [
                        Text(
                          formattedTimeExcludingSelf,
                          style: theme.textTheme.displayLarge?.copyWith(
                            fontSize: 48,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          'Today - ${_formatDate(DateTime.now())}',
                          style: theme.textTheme.bodyLarge?.copyWith(
                            color: const Color(0xFF8A8A8A),
                          ),
                        ),
                      ],
                    ),
                  ),
                  
                  const SizedBox(height: 24),
                  
                  // Category breakdown
                  _buildCategoryBreakdown(data, theme),
                  
                  const SizedBox(height: 24),
                  
                  // Search bar
                  _buildSearchBar(theme),
                ],
              ),
            ),
          ),
          
          // Apps list
          SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                if (index >= filteredApps.length) return null;
                final app = filteredApps[index];
                return UsageAppListTile(app: app);
              },
              childCount: filteredApps.length,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWeeklyContent(UsageStatsResponse data, AsyncValue<List<DailyUsageChartData>> chartData) {
    final theme = Theme.of(context);
    final filteredApps = _getFilteredApps(data);
    
    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(weeklyUsageStatsProvider);
        ref.invalidate(weeklyChartDataProvider);
      },
      color: theme.colorScheme.primary,
      backgroundColor: theme.colorScheme.surface,
      child: CustomScrollView(
        slivers: [
          // Weekly Summary
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Main usage time
                  Center(
                    child: Column(
                      children: [
                        Text(
                          data.summary.formattedTotalTime,
                          style: theme.textTheme.displayLarge?.copyWith(
                            fontSize: 48,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          '${_formatWeekRange()} • + 4% vs last week',
                          style: theme.textTheme.bodyLarge?.copyWith(
                            color: const Color(0xFF8A8A8A),
                          ),
                        ),
                      ],
                    ),
                  ),
                  
                  const SizedBox(height: 24),
                  
                  // Weekly chart
                  chartData.when(
                    data: (chartList) => WeeklyUsageChart(data: chartList),
                    loading: () => const SizedBox(
                      height: 200,
                      child: Center(
                        child: CircularProgressIndicator(color: Color(0xFF7ED957)),
                      ),
                    ),
                    error: (_, __) => const SizedBox(
                      height: 200,
                      child: Center(
                        child: Text('Error loading chart'),
                      ),
                    ),
                  ),
                  
                  const SizedBox(height: 24),
                  
                  // Category breakdown
                  _buildCategoryBreakdown(data, theme),
                  
                  const SizedBox(height: 24),
                  
                  // Search bar
                  _buildSearchBar(theme),
                ],
              ),
            ),
          ),
          
          // Apps list
          SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                if (index >= filteredApps.length) return null;
                final app = filteredApps[index];
                return UsageAppListTile(app: app);
              },
              childCount: filteredApps.length,
            ),
          ),
        ],
      ),
    );
  }

Widget _buildCategoryBreakdown(UsageStatsResponse data, ThemeData theme) {
  // Filter out pace app from all categories
  final filteredApps = data.apps.where((app) => 
    !app.packageName.contains('pace') && 
    app.packageName != 'com.example.pace'
  ).toList();
  
  // Calculate category times excluding pace
  final distractingTime = filteredApps
      .where((app) => app.category == AppCategory.distracting)
      .fold(0, (sum, app) => sum + app.totalUsageMinutes);
  
  final productiveTime = filteredApps
      .where((app) => app.category == AppCategory.productive)
      .fold(0, (sum, app) => sum + app.totalUsageMinutes);
  
  final othersTime = filteredApps
      .where((app) => app.category == AppCategory.others)
      .fold(0, (sum, app) => sum + app.totalUsageMinutes);
  
  return Row(
    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
    children: [
      _buildCategoryItem(
        _formatTime(distractingTime),
        'Distracting',
        const Color(0xFFFF8C00), // Orange
        theme,
      ),
      _buildCategoryItem(
        _formatTime(productiveTime),
        'Productive',
        const Color(0xFF7ED957), // Green
        theme,
      ),
      _buildCategoryItem(
        _formatTime(othersTime),
        'Others',
        const Color(0xFF8A8A8A), // Grey
        theme,
      ),
    ],
  );
}

// Add this helper method to format time
String _formatTime(int minutes) {
  final hours = minutes / 60;
  if (hours >= 1) {
    final h = hours.floor();
    final m = (minutes % 60);
    if (m == 0) return '${h}h';
    return '${h}h ${m}m';
  }
  return '${minutes}m';
}

  Widget _buildCategoryItem(String time, String label, Color color, ThemeData theme) {
    return Column(
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              time,
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: const Color(0xFF8A8A8A),
          ),
        ),
      ],
    );
  }

  Widget _buildSearchBar(ThemeData theme) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF2A2A2A),
        borderRadius: BorderRadius.circular(12),
      ),
      child: TextField(
        style: theme.textTheme.bodyMedium,
        decoration: InputDecoration(
          hintText: 'Search apps',
          hintStyle: theme.textTheme.bodyMedium?.copyWith(
            color: const Color(0xFF6A6A6A),
          ),
          prefixIcon: const Icon(
            Icons.search,
            color: Color(0xFF6A6A6A),
          ),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        ),
        onChanged: (value) {
          // TODO: Implement search functionality
        },
      ),
    );
  }

List<AppUsageStats> _getFilteredApps(UsageStatsResponse data) {
  // First filter out the pace app itself
  var apps = data.apps.where((app) => 
    !app.packageName.contains('pace') && 
    app.packageName != 'com.example.pace'
  ).toList();
  
  if (_selectedFilter == null) {
    return apps;
  }
  
  switch (_selectedFilter!) {
    case AppCategory.distracting:
      return apps.where((app) => app.category == AppCategory.distracting).toList();
    case AppCategory.productive:
      return apps.where((app) => app.category == AppCategory.productive).toList();
    case AppCategory.others:
      return apps.where((app) => app.category == AppCategory.others).toList();
  }
}

  String _formatDate(DateTime date) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return '${months[date.month - 1]} ${date.day}';
  }

  String _formatWeekRange() {
    final now = DateTime.now();
    final startOfWeek = now.subtract(Duration(days: 6));
    
    return '${_formatDate(startOfWeek)} - ${_formatDate(now)}';
  }

  void _showHelpDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: Text(
          'Usage Stats Help',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Daily: Shows your app usage for today only.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 8),
            Text(
              'Weekly: Shows your app usage for the past 7 days.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 8),
            Text(
              'Categories help you understand which apps are distracting vs productive.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(
              'Got it',
              style: TextStyle(color: Theme.of(context).colorScheme.primary),
            ),
          ),
        ],
      ),
    );
  }
}
