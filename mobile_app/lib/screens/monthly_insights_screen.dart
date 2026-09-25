import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../config/app_config.dart';
import '../models/transaction.dart';
import '../services/db_service.dart';
import '../utils/type_style.dart';
import '../widgets/month_selector.dart';

const _types = ['Expense', 'Free Money', 'Investment'];

// Fixed palette so a given category keeps the same color across the pie
// chart and the legend/bars below it, cycling for however many distinct
// categories a month happens to have.
const _palette = [
  Color(0xFFEF5350),
  Color(0xFFFFA726),
  Color(0xFF66BB6A),
  Color(0xFF42A5F5),
  Color(0xFFAB47BC),
  Color(0xFF26C6DA),
  Color(0xFFFFCA28),
  Color(0xFF8D6E63),
  Color(0xFF7E57C2),
  Color(0xFFEC407A),
];

/// A deeper look at one month than the Dashboard gives: a pie breakdown by
/// category for a chosen transaction type, and a bar breakdown by
/// subcategory within whichever category is tapped (or overall, if none
/// is). Reads local transactions only (synced or not), same local-first
/// rule as everywhere else.
class MonthlyInsightsScreen extends StatefulWidget {
  final AppConfig config;
  const MonthlyInsightsScreen({super.key, required this.config});

  @override
  State<MonthlyInsightsScreen> createState() => _MonthlyInsightsScreenState();
}

class _MonthlyInsightsScreenState extends State<MonthlyInsightsScreen> {
  late int _year = DateTime.now().year;
  late int _month = DateTime.now().month;
  String _type = 'Expense';
  String? _selectedCategory;
  int? _touchedPieIndex;
  List<LocalTransaction> _all = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final txs = await DbService.listForMonth(_year, _month);
    if (!mounted) return;
    setState(() {
      _all = txs;
      _loading = false;
    });
  }

  void _onMonthChanged((int, int) ym) {
    setState(() {
      _year = ym.$1;
      _month = ym.$2;
      _selectedCategory = null;
      _touchedPieIndex = null;
    });
    _load();
  }

  List<LocalTransaction> get _typeTransactions => _all.where((t) => t.type == _type).toList();

  Map<String, double> get _byCategory {
    final totals = <String, double>{};
    for (final t in _typeTransactions) {
      totals[t.category] = (totals[t.category] ?? 0) + t.amount;
    }
    return totals;
  }

  Map<String, double> get _bySubcategory {
    final source = _selectedCategory == null
        ? _typeTransactions
        : _typeTransactions.where((t) => t.category == _selectedCategory);
    final totals = <String, double>{};
    for (final t in source) {
      totals[t.subcategory] = (totals[t.subcategory] ?? 0) + t.amount;
    }
    return totals;
  }

  @override
  Widget build(BuildContext context) {
    final total = _typeTransactions.fold<double>(0, (sum, t) => sum + t.amount);
    final byCategory = _byCategory.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    final bySubcategory = _bySubcategory.entries.toList()..sort((a, b) => b.value.compareTo(a.value));

    return Scaffold(
      appBar: AppBar(title: const Text('Monthly Insights')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                MonthSelector(year: _year, month: _month, onChanged: _onMonthChanged),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  children: _types.map((t) {
                    final selected = t == _type;
                    return ChoiceChip(
                      label: Text(t),
                      avatar: Icon(TypeStyle.icon(t),
                          size: 18, color: selected ? Colors.white : TypeStyle.color(t)),
                      selected: selected,
                      selectedColor: TypeStyle.color(t),
                      labelStyle: TextStyle(color: selected ? Colors.white : null),
                      onSelected: (_) => setState(() {
                        _type = t;
                        _selectedCategory = null;
                        _touchedPieIndex = null;
                      }),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 20),
                Text('Total: ${total.toStringAsFixed(2)} DT',
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 12),
                if (byCategory.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 32),
                    child: Center(child: Text('No transactions this month.')),
                  )
                else ...[
                  Text('By category', style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 8),
                  Text(
                    'Tap a slice or a row to see its subcategories',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 220,
                    child: PieChart(
                      PieChartData(
                        sectionsSpace: 2,
                        centerSpaceRadius: 40,
                        pieTouchData: PieTouchData(
                          touchCallback: (event, response) {
                            if (!event.isInterestedForInteractions ||
                                response?.touchedSection == null) {
                              return;
                            }
                            final i = response!.touchedSection!.touchedSectionIndex;
                            if (i < 0 || i >= byCategory.length) return;
                            setState(() {
                              _touchedPieIndex = i;
                              _selectedCategory = byCategory[i].key;
                            });
                          },
                        ),
                        sections: [
                          for (var i = 0; i < byCategory.length; i++)
                            PieChartSectionData(
                              value: byCategory[i].value,
                              color: _palette[i % _palette.length],
                              title: '${(byCategory[i].value / total * 100).toStringAsFixed(0)}%',
                              radius: _touchedPieIndex == i ? 65 : 58,
                              titleStyle: const TextStyle(
                                  fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white),
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  for (var i = 0; i < byCategory.length; i++)
                    _LegendRow(
                      color: _palette[i % _palette.length],
                      label: byCategory[i].key,
                      amount: byCategory[i].value,
                      selected: _selectedCategory == byCategory[i].key,
                      onTap: () => setState(() {
                        _selectedCategory = _selectedCategory == byCategory[i].key ? null : byCategory[i].key;
                        _touchedPieIndex = _selectedCategory == null ? null : i;
                      }),
                    ),
                  const SizedBox(height: 24),
                  Text(
                    _selectedCategory == null
                        ? 'By subcategory (all categories)'
                        : 'By subcategory - ${_selectedCategory!}',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 220,
                    child: _SubcategoryBarChart(entries: bySubcategory),
                  ),
                ],
              ],
            ),
    );
  }
}

class _LegendRow extends StatelessWidget {
  final Color color;
  final String label;
  final double amount;
  final bool selected;
  final VoidCallback onTap;

  const _LegendRow({
    required this.color,
    required this.label,
    required this.amount,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        decoration: BoxDecoration(
          color: selected ? Theme.of(context).colorScheme.surfaceContainerHighest : null,
          borderRadius: BorderRadius.circular(8),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(
          children: [
            Container(width: 12, height: 12, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
            const SizedBox(width: 10),
            Expanded(
              child: Text(label,
                  style: TextStyle(fontWeight: selected ? FontWeight.bold : FontWeight.normal)),
            ),
            Text('${amount.toStringAsFixed(2)} DT', style: const TextStyle(fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}

class _SubcategoryBarChart extends StatelessWidget {
  final List<MapEntry<String, double>> entries;
  const _SubcategoryBarChart({required this.entries});

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) return const Center(child: Text('No data.'));
    // Cap to the top 8 so labels stay legible on a phone-width chart.
    final top = entries.take(8).toList();
    final maxY = top.first.value * 1.2;

    return BarChart(
      BarChartData(
        maxY: maxY,
        barGroups: [
          for (var i = 0; i < top.length; i++)
            BarChartGroupData(x: i, barRods: [
              BarChartRodData(
                toY: top[i].value,
                color: _palette[i % _palette.length],
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
              reservedSize: 36,
              getTitlesWidget: (value, meta) {
                final i = value.toInt();
                if (i < 0 || i >= top.length) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Transform.rotate(
                    angle: -0.5,
                    child: Text(top[i].key, style: const TextStyle(fontSize: 9)),
                  ),
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
