import 'dart:async';

import 'package:flutter/material.dart';

import '../config/app_config.dart';
import '../services/api_client.dart';
import '../services/data_refresh_service.dart';
import '../services/sync_service.dart';
import 'add_transaction_screen.dart';
import 'dashboard_screen.dart';
import 'income_screen.dart';
import 'manage_categories_screen.dart';
import 'plan_screen.dart';
import 'recurring_expenses_screen.dart';
import 'settings_screen.dart';
import 'transactions_screen.dart';
import 'yearly_overview_screen.dart';

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

  Future<void> _reloadTabsFromCache() async {
    await _dashboardKey.currentState?.reloadFromCache();
    await _transactionsKey.currentState?.reloadFromCache();
  }

  Future<void> _openSettings() async {
    if (_config == null) return;
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => SettingsScreen(config: _config!)),
    );
    if (changed == true) {
      final config = await AppConfig.load();
      setState(() => _config = config);
      await _reloadTabsFromCache();
    }
  }

  Future<void> _openScreen(Widget Function(AppConfig) builder) async {
    if (_config == null) return;
    Navigator.of(context).pop(); // close the drawer
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => builder(_config!)));
    // Income/Plan/Manage Categories/etc. can all change data the Dashboard
    // and Transactions tabs show - reload them from cache (no network call)
    // on return so coming back doesn't show stale figures until the next
    // explicit sync.
    await _reloadTabsFromCache();
  }

  Future<void> _openAddTransaction() async {
    if (_config == null) return;
    final added = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => AddTransactionScreen(config: _config!)),
    );
    if (added == true) {
      await _reloadTabsFromCache();
    }
  }

  Future<void> _sync() async {
    if (_config == null || !_config!.isConfigured) return;
    // Guards against the hourly timer firing while a manual sync (or vice
    // versa) is already in flight - the server-side fix makes a genuine
    // duplicate impossible either way, but there's no reason to fire two
    // redundant network round trips.
    if (_syncing) return;
    setState(() => _syncing = true);
    try {
      final api = ApiClient(_config!);
      final outcome = await SyncService(api).syncPending();
      final now = DateTime.now();
      await DataRefreshService(api).refreshMonth(now.year, now.month);
      if (mounted) {
        final parts = <String>[
          outcome.failedCount == 0
              ? 'Synced ${outcome.processedCount} transaction(s).'
              : 'Synced ${outcome.processedCount}, ${outcome.failedCount} failed.',
          if (outcome.opFailures.isNotEmpty)
            '${outcome.opFailures.length} other change(s) failed.',
        ];
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(parts.join(' '))));
      }
      await _reloadTabsFromCache();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Sync failed: $e')));
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
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.sync),
            tooltip: 'Sync Now',
            onPressed: _syncing ? null : _sync,
          ),
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: _openSettings,
          ),
        ],
      ),
      drawer: Drawer(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(20, 32, 20, 20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Theme.of(context).colorScheme.primary,
                    Theme.of(context).colorScheme.primaryContainer,
                  ],
                ),
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 22,
                    backgroundColor: Colors.white.withValues(alpha: 0.2),
                    child: Icon(
                      Icons.account_balance_wallet,
                      color: Theme.of(context).colorScheme.onPrimary,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'Money Handler',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      color: Theme.of(context).colorScheme.onPrimary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            ListTile(
              leading: const Icon(Icons.account_balance_wallet_outlined),
              title: const Text('Income'),
              onTap: () => _openScreen((c) => IncomeScreen(config: c)),
            ),
            ListTile(
              leading: const Icon(Icons.rule),
              title: const Text('Monthly Plan'),
              onTap: () => _openScreen((c) => PlanScreen(config: c)),
            ),
            ListTile(
              leading: const Icon(Icons.repeat),
              title: const Text('Recurring Expenses'),
              onTap: () =>
                  _openScreen((c) => RecurringExpensesScreen(config: c)),
            ),
            ListTile(
              leading: const Icon(Icons.calendar_view_month),
              title: const Text('Yearly Overview'),
              onTap: () => _openScreen((c) => YearlyOverviewScreen(config: c)),
            ),
            ListTile(
              leading: const Icon(Icons.category_outlined),
              title: const Text('Manage Categories'),
              onTap: () =>
                  _openScreen((c) => ManageCategoriesScreen(config: c)),
            ),
            const Divider(indent: 16, endIndent: 16),
            ListTile(
              leading: const Icon(Icons.settings_outlined),
              title: const Text('Settings'),
              onTap: () {
                Navigator.of(context).pop();
                _openSettings();
              },
            ),
          ],
        ),
      ),
      body: IndexedStack(
        index: _tabIndex,
        children: [
          DashboardScreen(key: _dashboardKey, config: _config!),
          TransactionsScreen(key: _transactionsKey, config: _config!),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openAddTransaction,
        icon: const Icon(Icons.add),
        label: const Text('Add'),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tabIndex,
        onDestinationSelected: (i) => setState(() => _tabIndex = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.dashboard),
            label: 'Dashboard',
          ),
          NavigationDestination(
            icon: Icon(Icons.receipt_long),
            label: 'Transactions',
          ),
        ],
      ),
    );
  }
}
