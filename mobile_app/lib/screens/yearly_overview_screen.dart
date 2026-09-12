import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../config/app_config.dart';
import '../services/api_client.dart';

const _monthAbbrev = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

class YearlyOverviewScreen extends StatefulWidget {
  final AppConfig config;
  const YearlyOverviewScreen({super.key, required this.config});

  @override
  State<YearlyOverviewScreen> createState() => _YearlyOverviewScreenState();
}

class _YearlyOverviewScreenState extends State<YearlyOverviewScreen> {
  final _year = DateTime.now().year;
  List<Map<String, dynamic>?> _monthly = List.filled(12, null);
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final api = ApiClient(widget.config);
      // Only fetch through the current month - future months are
      // "Not Started" and would just be zeros anyway.
      final upTo = DateTime.now().year == _year ? DateTime.now().month : 12;
      final results = await Future.wait([
        for (var m = 1; m <= upTo; m++) api.getSummary(_year, m),
      ]);
      setState(() {
        _monthly = List.filled(12, null);
        for (var i = 0; i < results.length; i++) {
          _monthly[i] = results[i];
        }
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('$_year Overview')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text('Error: $_error'))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      Text('Income vs Total Savings', style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 12),
                      SizedBox(height: 220, child: _YearLineChart(monthly: _monthly)),
                      const SizedBox(height: 24),
                      Text('Monthly Breakdown', style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 8),
                      for (var i = 0; i < 12; i++)
                        if (_monthly[i] != null) _MonthRow(month: i + 1, data: _monthly[i]!),
                    ],
                  ),
                ),
    );
  }
}

class _MonthRow extends StatelessWidget {
  final int month;
  final Map<String, dynamic> data;
  const _MonthRow({required this.month, required this.data});

  @override
  Widget build(BuildContext context) {
    final income = (data['income']['actual'] as num).toDouble();
    final necessary = (data['necessary_expenses_actual'] as num).toDouble();
    final savings = (data['total_savings'] as num).toDouble();

    return Card(
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        title: Text(_monthAbbrev[month - 1]),
        subtitle: Text('Income: ${income.toStringAsFixed(0)}  •  Expenses: ${necessary.toStringAsFixed(0)}'),
        trailing: Text(
          '${savings.toStringAsFixed(0)} DT',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: savings >= 0 ? Colors.green : Colors.red,
          ),
        ),
      ),
    );
  }
}

class _YearLineChart extends StatelessWidget {
  final List<Map<String, dynamic>?> monthly;
  const _YearLineChart({required this.monthly});

  @override
  Widget build(BuildContext context) {
    final incomeSpots = <FlSpot>[];
    final savingsSpots = <FlSpot>[];
    for (var i = 0; i < 12; i++) {
      final m = monthly[i];
      if (m == null) continue;
      incomeSpots.add(FlSpot(i.toDouble(), (m['income']['actual'] as num).toDouble()));
      savingsSpots.add(FlSpot(i.toDouble(), (m['total_savings'] as num).toDouble()));
    }

    return LineChart(
      LineChartData(
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          leftTitles: AxisTitles(sideTitles: SideTitles(reservedSize: 40, showTitles: true)),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              getTitlesWidget: (value, meta) {
                final i = value.toInt();
                if (i < 0 || i >= 12) return const SizedBox.shrink();
                return Text(_monthAbbrev[i], style: const TextStyle(fontSize: 10));
              },
            ),
          ),
        ),
        borderData: FlBorderData(show: false),
        gridData: const FlGridData(show: true, drawVerticalLine: false),
        lineBarsData: [
          LineChartBarData(spots: incomeSpots, color: Colors.green, isCurved: false, dotData: const FlDotData(show: true)),
          LineChartBarData(spots: savingsSpots, color: Colors.indigo, isCurved: false, dotData: const FlDotData(show: true)),
        ],
      ),
    );
  }
}
