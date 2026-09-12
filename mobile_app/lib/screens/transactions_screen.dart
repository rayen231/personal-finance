import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../config/app_config.dart';
import '../models/transaction.dart';
import '../services/api_client.dart';
import '../services/data_refresh_service.dart';
import '../services/db_service.dart';
import '../utils/type_style.dart';
import '../widgets/month_selector.dart';
import 'edit_transaction_screen.dart';

class TransactionsScreen extends StatefulWidget {
  final AppConfig config;
  const TransactionsScreen({super.key, required this.config});

  @override
  State<TransactionsScreen> createState() => TransactionsScreenState();
}

class TransactionsScreenState extends State<TransactionsScreen> {
  late int _year = DateTime.now().year;
  late int _month = DateTime.now().month;
  List<LocalTransaction> _transactions = [];
  bool _loading = true;
  bool _refreshing = false;

  @override
  void initState() {
    super.initState();
    _loadFromLocal();
  }

  /// Public so HomeShell can trigger a cheap (no-network) reload after a
  /// local-only change, or after Sync Now already refreshed things itself.
  Future<void> reloadFromCache() => _loadFromLocal();

  Future<void> _loadFromLocal() async {
    setState(() => _loading = true);
    final txs = await DbService.listForMonth(_year, _month);
    if (!mounted) return;
    setState(() {
      _transactions = txs;
      _loading = false;
    });
  }

  Future<void> _refreshFromServer() async {
    setState(() => _refreshing = true);
    try {
      await DataRefreshService(ApiClient(widget.config)).importTransactionsOnly(_year, _month);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Refresh failed: $e')));
      }
    }
    await _loadFromLocal();
    if (mounted) setState(() => _refreshing = false);
  }

  void _onMonthChanged((int, int) ym) {
    setState(() {
      _year = ym.$1;
      _month = ym.$2;
    });
    _loadFromLocal();
  }

  Future<void> _openTransaction(LocalTransaction tx) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => EditTransactionScreen(tx: tx)),
    );
    if (changed == true) await _loadFromLocal();
  }

  Map<String, List<LocalTransaction>> get _groupedByDay {
    final map = <String, List<LocalTransaction>>{};
    for (final t in _transactions) {
      final key = DateFormat('yyyy-MM-dd').format(t.date);
      map.putIfAbsent(key, () => []).add(t);
    }
    return map;
  }

  @override
  Widget build(BuildContext context) {
    final grouped = _groupedByDay;
    final days = grouped.keys.toList()..sort((a, b) => b.compareTo(a));

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: MonthSelector(year: _year, month: _month, onChanged: _onMonthChanged),
        ),
        if (_refreshing) const LinearProgressIndicator(),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _transactions.isEmpty
                  ? RefreshIndicator(
                      onRefresh: _refreshFromServer,
                      child: ListView(
                        children: const [
                          SizedBox(height: 120),
                          Center(child: Text('No transactions this month yet.')),
                        ],
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: _refreshFromServer,
                      child: ListView.builder(
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
                                  trailing: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      Text(
                                        '${t.amount.toStringAsFixed(2)} DT',
                                        style: const TextStyle(fontWeight: FontWeight.bold),
                                      ),
                                      Icon(
                                        t.synced ? Icons.cloud_done : Icons.cloud_upload_outlined,
                                        size: 14,
                                        color: t.synced ? Colors.green : Colors.orange,
                                      ),
                                    ],
                                  ),
                                ),
                              const Divider(height: 1),
                            ],
                          );
                        },
                      ),
                    ),
        ),
      ],
    );
  }
}
