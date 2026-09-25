import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../config/app_config.dart';
import '../models/transaction.dart';
import '../services/data_refresh_service.dart';
import '../services/db_service.dart';
import '../utils/type_style.dart';

const _types = ['Expense', 'Free Money', 'Investment'];

class AddTransactionScreen extends StatefulWidget {
  final AppConfig config;
  // Prefills every field from a previous transaction (only the date resets
  // to today) - the "Duplicate" action on Transactions, for things typed in
  // from scratch far too often (e.g. "5 DT gas" every few days).
  final LocalTransaction? template;
  const AddTransactionScreen({super.key, required this.config, this.template});

  @override
  State<AddTransactionScreen> createState() => _AddTransactionScreenState();
}

class _AddTransactionScreenState extends State<AddTransactionScreen> {
  late final _itemController = TextEditingController(text: widget.template?.item ?? '');
  late final _amountController =
      TextEditingController(text: widget.template?.amount.toStringAsFixed(2) ?? '');
  late final _subcategoryTextController = TextEditingController(
    text: (widget.template != null && widget.template!.type != 'Expense')
        ? widget.template!.subcategory
        : '',
  );

  DateTime _date = DateTime.now();
  late String _type = widget.template?.type ?? 'Expense';
  late String? _category = widget.template?.category;
  late String? _subcategory = widget.template?.subcategory;

  List<String> _expenseCategories = [];
  List<String> _freeMoneyCategories = [];
  List<String> _investmentAreas = [];
  List<Map<String, String>> _subcategoryPairs = [];

