import 'package:flutter/material.dart';

import '../config/app_config.dart';
import '../services/api_client.dart';
import '../services/data_refresh_service.dart';
import '../services/db_service.dart';
import '../services/sync_service.dart';
import '../widgets/month_selector.dart';

class IncomeScreen extends StatefulWidget {
  final AppConfig config;
  const IncomeScreen({super.key, required this.config});

  @override
  State<IncomeScreen> createState() => _IncomeScreenState();
}

class _IncomeScreenState extends State<IncomeScreen> {
  late int _year = DateTime.now().year;
  late int _month = DateTime.now().month;
  List<Map<String, dynamic>> _sources = [];
  DateTime? _lastUpdated;
  bool _loading = true;
  bool _refreshing = false;

  ApiClient get _api => ApiClient(widget.config);

  @override
  void initState() {
    super.initState();
    _loadFromCache();
  }

  Future<void> _loadFromCache() async {
    setState(() => _loading = true);
    final cached = await DbService.getCache(DataRefreshService.incomeKey(_year, _month));
    if (!mounted) return;
    setState(() {
      _sources = cached == null ? [] : (cached.$1 as List).cast<Map<String, dynamic>>();
      _lastUpdated = cached?.$2;
      _loading = false;
    });
  }

  /// Pulling down syncs the whole app for this month, not just this screen's
  /// own data - it pushes any queued pending ops (and unsynced transactions)
  /// first, same as Sync Now, then refreshes setup/income/plan/summary
  /// together so switching to another screen afterward is already fresh
  /// too. Fetching before pushing would overwrite optimistic local values
  /// with stale server data before they'd ever been sent, making
  /// entered-but-unsynced income look like it "disappeared".
  Future<void> _refreshFromServer() async {
    setState(() => _refreshing = true);
    try {
      await SyncService(_api).syncPending();
      await DataRefreshService(_api).refreshMonth(_year, _month);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Refresh failed: $e')));
      }
    }
    await _loadFromCache();
    if (mounted) setState(() => _refreshing = false);
  }

  void _onMonthChanged((int, int) ym) {
    setState(() {
      _year = ym.$1;
      _month = ym.$2;
    });
    _loadFromCache();
  }

  Future<void> _editSource(Map<String, dynamic> source) async {
    final expectedController =
        TextEditingController(text: (source['expected'] as num).toStringAsFixed(2));
    // Left blank (rather than pre-filled "0.00") when nothing's been
    // received/entered yet, so the user can tell "not yet filled" apart
    // from a genuine zero, and doesn't have to type over a misleading 0.
    final currentActual = source['actual'] as num?;
    final actualController =
        TextEditingController(text: currentActual == null ? '' : currentActual.toStringAsFixed(2));

    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(source['source'] as String),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: expectedController,
              decoration: const InputDecoration(labelText: 'Expected (DT)'),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: actualController,
              decoration: const InputDecoration(
                labelText: 'Actual (DT)',
                hintText: 'Leave blank if not received yet',
              ),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Save')),
        ],
      ),
    );

    if (saved != true) return;

    final expected = double.tryParse(expectedController.text) ?? (source['expected'] as num).toDouble();
    // An empty field means "not received yet" and is sent as null (the
    // server leaves that cell blank) rather than defaulting to 0.
    final actual = actualController.text.trim().isEmpty ? null : double.tryParse(actualController.text);
    final sourceName = source['source'] as String;

    // Queued, not sent immediately - this screen only talks to the API via
    // Sync Now / the hourly timer, same rule as everywhere else. Update
    // the cached copy optimistically so the change shows right away.
    await DbService.addPendingOp(
      'update_income:$_year:$_month:$sourceName',
      'update_income',
      {'year': _year, 'month': _month, 'source': sourceName, 'expected': expected, 'actual': actual},
    );

    final cached = await DbService.getCache(DataRefreshService.incomeKey(_year, _month));
    if (cached != null) {
      final list = List<Map<String, dynamic>>.from((cached.$1 as List).cast<Map<String, dynamic>>());
      final idx = list.indexWhere((s) => s['source'] == sourceName);
      if (idx != -1) {
        list[idx] = {
          'source': sourceName,
          'expected': expected,
          'actual': actual,
          'difference': actual == null ? null : actual - expected,
        };
        await DbService.setCache(DataRefreshService.incomeKey(_year, _month), list);
      }
    }
    await _loadFromCache();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Income')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: MonthSelector(year: _year, month: _month, onChanged: _onMonthChanged),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Text(
              _lastUpdated == null
                  ? 'Never synced - pull down to fetch'
                  : 'Last synced: ${_lastUpdated!.toLocal()}'.split('.').first,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          if (_refreshing) const LinearProgressIndicator(),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : RefreshIndicator(
                    onRefresh: _refreshFromServer,
                    child: _sources.isEmpty
                        ? ListView(
                            children: const [
                              SizedBox(height: 120),
                              Center(child: Text('No cached income data. Pull down to fetch.')),
                            ],
                          )
                        : ListView(
                            padding: const EdgeInsets.all(16),
                            children: [
                              for (final s in _sources)
                                Card(
                                  child: ListTile(
                                    contentPadding:
                                        const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                    title: Text(s['source'] as String),
                                    subtitle: Text(
                                      'Expected: ${(s['expected'] as num).toStringAsFixed(2)} DT',
                                    ),
                                    trailing: Column(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      crossAxisAlignment: CrossAxisAlignment.end,
                                      children: [
                                        Text(
                                          s['actual'] == null
                                              ? 'Not received yet'
                                              : '${(s['actual'] as num).toStringAsFixed(2)} DT',
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            color: s['actual'] == null
                                                ? Theme.of(context).textTheme.bodySmall?.color
                                                : null,
                                          ),
                                        ),
                                        if (s['difference'] != null)
                                          Text(
                                            '${(s['difference'] as num) >= 0 ? '+' : ''}${(s['difference'] as num).toStringAsFixed(2)}',
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: (s['difference'] as num) >= 0
                                                  ? Colors.green
                                                  : Colors.red,
                                            ),
                                          ),
                                      ],
                                    ),
                                    onTap: () => _editSource(s),
                                  ),
                                ),
                            ],
                          ),
                  ),
          ),
        ],
      ),
    );
  }
}
