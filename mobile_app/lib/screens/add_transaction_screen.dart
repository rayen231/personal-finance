import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../config/app_config.dart';
import '../models/transaction.dart';
import '../services/api_client.dart';
import '../services/db_service.dart';

const _types = ['Expense', 'Free Money', 'Investment'];

class AddTransactionScreen extends StatefulWidget {
  final AppConfig config;
  const AddTransactionScreen({super.key, required this.config});

  @override
  State<AddTransactionScreen> createState() => _AddTransactionScreenState();
}

class _AddTransactionScreenState extends State<AddTransactionScreen> {
  final _itemController = TextEditingController();
  final _amountController = TextEditingController();
  final _subcategoryTextController = TextEditingController();

  DateTime _date = DateTime.now();
  String _type = 'Expense';
  String? _category;
  String? _subcategory;

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

  Future<void> _loadSetup() async {
    try {
      final api = ApiClient(widget.config);
      final setup = await api.getSetup(_date.year);
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
    } catch (e) {
      setState(() {
        _error = 'Could not load categories: $e';
        _loadingSetup = false;
      });
    }
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

  bool get _subcategoryIsFreeText => _type != 'Expense';

  Future<void> _save() async {
    final amount = double.tryParse(_amountController.text);
    final subcategory = _subcategoryIsFreeText ? _subcategoryTextController.text.trim() : _subcategory;

    if (_category == null || subcategory == null || subcategory.isEmpty || _itemController.text.trim().isEmpty) {
      setState(() => _error = 'Category, subcategory and item are required.');
      return;
    }
    if (amount == null || amount <= 0) {
      setState(() => _error = 'Amount must be a positive number.');
      return;
    }

    setState(() => _saving = true);

    final tx = LocalTransaction(
      clientTransactionId: const Uuid().v4(),
      year: _date.year,
      month: _date.month,
      date: _date,
      type: _type,
      category: _category!,
      subcategory: subcategory,
      item: _itemController.text.trim(),
      amount: amount,
    );

    await DbService.insert(tx);
    if (!mounted) return;
    Navigator.of(context).pop(true);
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

    return Scaffold(
      appBar: AppBar(title: const Text('Add Transaction')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: ListView(
          children: [
            if (_error != null) ...[
              Text(_error!, style: const TextStyle(color: Colors.red)),
              const SizedBox(height: 12),
            ],
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Date'),
              subtitle: Text('${_date.year}-${_date.month.toString().padLeft(2, '0')}-${_date.day.toString().padLeft(2, '0')}'),
              trailing: const Icon(Icons.calendar_today),
              onTap: _pickDate,
            ),
            DropdownButtonFormField<String>(
              initialValue: _type,
              decoration: const InputDecoration(labelText: 'Type'),
              items: _types.map((t) => DropdownMenuItem(value: t, child: Text(t))).toList(),
              onChanged: (v) => setState(() {
                _type = v!;
                _category = null;
                _subcategory = null;
              }),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _category,
              decoration: const InputDecoration(labelText: 'Category'),
              items: _categoryOptions.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
              onChanged: (v) => setState(() {
                _category = v;
                _subcategory = null;
              }),
            ),
            const SizedBox(height: 12),
            if (_subcategoryIsFreeText)
              TextField(
                controller: _subcategoryTextController,
                decoration: const InputDecoration(labelText: 'Subcategory'),
              )
            else
              DropdownButtonFormField<String>(
                initialValue: _subcategory,
                decoration: const InputDecoration(labelText: 'Subcategory'),
                items: _subcategoryOptions.map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
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
              decoration: const InputDecoration(labelText: 'Amount'),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }
}
