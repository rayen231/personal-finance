import 'package:flutter/material.dart';

import '../config/app_config.dart';
import '../services/api_client.dart';

class PlanScreen extends StatefulWidget {
  final AppConfig config;
  const PlanScreen({super.key, required this.config});

  @override
  State<PlanScreen> createState() => _PlanScreenState();
}

class _PlanScreenState extends State<PlanScreen> {
  final _now = DateTime.now();
  final _minSavingsController = TextEditingController();
  final Map<String, TextEditingController> _necessaryControllers = {};
  final Map<String, TextEditingController> _freeMoneyControllers = {};

  double _investmentsPlannedTotal = 0;
  bool _loading = true;
  bool _saving = false;
  String? _error;

  ApiClient get _api => ApiClient(widget.config);

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
      final plan = await _api.getPlan(_now.year, _now.month);
      _minSavingsController.text = (plan['minimum_savings'] as num).toStringAsFixed(2);

      final necessary = (plan['necessary_expenses_planned'] as Map).cast<String, dynamic>();
      necessary.forEach((category, amount) {
        _necessaryControllers[category] =
            TextEditingController(text: (amount as num).toStringAsFixed(2));
      });

      final freeMoney = (plan['free_money_planned'] as Map).cast<String, dynamic>();
      freeMoney.forEach((category, amount) {
        _freeMoneyControllers[category] =
            TextEditingController(text: (amount as num).toStringAsFixed(2));
      });

      setState(() {
        _investmentsPlannedTotal = (plan['investments_planned_total'] as num).toDouble();
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await _api.updatePlan(
        _now.year,
        _now.month,
        minimumSavings: double.tryParse(_minSavingsController.text),
        necessaryExpensesPlanned: _necessaryControllers.map(
          (category, c) => MapEntry(category, double.tryParse(c.text) ?? 0),
        ),
        freeMoneyPlanned: _freeMoneyControllers.map(
          (category, c) => MapEntry(category, double.tryParse(c.text) ?? 0),
        ),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Plan saved.')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not save: $e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Monthly Plan')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text('Error: $_error'))
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: TextField(
                          controller: _minSavingsController,
                          decoration: const InputDecoration(labelText: 'Minimum Savings (DT)'),
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text('Necessary Expenses - Planned', style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 8),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Column(
                          children: [
                            for (final entry in _necessaryControllers.entries)
                              Padding(
                                padding: const EdgeInsets.symmetric(vertical: 4),
                                child: TextField(
                                  controller: entry.value,
                                  decoration: InputDecoration(labelText: entry.key, suffixText: 'DT'),
                                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text('Free Money - Planned Allocation', style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 8),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Column(
                          children: [
                            for (final entry in _freeMoneyControllers.entries)
                              Padding(
                                padding: const EdgeInsets.symmetric(vertical: 4),
                                child: TextField(
                                  controller: entry.value,
                                  decoration: InputDecoration(labelText: entry.key, suffixText: 'DT'),
                                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Card(
                      child: ListTile(
                        leading: const Icon(Icons.trending_up),
                        title: const Text('Investments Planned (read-only)'),
                        subtitle: const Text(
                          'Fill this in directly in the Excel workbook - the API only reads it.',
                        ),
                        trailing: Text('${_investmentsPlannedTotal.toStringAsFixed(2)} DT'),
                      ),
                    ),
                    const SizedBox(height: 24),
                    FilledButton.icon(
                      onPressed: _saving ? null : _save,
                      icon: _saving
                          ? const SizedBox(
                              width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.check),
                      label: const Text('Save Plan'),
                    ),
                  ],
                ),
    );
  }
}
