import 'package:flutter/material.dart';
import 'package:installed_apps/installed_apps.dart';
import 'package:installed_apps/app_info.dart';

class AppSelectorScreen extends StatefulWidget {
  const AppSelectorScreen({super.key});

  @override
  State<AppSelectorScreen> createState() => _AppSelectorScreenState();
}

class _AppSelectorScreenState extends State<AppSelectorScreen> {
  final _searchController = TextEditingController();
  List<AppInfo> _installedApps = [];
  List<AppInfo> _filteredApps = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadInstalledApps();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadInstalledApps() async {
    try {
      final apps = await InstalledApps.getInstalledApps(true, true);
      apps.removeWhere((app) => app.packageName == 'com.example.pace');
      apps.sort((a, b) => a.name.compareTo(b.name));
      if (mounted) {
        setState(() {
          _installedApps = apps;
          _filteredApps = apps;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _filterApps(String query) {
    setState(() {
      if (query.isEmpty) {
        _filteredApps = _installedApps;
      } else {
        final lowerQuery = query.toLowerCase();
        _filteredApps = _installedApps
            .where(
              (app) =>
                  app.name.toLowerCase().contains(lowerQuery) ||
                  app.packageName.toLowerCase().contains(lowerQuery),
            )
            .toList();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Select App')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: _searchController,
              onChanged: _filterApps,
              decoration: InputDecoration(
                hintText: 'Search apps...',
                prefixIcon: const Icon(Icons.search),
                filled: true,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _filteredApps.isEmpty
                ? Center(
                    child: Text(
                      'No apps found',
                      style: theme.textTheme.bodyMedium,
                    ),
                  )
                : ListView.builder(
                    itemCount: _filteredApps.length,
                    itemBuilder: (context, index) {
                      final app = _filteredApps[index];
                      return ListTile(
                        leading: app.icon != null
                            ? Image.memory(
                                app.icon!,
                                width: 40,
                                height: 40,
                              )
                            : const Icon(Icons.android),
                        title: Text(app.name),
                        subtitle: Text(
                          app.packageName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall,
                        ),
                        onTap: () => Navigator.pop(context, {
                          'packageName': app.packageName,
                          'appName': app.name,
                        }),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
