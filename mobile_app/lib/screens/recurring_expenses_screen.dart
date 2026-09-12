import 'package:flutter/material.dart';

import '../config/app_config.dart';
import '../services/api_client.dart';
import '../services/data_refresh_service.dart';
import '../services/db_service.dart';
import '../services/sync_service.dart';

class RecurringExpensesScreen extends StatefulWidget {
  final AppConfig config;
  const RecurringExpensesScreen({super.key, required this.config});

  @override
  State<RecurringExpensesScreen> createState() => _RecurringExpensesScreenState();
}

class _RecurringExpensesScreenState extends State<RecurringExpensesScreen> {
  List<Map<String, dynamic>> _expenses = [];
  DateTime? _lastUpdated;
  bool _loading = true;
  bool _refreshing = false;

  int get _year => DateTime.now().year;

  @override
  void initState() {
    super.initState();
    _loadFromCache();
  }

  Future<void> _loadFromCache() async {
    setState(() => _loading = true);
    final cached = await DbService.getCache(DataRefreshService.setupKey(_year));
    if (!mounted) return;
    final setup = cached?.$1 as Map<String, dynamic>?;
    setState(() {
      _expenses = setup == null
          ? []
          : (setup['recurring_expenses'] as List).cast<Map<String, dynamic>>();
      _lastUpdated = cached?.$2;
      _loading = false;
    });
  }

  // Pulling down must never silently discard local edits that haven't
  // reached the server yet - see income_screen.dart's _refreshFromServer
  // for the full rationale.
  Future<void> _refreshFromServer() async {
    setState(() => _refreshing = true);
    try {
      final api = ApiClient(widget.config);
      await SyncService(api).processPendingOps();
      final setup = await api.getSetup(_year);
      await DbService.setCache(DataRefreshService.setupKey(_year), setup);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Refresh failed: $e')));
      }
    }
    await _loadFromCache();
    if (mounted) setState(() => _refreshing = false);
  }

  IconData _iconFor(String? frequency) => switch (frequency) {
        'Weekly' => Icons.calendar_view_week,
        'Monthly' => Icons.calendar_month,
        'Every 3 months' => Icons.event_repeat,
        'Every 6 months' => Icons.event_repeat,
        'Yearly' => Icons.event,
        _ => Icons.repeat,
      };

  @override
  Widget build(BuildContext context) {
    final totalMonthlyReserve =
        _expenses.fold<double>(0, (sum, e) => sum + (e['monthly_reserve'] as num).toDouble());

    return Scaffold(
      appBar: AppBar(
        title: const Text('Recurring Expenses'),
        actions: [
          IconButton(
            icon: _refreshing
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.sync),
            onPressed: _refreshing ? null : _refreshFromServer,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _refreshFromServer,
              child: _expenses.isEmpty
                  ? ListView(
                      children: [
                        const SizedBox(height: 120),
                        Center(
                          child: Text(
                            _lastUpdated == null
                                ? 'No cached data yet - pull down to sync.'
                                : 'No recurring expenses set up.',
                          ),
                        ),
                      ],
                    )
                  : ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        Card(
                          color: Theme.of(context).colorScheme.primaryContainer,
                          child: Padding(
                            padding: const EdgeInsets.all(20),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  'Total monthly reserve',
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleSmall
                                      ?.copyWith(color: Theme.of(context).colorScheme.onPrimaryContainer),
                                ),
                                Text(
                                  '${totalMonthlyReserve.toStringAsFixed(2)} DT',
                                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                        fontWeight: FontWeight.bold,
                                        color: Theme.of(context).colorScheme.onPrimaryContainer,
                                      ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        for (final e in _expenses)
                          Card(
                            margin: const EdgeInsets.only(bottom: 10),
                            child: ListTile(
                              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                              leading: CircleAvatar(
                                backgroundColor:
                                    Theme.of(context).colorScheme.secondaryContainer,
                                child: Icon(
                                  _iconFor(e['frequency'] as String?),
                                  color: Theme.of(context).colorScheme.onSecondaryContainer,
                                ),
                              ),
                              title: Text(e['expense'] as String,
                                  style: const TextStyle(fontWeight: FontWeight.w600)),
                              subtitle: Text(
                                '${e['category'] ?? '-'} • ${e['frequency'] ?? '-'}'
                                '${(e['notes'] as String?)?.isNotEmpty == true ? '\n${e['notes']}' : ''}',
                              ),
                              isThreeLine: (e['notes'] as String?)?.isNotEmpty == true,
                              trailing: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(
                                    '${(e['expected_amount'] as num).toStringAsFixed(2)} DT',
                                    style: const TextStyle(fontWeight: FontWeight.bold),
                                  ),
                                  Text(
                                    '~${(e['monthly_reserve'] as num).toStringAsFixed(2)}/mo',
                                    style: Theme.of(context).textTheme.bodySmall,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        const SizedBox(height: 8),
                        Center(
                          child: Text(
                            'Managed directly in the Excel workbook - read-only here.',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                      ],
                    ),
            ),
    );
  }
}