  bool _loadingSetup = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadSetup();
  }

  // Cache-only: this screen must never call the API itself - the app talks
  // to the network only via Sync Now / the hourly timer. If nothing has
  // been synced yet, the lists are simply empty and the user is told to
  // sync first, rather than the screen silently blocking on a network call.
  Future<void> _loadSetup() async {
    final cached = await DbService.getCache(DataRefreshService.setupKey(_date.year));
    if (cached == null) {
      setState(() {
        _error = 'No cached categories yet - sync at least once first.';
        _loadingSetup = false;
      });
      return;
    }
    final setup = cached.$1 as Map<String, dynamic>;
    setState(() {
      _expenseCategories = (setup['expense_categories'] as List).cast<String>();
      _freeMoneyCategories = (setup['free_money_categories'] as List).cast<String>();
      _investmentAreas = (setup['investment_areas'] as List).cast<String>();
      _subcategoryPairs = (setup['subcategories'] as List)
          .cast<Map<String, dynamic>>()
          .map((p) => {'category': p['category'] as String, 'subcategory': p['subcategory'] as String})
          .toList();
      _loadingSetup = false;
    });
  }

  List<String> get _categoryOptions => switch (_type) {
        'Expense' => _expenseCategories,
        'Free Money' => _freeMoneyCategories,
        'Investment' => _investmentAreas,
        _ => [],
      };

  List<String> get _subcategoryOptions {
    if (_type != 'Expense' || _category == null) return [];
    return _subcategoryPairs
        .where((p) => p['category'] == _category)
        .map((p) => p['subcategory']!)
        .toList();
  }

  // Free-text entry for non-Expense types (per the API's own validation
  // rules), OR for an Expense category that has no subcategories defined
  // yet (e.g. "Other") - otherwise the user would hit a dead end.
  bool get _subcategoryIsFreeText => _type != 'Expense' || _subcategoryOptions.isEmpty;

  Future<void> _save() async {
    final amount = double.tryParse(_amountController.text);
    final subcategory =
        _subcategoryIsFreeText ? _subcategoryTextController.text.trim() : _subcategory;

    if (_category == null ||
        subcategory == null ||
        subcategory.isEmpty ||
        _itemController.text.trim().isEmpty) {
      setState(() => _error = 'Category, subcategory and item are required.');
      return;
    }
    final amountValue = amount;
    if (amountValue == null || amountValue <= 0) {
      setState(() => _error = 'Amount must be a positive number.');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      // A typed-in subcategory for an Expense type must exist in SETUP
      // before a transaction using it can ever sync. Rather than call the
      // API right now (this screen never talks to the network directly),
      // queue it as a pending op for the next sync, and add it to the
      // cached setup immediately so it shows up in dropdowns right away.
      final isNewExpenseSubcategory =
          _type == 'Expense' && !_subcategoryOptions.contains(subcategory);
      if (isNewExpenseSubcategory) {
        await DbService.addPendingOp(
          'add_subcategory:${_category!}:$subcategory',
          'add_subcategory',
          {'year': _date.year, 'category': _category!, 'subcategory': subcategory},
        );

        final cached = await DbService.getCache(DataRefreshService.setupKey(_date.year));
        if (cached != null) {
          final setup = Map<String, dynamic>.from(cached.$1 as Map);
          final subs = List<Map<String, dynamic>>.from(setup['subcategories'] as List);
          subs.add({'category': _category!, 'subcategory': subcategory});
          setup['subcategories'] = subs;
          await DbService.setCache(DataRefreshService.setupKey(_date.year), setup);
        }
      }

      final tx = LocalTransaction(
        clientTransactionId: const Uuid().v4(),
        year: _date.year,
        month: _date.month,
        date: _date,
        type: _type,
        category: _category!,
        subcategory: subcategory,
        item: _itemController.text.trim(),
        amount: amountValue,
      );

      await DbService.insert(tx);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      setState(() {
        _error = 'Could not save: $e';
        _saving = false;
      });
    }
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked != null) setState(() => _date = picked);
  }

  @override
  Widget build(BuildContext context) {
    if (_loadingSetup) {
      return Scaffold(
        appBar: AppBar(title: const Text('Add Transaction')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_expenseCategories.isEmpty && _freeMoneyCategories.isEmpty && _investmentAreas.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('Add Transaction')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.cloud_off, size: 48),
                const SizedBox(height: 12),
                Text(
                  _error ?? 'No cached categories yet.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 4),
                const Text(
                  'Go to Dashboard and pull down to sync, or tap Sync Now.',
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: Text(widget.template != null ? 'Duplicate Transaction' : 'Add Transaction')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_error != null)
              Card(
                color: Theme.of(context).colorScheme.errorContainer,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(_error!,
                      style: TextStyle(color: Theme.of(context).colorScheme.onErrorContainer)),
                ),
              ),
            const SizedBox(height: 12),

            // Type selector as colored segmented chips.
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
                    _category = null;
                    _subcategory = null;
                  }),
                );
              }).toList(),
            ),
            const SizedBox(height: 16),

            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.calendar_today),
                      title: const Text('Date'),
                      subtitle: Text(
                          '${_date.year}-${_date.month.toString().padLeft(2, '0')}-${_date.day.toString().padLeft(2, '0')}'),
                      onTap: _pickDate,
                    ),
                    const Divider(),
                    DropdownButtonFormField<String>(
                      initialValue: _category,
                      decoration: const InputDecoration(labelText: 'Category'),
                      items: _categoryOptions
                          .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                          .toList(),
                      onChanged: (v) => setState(() {
                        _category = v;
                        _subcategory = null;
                      }),
                    ),
                    const SizedBox(height: 12),
                    if (_subcategoryIsFreeText)
                      TextField(
                        controller: _subcategoryTextController,
                        decoration: InputDecoration(
                          labelText: 'Subcategory',
                          helperText: _type == 'Expense' && _category != null
                              ? 'No subcategories set up yet for "$_category" - this will add one.'
                              : null,
                        ),
                      )
                    else
                      DropdownButtonFormField<String>(
                        initialValue: _subcategory,
                        decoration: const InputDecoration(labelText: 'Subcategory'),
                        items: _subcategoryOptions
                            .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                            .toList(),
                        onChanged: (v) => setState(() => _subcategory = v),
                      ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _itemController,
                      decoration: const InputDecoration(labelText: 'Item / Description'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _amountController,
                      decoration: const InputDecoration(labelText: 'Amount', suffixText: 'DT'),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _saving ? null : _save,
              icon: _saving
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.check),
              label: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }
}
