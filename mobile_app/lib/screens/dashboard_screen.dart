import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../config/app_config.dart';
import '../models/transaction.dart';
import '../services/api_client.dart';
import '../services/data_refresh_service.dart';
import '../services/db_service.dart';
import '../services/sync_service.dart';
import '../utils/type_style.dart';
import '../widgets/month_selector.dart';

class DashboardScreen extends StatefulWidget {
  final AppConfig config;
  const DashboardScreen({super.key, required this.config});

  @override
  State<DashboardScreen> createState() => DashboardScreenState();
}

class DashboardScreenState extends State<DashboardScreen> {
  late int _year = DateTime.now().year;
  late int _month = DateTime.now().month;
  Map<String, dynamic>? _summary;
  List<LocalTransaction> _monthTransactions = [];
  DateTime? _lastUpdated;
  bool _loading = true;
  bool _refreshing = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadFromCache();
  }

  /// Public so HomeShell can trigger a cheap (no-network) reload after a
  /// local-only change (adding a transaction) or after Sync Now already
  /// refreshed the cache itself.
  Future<void> reloadFromCache() => _loadFromCache();

  Future<void> _loadFromCache() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final cached = await DbService.getCache(DataRefreshService.summaryKey(_year, _month));
      final txs = await DbService.listForMonth(_year, _month);
      setState(() {
        _summary = cached?.$1 as Map<String, dynamic>?;
        _lastUpdated = cached?.$2;
        _monthTransactions = txs;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  // Pulling down must never silently discard local edits that haven't
  // reached the server yet - see income_screen.dart's _refreshFromServer
  // for the full rationale.
  Future<void> _refreshFromServer() async {
    setState(() => _refreshing = true);
    try {
      final api = ApiClient(widget.config);
      await SyncService(api).processPendingOps();
      await DataRefreshService(api).refreshMonth(_year, _month);
      await _loadFromCache();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Refresh failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  void _onMonthChanged((int, int) ym) {
    setState(() {
      _year = ym.$1;
      _month = ym.$2;
    });
    _loadFromCache();
  }

  Map<String, double> get _expenseByCategory {
    final totals = <String, double>{};
    for (final t in _monthTransactions.where((t) => t.type == 'Expense')) {
      totals[t.category] = (totals[t.category] ?? 0) + t.amount;
    }
    return totals;
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Could not load dashboard: $_error', textAlign: TextAlign.center),
              const SizedBox(height: 12),
              FilledButton(onPressed: _refreshFromServer, child: const Text('Retry (Sync)')),
            ],
          ),
        ),
      );
    }

    final s = _summary;

    return RefreshIndicator(
      onRefresh: _refreshFromServer,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          MonthSelector(year: _year, month: _month, onChanged: _onMonthChanged),
          const SizedBox(height: 4),
          Center(
            child: Text(
              _lastUpdated == null
                  ? 'Never synced - pull down or tap Sync Now'
                  : 'Last synced: ${_formatWhen(_lastUpdated!)}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          const SizedBox(height: 12),
          if (_refreshing) const LinearProgressIndicator(),
          if (s == null)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 48),
              child: Center(child: Text('No cached data for this month yet.')),
            )
          else ...[
            _buildHeroCard(s),
            const SizedBox(height: 16),
            _buildStats(s),
            const SizedBox(height: 24),
            Text('Spending by category', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            if (_expenseByCategory.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Text('No expenses recorded this month yet.'),
              )
            else
              SizedBox(height: 220, child: _CategoryBarChart(data: _expenseByCategory)),
          ],
        ],
      ),
    );
  }

  Widget _buildHeroCard(Map<String, dynamic> s) {
    final scheme = Theme.of(context).colorScheme;
    final income = s['income'] as Map<String, dynamic>;
    final totalSavings = (s['total_savings'] as num).toDouble();
    final actualIncome = (income['actual'] as num).toDouble();
    final expectedIncome = (income['expected'] as num).toDouble();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [scheme.primary, scheme.tertiary],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Total Savings',
            style: TextStyle(color: scheme.onPrimary.withValues(alpha: 0.85), fontSize: 14),
          ),
          const SizedBox(height: 6),
          Text(
            '${totalSavings.toStringAsFixed(2)} DT',
            style: TextStyle(
              color: scheme.onPrimary,
              fontSize: 34,
              fontWeight: FontWeight.bold,
            ),
          ),
          // Savings/received income are based on what's actually confirmed
          // received or spent so far this month, not the plan - showing
          // "expected" alongside makes clear the plan did register, even
          // when nothing's been marked received yet (both would otherwise
          // show 0 and look like the app lost the entered data).
          if (expectedIncome > 0)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                'Planned income: ${expectedIncome.toStringAsFixed(0)} DT',
                style: TextStyle(color: scheme.onPrimary.withValues(alpha: 0.7), fontSize: 12),
              ),
            ),
          const SizedBox(height: 16),
          Row(
            children: [
              Icon(Icons.arrow_downward, size: 16, color: scheme.onPrimary.withValues(alpha: 0.85)),
              const SizedBox(width: 4),
              Text(
                'Received ${actualIncome.toStringAsFixed(0)} DT',
                style: TextStyle(color: scheme.onPrimary.withValues(alpha: 0.85), fontSize: 13),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStats(Map<String, dynamic> s) {
    final freeMoney = s['free_money'] as Map<String, dynamic>;
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      childAspectRatio: 1.35,
      children: [
        _StatCard(
          label: 'Necessary Expenses',
          value: s['necessary_expenses_actual'],
          icon: Icons.shopping_cart,
          color: TypeStyle.color('Expense'),
        ),
        _StatCard(
          label: 'Free Money Spent',
          value: freeMoney['spent'],
          icon: Icons.celebration,
          color: TypeStyle.color('Free Money'),
        ),
        _StatCard(
          label: 'Investments',
          value: s['investments_actual'],
          icon: Icons.trending_up,
          color: TypeStyle.color('Investment'),
        ),
        _StatCard(
          label: 'Extra Savings',
          value: s['extra_savings'],
          icon: Icons.savings,
          color: Colors.indigo,
        ),
      ],
    );
  }

  String _formatWhen(DateTime d) {
    final diff = DateTime.now().difference(d);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final dynamic value;
  final IconData icon;
  final Color color;

  const _StatCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final amount = (value is num) ? value.toDouble() : 0.0;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: color, size: 18),
            ),
            const SizedBox(height: 6),
            Text(
              label,
              style: Theme.of(context).textTheme.bodySmall,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            Text(
              '${amount.toStringAsFixed(2)} DT',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

class _CategoryBarChart extends StatelessWidget {
  final Map<String, double> data;
  const _CategoryBarChart({required this.data});

  @override
  Widget build(BuildContext context) {
    final entries = data.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    final maxY = entries.map((e) => e.value).reduce((a, b) => a > b ? a : b) * 1.2;

    return BarChart(
      BarChartData(
        maxY: maxY,
        barGroups: [
          for (var i = 0; i < entries.length; i++)
            BarChartGroupData(x: i, barRods: [
              BarChartRodData(
                toY: entries[i].value,
                color: TypeStyle.color('Expense'),
                width: 18,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
              ),
            ]),
        ],
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          leftTitles: AxisTitles(sideTitles: SideTitles(reservedSize: 40, showTitles: true)),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              getTitlesWidget: (value, meta) {
                final i = value.toInt();
                if (i < 0 || i >= entries.length) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(entries[i].key, style: const TextStyle(fontSize: 10)),
                );
              },
            ),
          ),
        ),
        borderData: FlBorderData(show: false),
        gridData: const FlGridData(show: true, drawVerticalLine: false),
      ),
    );
  }
}
