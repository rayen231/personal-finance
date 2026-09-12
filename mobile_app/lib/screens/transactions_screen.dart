import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../config/app_config.dart';
import '../models/transaction.dart';
import '../services/api_client.dart';
import '../services/db_service.dart';
import '../services/import_service.dart';
import '../utils/type_style.dart';

class TransactionsScreen extends StatefulWidget {
  final AppConfig config;
  const TransactionsScreen({super.key, required this.config});

  @override
  State<TransactionsScreen> createState() => TransactionsScreenState();
}

class TransactionsScreenState extends State<TransactionsScreen> {
  List<LocalTransaction> _transactions = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    refresh();
  }

  /// Public so HomeShell can trigger a reload after Add Transaction closes.
  Future<void> refresh() async {
    setState(() => _loading = true);
    final now = DateTime.now();
    try {
      await ImportService(ApiClient(widget.config)).importMonth(now.year, now.month);
    } catch (_) {
      // Import is best-effort for display purposes; local data still shows.
    }
    final txs = await DbService.listForMonth(now.year, now.month);
    if (!mounted) return;
    setState(() {
      _transactions = txs;
      _loading = false;
    });
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
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_transactions.isEmpty) {
      return RefreshIndicator(
        onRefresh: refresh,
        child: ListView(
          children: const [
            SizedBox(height: 120),
            Center(child: Text('No transactions this month yet.')),
          ],
        ),
      );
    }

    final grouped = _groupedByDay;
    final days = grouped.keys.toList()..sort((a, b) => b.compareTo(a));

    return RefreshIndicator(
      onRefresh: refresh,
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
    );
  }
}
