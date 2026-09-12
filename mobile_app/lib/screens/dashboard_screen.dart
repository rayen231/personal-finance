import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../config/app_config.dart';
import '../models/transaction.dart';
import '../services/api_client.dart';
import '../services/db_service.dart';
import '../services/import_service.dart';
import '../utils/type_style.dart';

class DashboardScreen extends StatefulWidget {
  final AppConfig config;
  const DashboardScreen({super.key, required this.config});

  @override
  State<DashboardScreen> createState() => DashboardScreenState();
}

class DashboardScreenState extends State<DashboardScreen> {
  final _now = DateTime.now();
  Map<String, dynamic>? _summary;
  List<LocalTransaction> _monthTransactions = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// Public so HomeShell can trigger a reload after Add Transaction closes.
  Future<void> refresh() => _load();

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final api = ApiClient(widget.config);
      await ImportService(api).importMonth(_now.year, _now.month);
      final summary = await api.getSummary(_now.year, _now.month);
      final txs = await DbService.listForMonth(_now.year, _now.month);
      setState(() {
        _summary = summary;
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
              FilledButton(onPressed: _load, child: const Text('Retry')),
            ],
          ),
        ),
      );
    }

    final s = _summary!;
    final income = s['income'] as Map<String, dynamic>;
    final freeMoney = s['free_money'] as Map<String, dynamic>;

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            _monthLabel(_now),
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 12),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            childAspectRatio: 1.6,
            children: [
              _StatCard(
                label: 'Income (actual)',
                value: income['actual'],
                icon: Icons.account_balance_wallet,
                color: Colors.green,
              ),
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
              _StatCard(
                label: 'Total Savings',
                value: s['total_savings'],
                icon: Icons.account_balance,
                color: Colors.indigo,
              ),
            ],
          ),
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
      ),
    );
  }

  String _monthLabel(DateTime d) {
    const months = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December',
    ];
    return '${months[d.month - 1]} ${d.year}';
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
            Icon(icon, color: color),
            Text(label, style: Theme.of(context).textTheme.bodySmall),
            Text(
              '${amount.toStringAsFixed(2)} DT',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
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
