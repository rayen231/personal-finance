import 'package:flutter/material.dart';

import '../config/app_config.dart';
import '../services/api_client.dart';

const _listKinds = [
  ('categories', 'Expense Categories'),
  ('free-money-categories', 'Free Money Categories'),
  ('investment-areas', 'Investment Areas'),
  ('income-sources', 'Income Sources'),
];

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
  String? _error;

  ApiClient get _api => ApiClient(widget.config);
  int get _year => DateTime.now().year;

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
      final setup = await _api.getSetup(_year);
      setState(() {
        _setup = setup;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
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

  Future<void> _runAction(Future<void> Function() action) async {
    try {
      await action();
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Manage Categories'),
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabs: [
            for (final (_, label) in _listKinds) Tab(text: label),
            const Tab(text: 'Subcategories'),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text('Error: $_error'))
              : TabBarView(
                  controller: _tabController,
                  children: [
                    for (final (kind, _) in _listKinds) _buildListTab(kind),
                    _buildSubcategoriesTab(),
                  ],
                ),
    );
  }

  Widget _buildListTab(String listKind) {
    final key = switch (listKind) {
      'categories' => 'expense_categories',
      'free-money-categories' => 'free_money_categories',
      'investment-areas' => 'investment_areas',
      'income-sources' => 'income_sources',
      _ => throw ArgumentError(listKind),
    };
    final values = (_setup![key] as List).cast<String>();

    return Scaffold(
      body: ListView(
        children: [
          for (final value in values)
            ListTile(
              title: Text(value),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.edit, size: 20),
                    onPressed: () async {
                      final newValue = await _promptText('Rename "$value"', initial: value);
                      if (newValue.isEmpty || newValue == value) return;
                      await _runAction(() => _api.renameListValue(_year, listKind, value, newValue));
                    },
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline, size: 20),
                    onPressed: () => _runAction(() => _api.deleteListValue(_year, listKind, value)),
                  ),
                ],
              ),
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          final value = await _promptText('New value');
          if (value.isEmpty) return;
          await _runAction(() => _api.addListValue(_year, listKind, value));
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
                dense: true,
                title: Text(sub),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.edit, size: 20),
                      onPressed: () async {
                        final newValue = await _promptText('Rename "$sub"', initial: sub);
                        if (newValue.isEmpty || newValue == sub) return;
                        await _runAction(
                            () => _api.renameSubcategory(_year, category, sub, newValue));
                      },
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline, size: 20),
                      onPressed: () =>
                          _runAction(() => _api.deleteSubcategory(_year, category, sub)),
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
                await _runAction(() => _api.addSubcategory(_year, category, value));
              },
            ),
          ],
        ],
      ),
    );
  }
}
