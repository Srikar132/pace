import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pace/data/models/app_limit_model.dart';
import 'package:pace/presentation/providers/app_limits_provider.dart';
import 'package:pace/presentation/screens/app_selector_screen.dart';
import 'package:pace/services/app_limit_native_service.dart';

class AddAppLimitScreen extends ConsumerStatefulWidget {
  final String userId;
  final AppLimitModel? existingLimit;

  const AddAppLimitScreen({
    super.key,
    required this.userId,
    this.existingLimit,
  });

  @override
  ConsumerState<AddAppLimitScreen> createState() => _AddAppLimitScreenState();
}

class _AddAppLimitScreenState extends ConsumerState<AddAppLimitScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nativeService = AppLimitNativeService();

  // Form fields
  String? _packageName;
  String? _appName;
  int _dailyLimitHours = 1;
  int _dailyLimitMinutes = 0;
  int _weeklyLimitHours = 0;
  int _weeklyLimitMinutes = 0;
  String _actionOnExceed = 'warn';
  bool _isActive = true;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    if (widget.existingLimit != null) {
      _initializeFromExistingLimit();
    }
  }

  void _initializeFromExistingLimit() {
    final limit = widget.existingLimit!;
    _packageName = limit.packageName;
    _appName = limit.appName;
    _dailyLimitHours = limit.dailyLimit ~/ 60;
    _dailyLimitMinutes = limit.dailyLimit % 60;
    _weeklyLimitHours = limit.weeklyLimit ~/ 60;
    _weeklyLimitMinutes = limit.weeklyLimit % 60;
    _actionOnExceed = limit.actionOnExceed;
    _isActive = limit.isActive;
  }

  bool get _isEditMode => widget.existingLimit != null;

  int get _totalDailyMinutes => (_dailyLimitHours * 60) + _dailyLimitMinutes;
  int get _totalWeeklyMinutes => (_weeklyLimitHours * 60) + _weeklyLimitMinutes;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditMode ? 'Edit App Limit' : 'Add App Limit'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // App Selection Card
              _buildAppSelectionCard(),
              const SizedBox(height: 24),

              // Daily Limit Section
              _buildDailyLimitSection(),
              const SizedBox(height: 24),

              // Weekly Limit Section (Optional)
              _buildWeeklyLimitSection(),
              const SizedBox(height: 24),

              // Action on Exceed Section
              _buildActionSection(),
              const SizedBox(height: 24),

              // Active Toggle
              _buildActiveToggle(),
              const SizedBox(height: 32),

              // Save Button
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: _isSaving ? null : _saveLimit,
                  style: ElevatedButton.styleFrom(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: _isSaving
                      ? const CircularProgressIndicator()
                      : Text(
                          _isEditMode ? 'Update Limit' : 'Add Limit',
                          style: const TextStyle(fontSize: 18),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAppSelectionCard() {
    return Card(
      elevation: 2,
      child: InkWell(
        onTap: _isEditMode ? null : _selectApp,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: _appName != null
                      ? Colors.primaries[_appName!.hashCode %
                            Colors.primaries.length]
                      : Colors.grey[300],
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Center(
                  child: _appName != null
                      ? Text(
                          _appName![0].toUpperCase(),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                          ),
                        )
                      : const Icon(Icons.apps, color: Colors.white, size: 32),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _appName ?? 'Select App',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    if (_packageName != null)
                      Text(
                        _packageName!,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Colors.grey[600],
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
              if (!_isEditMode)
                const Icon(Icons.chevron_right, color: Colors.grey),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDailyLimitSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Daily Limit',
          style: Theme.of(
            context,
          ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Text(
          'Set maximum usage time per day',
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(color: Colors.grey[600]),
        ),
        const SizedBox(height: 16),
        Card(
          elevation: 1,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Hours',
                        style: Theme.of(context).textTheme.labelMedium,
                      ),
                      const SizedBox(height: 8),
                      DropdownButtonFormField<int>(
                        initialValue: _dailyLimitHours,
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                          contentPadding: EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                        ),
                        items: List.generate(
                          24,
                          (i) =>
                              DropdownMenuItem(value: i, child: Text('$i hr')),
                        ),
                        onChanged: (value) {
                          setState(() => _dailyLimitHours = value ?? 0);
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Minutes',
                        style: Theme.of(context).textTheme.labelMedium,
                      ),
                      const SizedBox(height: 8),
                      DropdownButtonFormField<int>(
                        initialValue: _dailyLimitMinutes,
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                          contentPadding: EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                        ),
                        items: [0, 15, 30, 45]
                            .map(
                              (i) => DropdownMenuItem(
                                value: i,
                                child: Text('$i min'),
                              ),
                            )
                            .toList(),
                        onChanged: (value) {
                          setState(() => _dailyLimitMinutes = value ?? 0);
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.blue[50],
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              const Icon(Icons.info_outline, color: Colors.blue, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Total: $_totalDailyMinutes minutes per day',
                  style: const TextStyle(
                    color: Colors.blue,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildWeeklyLimitSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'Weekly Limit',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
            ),
            const Spacer(),
            Text(
              'Optional',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Colors.grey[600],
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          'Set maximum usage time per week',
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(color: Colors.grey[600]),
        ),
        const SizedBox(height: 16),
        Card(
          elevation: 1,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Hours',
                        style: Theme.of(context).textTheme.labelMedium,
                      ),
                      const SizedBox(height: 8),
                      DropdownButtonFormField<int>(
                        initialValue: _weeklyLimitHours,
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                          contentPadding: EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                        ),
                        items: List.generate(
                          49,
                          (i) =>
                              DropdownMenuItem(value: i, child: Text('$i hr')),
                        ),
                        onChanged: (value) {
                          setState(() => _weeklyLimitHours = value ?? 0);
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Minutes',
                        style: Theme.of(context).textTheme.labelMedium,
                      ),
                      const SizedBox(height: 8),
                      DropdownButtonFormField<int>(
                        initialValue: _weeklyLimitMinutes,
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                          contentPadding: EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                        ),
                        items: [0, 15, 30, 45]
                            .map(
                              (i) => DropdownMenuItem(
                                value: i,
                                child: Text('$i min'),
                              ),
                            )
                            .toList(),
                        onChanged: (value) {
                          setState(() => _weeklyLimitMinutes = value ?? 0);
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        if (_totalWeeklyMinutes > 0) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.blue[50],
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                const Icon(Icons.info_outline, color: Colors.blue, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Total: $_totalWeeklyMinutes minutes per week',
                    style: const TextStyle(
                      color: Colors.blue,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildActionSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Action When Limit Exceeded',
          style: Theme.of(
            context,
          ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Text(
          'Choose what happens when the limit is reached',
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(color: Colors.grey[600]),
        ),
        const SizedBox(height: 16),
        RadioGroup<String>(
          groupValue: _actionOnExceed,
          onChanged: (value) {
            setState(() => _actionOnExceed = value!);
          },
          child: Column(
            children: [
              _ActionOption(
                value: 'block',
                groupValue: _actionOnExceed,
                title: 'Block App',
                description: 'Hard block - app cannot be opened',
                icon: Icons.block,
                color: Colors.red,
                onChanged: (value) {
                  setState(() => _actionOnExceed = value!);
                },
              ),
              const SizedBox(height: 12),
              _ActionOption(
                value: 'warn',
                groupValue: _actionOnExceed,
                title: 'Show Warning',
                description: 'Show warning overlay that can be dismissed',
                icon: Icons.warning,
                color: Colors.orange,
                onChanged: (value) {
                  setState(() => _actionOnExceed = value!);
                },
              ),
              const SizedBox(height: 12),
              _ActionOption(
                value: 'notify',
                groupValue: _actionOnExceed,
                title: 'Notify Only',
                description: 'Send notification but allow app to open',
                icon: Icons.notifications,
                color: Colors.blue,
                onChanged: (value) {
                  setState(() => _actionOnExceed = value!);
                },
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildActiveToggle() {
    return Card(
      elevation: 1,
      child: SwitchListTile(
        value: _isActive,
        onChanged: (value) {
          setState(() => _isActive = value);
        },
        title: const Text('Enable Limit'),
        subtitle: Text(
          _isActive
              ? 'This limit is currently active'
              : 'This limit is currently disabled',
        ),
        secondary: Icon(
          _isActive ? Icons.check_circle : Icons.cancel,
          color: _isActive ? Colors.green : Colors.grey,
        ),
      ),
    );
  }

  Future<void> _selectApp() async {
    final result = await Navigator.push<Map<String, String>>(
      context,
      MaterialPageRoute(builder: (context) => const AppSelectorScreen()),
    );

    if (result != null) {
      setState(() {
        _packageName = result['packageName'];
        _appName = result['appName'];
      });
    }
  }

  Future<void> _saveLimit() async {
    if (_packageName == null || _appName == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Please select an app')));
      return;
    }

    if (_totalDailyMinutes == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please set a daily limit greater than 0'),
        ),
      );
      return;
    }

    setState(() => _isSaving = true);

    try {
      final limit = AppLimitModel(
        packageName: _packageName!,
        appName: _appName!,
        dailyLimit: _totalDailyMinutes,
        weeklyLimit: _totalWeeklyMinutes,
        isActive: _isActive,
        actionOnExceed: _actionOnExceed,
      );

      // Save to Firebase
      await ref
          .read(appLimitNotifierProvider.notifier)
          .setAppLimit(widget.userId, limit);

      // Sync to native service
      await _nativeService.setAppLimit(limit.packageName, limit.dailyLimit);

      if (mounted) {
        Navigator.pop(context, true);
      }
    } catch (e) {
      setState(() => _isSaving = false);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error saving limit: $e')));
      }
    }
  }
}

class _ActionOption extends StatelessWidget {
  final String value;
  final String groupValue;
  final String title;
  final String description;
  final IconData icon;
  final Color color;
  final ValueChanged<String?> onChanged;

  const _ActionOption({
    required this.value,
    required this.groupValue,
    required this.title,
    required this.description,
    required this.icon,
    required this.color,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final isSelected = value == groupValue;

    return Card(
      elevation: isSelected ? 3 : 1,
      color: isSelected ? color.withValues(alpha: 0.1) : null,
      child: InkWell(
        onTap: () => onChanged(value),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Radio<String>(value: value, activeColor: color),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: color, size: 28),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: isSelected ? color : null,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      description,
                      style: Theme.of(
                        context,
                      ).textTheme.bodySmall?.copyWith(color: Colors.grey[600]),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
