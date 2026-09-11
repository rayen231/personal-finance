import 'dart:async';

import 'package:flutter/material.dart';

import '../config/app_config.dart';
import '../models/transaction.dart';
import '../services/api_client.dart';
import '../services/db_service.dart';
import '../services/sync_service.dart';
import 'add_transaction_screen.dart';
import 'settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  AppConfig? _config;
  List<LocalTransaction> _transactions = [];
  bool _syncing = false;
  String? _syncMessage;
  Timer? _hourlyTimer;

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _hourlyTimer?.cancel();
    super.dispose();
  }

  Future<void> _init() async {
    final config = await AppConfig.load();
    setState(() => _config = config);
    if (!config.isConfigured) {
      await _openSettings();
    }
    await _refresh();

    // Best-effort "roughly hourly" sync while the app is open. Real
    // background sync (app closed/killed) would need platform-specific
    // work (e.g. WorkManager on Android) - out of scope for this version.
    _hourlyTimer = Timer.periodic(const Duration(hours: 1), (_) => _sync());
  }

  Future<void> _refresh() async {
    final txs = await DbService.listAll();
    setState(() => _transactions = txs);
  }

  Future<void> _openSettings() async {
    if (_config == null) return;
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => SettingsScreen(config: _config!)),
    );
    if (changed == true) {
      setState(() => _config = null);
      final config = await AppConfig.load();
      setState(() => _config = config);
    }
  }

  Future<void> _openAddTransaction() async {
    if (_config == null) return;
    final added = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => AddTransactionScreen(config: _config!)),
    );
    if (added == true) {
      await _refresh();
    }
  }

  Future<void> _sync() async {
    if (_config == null || !_config!.isConfigured) return;
    setState(() {
      _syncing = true;
      _syncMessage = null;
    });
    try {
      final outcome = await SyncService(ApiClient(_config!)).syncPending();
      setState(() {
        _syncMessage = outcome.failedCount == 0
            ? 'Synced ${outcome.processedCount} transaction(s).'
            : 'Synced ${outcome.processedCount}, ${outcome.failedCount} failed: '
                '${outcome.failures.map((f) => f['reason']).join('; ')}';
      });
      await _refresh();
    } catch (e) {
      setState(() => _syncMessage = 'Sync failed: $e');
    } finally {
      setState(() => _syncing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_config == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final unsyncedCount = _transactions.where((t) => !t.synced).length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Money Handler'),
        actions: [
          IconButton(icon: const Icon(Icons.settings), onPressed: _openSettings),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    unsyncedCount == 0
                        ? 'All synced'
                        : '$unsyncedCount transaction(s) pending sync',
                  ),
                ),
                FilledButton.icon(
                  onPressed: _syncing ? null : _sync,
                  icon: _syncing
                      ? const SizedBox(
                          width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.sync),
                  label: const Text('Sync Now'),
                ),
              ],
            ),
          ),
          if (_syncMessage != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text(_syncMessage!, style: Theme.of(context).textTheme.bodySmall),
            ),
          const Divider(height: 1),
          Expanded(
            child: _transactions.isEmpty
                ? const Center(child: Text('No transactions yet. Tap + to add one.'))
                : ListView.builder(
                    itemCount: _transactions.length,
                    itemBuilder: (context, i) {
                      final tx = _transactions[i];
                      return ListTile(
                        leading: Icon(tx.synced ? Icons.cloud_done : Icons.cloud_upload_outlined),
                        title: Text('${tx.category} / ${tx.subcategory} - ${tx.item}'),
                        subtitle: Text(
                          '${tx.type} - ${tx.date.toIso8601String().substring(0, 10)}',
                        ),
                        trailing: Text('${tx.amount.toStringAsFixed(2)} DT'),
                      );
                    },
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _openAddTransaction,
        child: const Icon(Icons.add),
      ),
    );
  }
}
