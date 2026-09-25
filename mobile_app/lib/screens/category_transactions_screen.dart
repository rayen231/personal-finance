import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../config/app_config.dart';
import '../models/transaction.dart';
import '../services/db_service.dart';
import '../utils/type_style.dart';
import '../widgets/month_selector.dart';
import 'edit_transaction_screen.dart';

/// Reached by tapping a Dashboard stat card ("Necessary Expenses", "Free
/// Money Spent", "Investments") - all transactions of that one type, with a
/// month selector and a category filter, reading local cache only (same
/// local-first rule as every other screen).
class CategoryTransactionsScreen extends StatefulWidget {
  final AppConfig config;
  final String type; // Expense | Free Money | Investment
  const CategoryTransactionsScreen({super.key, required this.config, required this.type});

  @override
  State<CategoryTransactionsScreen> createState() => _CategoryTransactionsScreenState();
}

class _CategoryTransactionsScreenState extends State<CategoryTransactionsScreen> {
  late int _year = DateTime.now().year;
  late int _month = DateTime.now().month;
  String? _categoryFilter; // null = All
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
      _all = txs.where((t) => t.type == widget.type).toList();
      _loading = false;
    });
  }

  void _onMonthChanged((int, int) ym) {
    setState(() {
      _year = ym.$1;
      _month = ym.$2;
      _categoryFilter = null;
    });
    _load();
  }

  List<String> get _categories => _all.map((t) => t.category).toSet().toList()..sort();

  List<LocalTransaction> get _filtered =>
      _categoryFilter == null ? _all : _all.where((t) => t.category == _categoryFilter).toList();

  Map<String, List<LocalTransaction>> get _groupedByDay {
    final map = <String, List<LocalTransaction>>{};
    for (final t in _filtered) {
      final key = DateFormat('yyyy-MM-dd').format(t.date);
      map.putIfAbsent(key, () => []).add(t);
    }
    return map;
  }

  Future<void> _openTransaction(LocalTransaction tx) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => EditTransactionScreen(tx: tx)),
    );
    if (changed == true) await _load();
  }

  @override
  Widget build(BuildContext context) {
    final total = _filtered.fold<double>(0, (sum, t) => sum + t.amount);
    final grouped = _groupedByDay;
    final days = grouped.keys.toList()..sort((a, b) => b.compareTo(a));

    return Scaffold(
      appBar: AppBar(title: Text(widget.type)),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: MonthSelector(year: _year, month: _month, onChanged: _onMonthChanged),
          ),
          if (!_loading && _categories.length > 1)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: SizedBox(
                height: 40,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: const Text('All'),
                        selected: _categoryFilter == null,
                        onSelected: (_) => setState(() => _categoryFilter = null),
                      ),
                    ),
                    for (final c in _categories)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          label: Text(c),
                          selected: _categoryFilter == c,
                          onSelected: (_) => setState(() => _categoryFilter = c),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          if (!_loading)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Total', style: Theme.of(context).textTheme.titleSmall),
                  Text(
                    '${total.toStringAsFixed(2)} DT',
                    style: Theme.of(context)
                        .textTheme
                        .titleSmall
                        ?.copyWith(fontWeight: FontWeight.bold, color: TypeStyle.color(widget.type)),
                  ),
                ],
              ),
            ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _filtered.isEmpty
                    ? const Center(child: Text('No transactions this month.'))
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        itemCount: days.length,
                        itemBuilder: (context, i) {
                          final day = days[i];
                          final dayTxs = grouped[day]!;
                          final dayTotal = dayTxs.fold<double>(0, (sum, t) => sum + t.amount);
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Padding(
                                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      DateFormat('EEEE, MMM d').format(DateTime.parse(day)),
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleSmall
                                          ?.copyWith(color: Theme.of(context).colorScheme.primary),
                                    ),
                                    Text('${dayTotal.toStringAsFixed(2)} DT',
                                        style: Theme.of(context).textTheme.bodySmall),
                                  ],
                                ),
                              ),
                              for (final t in dayTxs)
                                ListTile(
                                  onTap: () => _openTransaction(t),
                                  leading: CircleAvatar(
                                    backgroundColor: TypeStyle.color(t.type).withValues(alpha: 0.15),
                                    child: Icon(TypeStyle.icon(t.type), color: TypeStyle.color(t.type)),
                                  ),
                                  title: Text('${t.category} / ${t.subcategory}'),
                                  subtitle: Text(t.item),
                                  trailing: Text(
                                    '${t.amount.toStringAsFixed(2)} DT',
                                    style: const TextStyle(fontWeight: FontWeight.bold),
                                  ),
                                ),
                              const Divider(height: 1),
                            ],
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}
