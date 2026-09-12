import 'package:flutter/material.dart';

import '../config/app_config.dart';
import '../services/api_client.dart';
import '../services/data_refresh_service.dart';
import '../services/db_service.dart';

const _listKinds = [
  ('categories', 'expense_categories', 'Expense Categories', false),
  ('free-money-categories', 'free_money_categories', 'Free Money Categories', true),
  ('investment-areas', 'investment_areas', 'Investment Areas', false),
  ('income-sources', 'income_sources', 'Income Sources', true),
];

/// All edits here are queued (pending_ops), same rule as the rest of the
/// app: this screen only talks to the API via Sync Now / the hourly timer
/// / an explicit pull-to-refresh. The cached setup is updated optimistically
/// so changes show immediately.
class ManageCategoriesScreen extends StatefulWidget {
  final AppConfig config;
  const ManageCategoriesScreen({super.key, required this.config});

  @override
  State<ManageCategoriesScreen> createState() => _ManageCategoriesScreenState();
}

class _ManageCategoriesScreenState extends State<ManageCategoriesScreen>
    with SingleTickerProviderStateMixin {
  late final _tabController = TabController(length: _listKinds.length + 1, vsync: this);
  Map<String, dynamic>? _setup;
  bool _loading = true;
  bool _refreshing = false;

  int get _year => DateTime.now().year;

  @override
  void initState() {
    super.initState();
    _loadFromCache();
  }

  Future<void> _loadFromCache() async {
    setState(() => _loading = true);
    final cached = await DbService.getCache(DataRefreshService.setupKey(_year));
    if (!mounted) return;
    setState(() {
      _setup = cached?.$1 as Map<String, dynamic>?;
      _loading = false;
    });
  }

  Future<void> _refreshFromServer() async {
    setState(() => _refreshing = true);
    try {
      final setup = await ApiClient(widget.config).getSetup(_year);
      await DbService.setCache(DataRefreshService.setupKey(_year), setup);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Refresh failed: $e')));
      }
    }
    await _loadFromCache();
    if (mounted) setState(() => _refreshing = false);
  }

  Future<String> _promptText(String title, {String initial = ''}) => showDialog<String>(
        context: context,
        builder: (context) {
          final controller = TextEditingController(text: initial);
          return AlertDialog(
            title: Text(title),
            content: TextField(controller: controller, autofocus: true),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
              FilledButton(
                onPressed: () => Navigator.pop(context, controller.text.trim()),
                child: const Text('Save'),
              ),
            ],
          );
        },
      ).then((v) => v ?? '');

  Future<void> _queue(String opId, String opType, Map<String, dynamic> payload) async {
    await DbService.addPendingOp(opId, opType, payload);
    await _loadFromCache();
  }

  Future<void> _addListValue(String listKind, String jsonKey, String value) async {
    await _queue('add_list:$listKind:$value', 'add_list_value', {
      'year': _year,
      'list_kind': listKind,
      'value': value,
    });
    final setup = Map<String, dynamic>.from(_setup!);
    final list = List<String>.from(setup[jsonKey] as List);
    if (!list.contains(value)) list.add(value);
    setup[jsonKey] = list;
    await DbService.setCache(DataRefreshService.setupKey(_year), setup);
    await _loadFromCache();
  }

  Future<void> _renameListValue(String listKind, String jsonKey, String oldValue, String newValue) async {
    await _queue('rename_list:$listKind:$oldValue', 'rename_list_value', {
      'year': _year,
      'list_kind': listKind,
      'old_value': oldValue,
      'new_value': newValue,
    });
    final setup = Map<String, dynamic>.from(_setup!);
    final list = List<String>.from(setup[jsonKey] as List);
    final idx = list.indexOf(oldValue);
    if (idx != -1) list[idx] = newValue;
    setup[jsonKey] = list;
    await DbService.setCache(DataRefreshService.setupKey(_year), setup);
    await _loadFromCache();
  }

  Future<void> _deleteListValue(String listKind, String jsonKey, String value) async {
    await _queue('delete_list:$listKind:$value', 'delete_list_value', {
      'year': _year,
      'list_kind': listKind,
      'value': value,
    });
    final setup = Map<String, dynamic>.from(_setup!);
    final list = List<String>.from(setup[jsonKey] as List)..remove(value);
    setup[jsonKey] = list;
    await DbService.setCache(DataRefreshService.setupKey(_year), setup);
    await _loadFromCache();
  }

  Future<void> _addSubcategory(String category, String subcategory) async {
    await _queue('add_sub:$category:$subcategory', 'add_subcategory', {
      'year': _year,
      'category': category,
      'subcategory': subcategory,
    });
    final setup = Map<String, dynamic>.from(_setup!);
    final subs = List<Map<String, dynamic>>.from((setup['subcategories'] as List).cast<Map<String, dynamic>>());
    subs.add({'category': category, 'subcategory': subcategory});
    setup['subcategories'] = subs;
    await DbService.setCache(DataRefreshService.setupKey(_year), setup);
    await _loadFromCache();
  }

  Future<void> _renameSubcategory(String category, String oldSub, String newSub) async {
    await _queue('rename_sub:$category:$oldSub', 'rename_subcategory', {
      'year': _year,
      'category': category,
      'old_subcategory': oldSub,
      'new_subcategory': newSub,
    });
    final setup = Map<String, dynamic>.from(_setup!);
    final subs = List<Map<String, dynamic>>.from((setup['subcategories'] as List).cast<Map<String, dynamic>>());
    final idx = subs.indexWhere((p) => p['category'] == category && p['subcategory'] == oldSub);
    if (idx != -1) subs[idx] = {'category': category, 'subcategory': newSub};
    setup['subcategories'] = subs;
    await DbService.setCache(DataRefreshService.setupKey(_year), setup);
    await _loadFromCache();
  }

  Future<void> _deleteSubcategory(String category, String subcategory) async {
    await _queue('delete_sub:$category:$subcategory', 'delete_subcategory', {
      'year': _year,
      'category': category,
      'subcategory': subcategory,
    });
    final setup = Map<String, dynamic>.from(_setup!);
    final subs = List<Map<String, dynamic>>.from((setup['subcategories'] as List).cast<Map<String, dynamic>>())
      ..removeWhere((p) => p['category'] == category && p['subcategory'] == subcategory);
    setup['subcategories'] = subs;
    await DbService.setCache(DataRefreshService.setupKey(_year), setup);
    await _loadFromCache();
  }

  Map<String, dynamic> get _recurringFlags =>
      (_setup?['recurring_flags'] as Map<String, dynamic>?) ??
      {'income_sources': [], 'free_money_categories': [], 'subcategories': []};

  bool _isIncomeSourceRecurring(String source) =>
      (_recurringFlags['income_sources'] as List).contains(source);

  bool _isFreeMoneyCategoryRecurring(String category) =>
      (_recurringFlags['free_money_categories'] as List).contains(category);

  bool _isSubcategoryRecurring(String category, String subcategory) =>
      (_recurringFlags['subcategories'] as List).cast<Map<String, dynamic>>().any(
            (p) => p['category'] == category && p['subcategory'] == subcategory,
          );

  Future<void> _setListValueRecurring(String listKind, String value, bool recurring) async {
    final opType = listKind == 'income-sources'
        ? 'set_income_source_recurring'
        : 'set_free_money_category_recurring';
    final key = listKind == 'income-sources' ? 'source' : 'category';
    await DbService.addPendingOp(
      '$opType:$value',
      opType,
      {'year': _year, key: value, 'recurring': recurring},
    );
    final setup = Map<String, dynamic>.from(_setup!);
    final flags = Map<String, dynamic>.from(
      (setup['recurring_flags'] as Map?) ?? {'income_sources': [], 'free_money_categories': [], 'subcategories': []},
    );
    final flagKey = listKind == 'income-sources' ? 'income_sources' : 'free_money_categories';
    final items = List<String>.from((flags[flagKey] as List?) ?? []);
    if (recurring) {
      if (!items.contains(value)) items.add(value);
    } else {
      items.remove(value);
    }
    flags[flagKey] = items;
    setup['recurring_flags'] = flags;
    await DbService.setCache(DataRefreshService.setupKey(_year), setup);
    await _loadFromCache();
  }

  Future<void> _setSubcategoryRecurring(String category, String subcategory, bool recurring) async {
    await DbService.addPendingOp(
      'set_subcategory_recurring:$category:$subcategory',
      'set_subcategory_recurring',
      {'year': _year, 'category': category, 'subcategory': subcategory, 'recurring': recurring},
    );
    final setup = Map<String, dynamic>.from(_setup!);
    final flags = Map<String, dynamic>.from(
      (setup['recurring_flags'] as Map?) ?? {'income_sources': [], 'free_money_categories': [], 'subcategories': []},
    );
    final items = List<Map<String, dynamic>>.from(
      ((flags['subcategories'] as List?) ?? []).cast<Map<String, dynamic>>(),
    );
    items.removeWhere((p) => p['category'] == category && p['subcategory'] == subcategory);
    if (recurring) items.add({'category': category, 'subcategory': subcategory});
    flags['subcategories'] = items;
    setup['recurring_flags'] = flags;
    await DbService.setCache(DataRefreshService.setupKey(_year), setup);
    await _loadFromCache();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Manage Categories'),
        actions: [
          IconButton(
            icon: _refreshing
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.sync),
            onPressed: _refreshing ? null : _refreshFromServer,
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabs: [
            for (final (_, _, label, _) in _listKinds) Tab(text: label),
            const Tab(text: 'Subcategories'),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _setup == null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.cloud_off, size: 48),
                        const SizedBox(height: 12),
                        const Text('No cached categories yet.', textAlign: TextAlign.center),
                        const SizedBox(height: 12),
                        FilledButton(onPressed: _refreshFromServer, child: const Text('Sync now')),
                      ],
                    ),
                  ),
                )
              : TabBarView(
                  controller: _tabController,
                  children: [
                    for (final (kind, jsonKey, _, recurs) in _listKinds) _buildListTab(kind, jsonKey, recurs),
                    _buildSubcategoriesTab(),
                  ],
                ),
    );
  }

  Widget _buildListTab(String listKind, String jsonKey, bool supportsRecurring) {
    final values = (_setup![jsonKey] as List).cast<String>();

    return Scaffold(
      body: ListView.separated(
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: values.length,
        separatorBuilder: (_, _) => const Divider(height: 1, indent: 16, endIndent: 16),
        itemBuilder: (context, i) {
          final value = values[i];
          final isRecurring = listKind == 'income-sources'
              ? _isIncomeSourceRecurring(value)
              : listKind == 'free-money-categories'
                  ? _isFreeMoneyCategoryRecurring(value)
                  : false;
          return ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            title: Text(value),
            subtitle: supportsRecurring
                ? Text(
                    isRecurring ? 'Recurring - carries forward each month' : 'One-off - starts blank each month',
                    style: Theme.of(context).textTheme.bodySmall,
                  )
                : null,
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (supportsRecurring)
                  Switch(
                    value: isRecurring,
                    onChanged: (v) => _setListValueRecurring(listKind, value, v),
                  ),
                IconButton(
                  icon: const Icon(Icons.edit, size: 20),
                  onPressed: () async {
                    final newValue = await _promptText('Rename "$value"', initial: value);
                    if (newValue.isEmpty || newValue == value) return;
                    await _renameListValue(listKind, jsonKey, value, newValue);
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline, size: 20),
                  onPressed: () => _deleteListValue(listKind, jsonKey, value),
                ),
              ],
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          final value = await _promptText('New value');
          if (value.isEmpty) return;
          await _addListValue(listKind, jsonKey, value);
        },
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _buildSubcategoriesTab() {
    final pairs = (_setup!['subcategories'] as List).cast<Map<String, dynamic>>();
    final byCategory = <String, List<String>>{};
    for (final p in pairs) {
      byCategory.putIfAbsent(p['category'] as String, () => []).add(p['subcategory'] as String);
    }
    final categories = (_setup!['expense_categories'] as List).cast<String>();

    return Scaffold(
      body: ListView(
        children: [
          for (final category in categories) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Text(category, style: Theme.of(context).textTheme.titleSmall),
            ),
            for (final sub in byCategory[category] ?? [])
              ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
                title: Text(sub),
                subtitle: Text(
                  _isSubcategoryRecurring(category, sub)
                      ? 'Recurring - carries forward each month'
                      : 'One-off - starts blank each month',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Switch(
                      value: _isSubcategoryRecurring(category, sub),
                      onChanged: (v) => _setSubcategoryRecurring(category, sub, v),
                    ),
                    IconButton(
                      icon: const Icon(Icons.edit, size: 20),
                      onPressed: () async {
                        final newValue = await _promptText('Rename "$sub"', initial: sub);
                        if (newValue.isEmpty || newValue == sub) return;
                        await _renameSubcategory(category, sub, newValue);
                      },
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline, size: 20),
                      onPressed: () => _deleteSubcategory(category, sub),
                    ),
                  ],
                ),
              ),
            TextButton.icon(
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Add subcategory'),
              onPressed: () async {
                final value = await _promptText('New subcategory for "$category"');
                if (value.isEmpty) return;
                await _addSubcategory(category, value);
              },
            ),
          ],
        ],
      ),
    );
  }
}
