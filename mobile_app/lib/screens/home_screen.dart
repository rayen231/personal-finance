import 'dart:async';

import 'package:flutter/material.dart';

import '../config/app_config.dart';
import '../services/api_client.dart';
import '../services/sync_service.dart';
import 'add_transaction_screen.dart';
import 'dashboard_screen.dart';
import 'settings_screen.dart';
import 'transactions_screen.dart';

/// Top-level shell: bottom nav between Dashboard and Transactions, with
/// Sync Now / Settings in the app bar and an Add Transaction FAB.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  AppConfig? _config;
  int _tabIndex = 0;
  bool _syncing = false;
  Timer? _hourlyTimer;

  final _dashboardKey = GlobalKey<DashboardScreenState>();
  final _transactionsKey = GlobalKey<TransactionsScreenState>();

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

    // Best-effort "roughly hourly" sync while the app is open. Real
    // background sync (app closed/killed) would need platform-specific
    // work (e.g. WorkManager on Android) - out of scope for this version.
    _hourlyTimer = Timer.periodic(const Duration(hours: 1), (_) => _sync());
  }

  Future<void> _refreshTabs() async {
    await _dashboardKey.currentState?.refresh();
    await _transactionsKey.currentState?.refresh();
  }

  Future<void> _openSettings() async {
    if (_config == null) return;
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => SettingsScreen(config: _config!)),
    );
    if (changed == true) {
      final config = await AppConfig.load();
      setState(() => _config = config);
      await _refreshTabs();
    }
  }

  Future<void> _openAddTransaction() async {
    if (_config == null) return;
    final added = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => AddTransactionScreen(config: _config!)),
    );
    if (added == true) {
      await _refreshTabs();
    }
  }

  Future<void> _sync() async {
    if (_config == null || !_config!.isConfigured) return;
    setState(() => _syncing = true);
    try {
      final outcome = await SyncService(ApiClient(_config!)).syncPending();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
            outcome.failedCount == 0
                ? 'Synced ${outcome.processedCount} transaction(s).'
                : 'Synced ${outcome.processedCount}, ${outcome.failedCount} failed.',
          ),
        ));
      }
      await _refreshTabs();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Sync failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_config == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final titles = ['Dashboard', 'Transactions'];

    return Scaffold(
      appBar: AppBar(
        title: Text(titles[_tabIndex]),
        actions: [
          IconButton(
            icon: _syncing
                ? const SizedBox(
                    width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.sync),
            tooltip: 'Sync Now',
            onPressed: _syncing ? null : _sync,
          ),
          IconButton(icon: const Icon(Icons.settings), onPressed: _openSettings),
        ],
      ),
      body: IndexedStack(
        index: _tabIndex,
        children: [
          DashboardScreen(key: _dashboardKey, config: _config!),
          TransactionsScreen(key: _transactionsKey, config: _config!),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _openAddTransaction,
        child: const Icon(Icons.add),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tabIndex,
        onDestinationSelected: (i) => setState(() => _tabIndex = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.dashboard), label: 'Dashboard'),
          NavigationDestination(icon: Icon(Icons.receipt_long), label: 'Transactions'),
        ],
      ),
    );
  }
}
