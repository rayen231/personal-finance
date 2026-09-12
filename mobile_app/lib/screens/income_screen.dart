import 'package:flutter/material.dart';

import '../config/app_config.dart';
import '../services/api_client.dart';

class IncomeScreen extends StatefulWidget {
  final AppConfig config;
  const IncomeScreen({super.key, required this.config});

  @override
  State<IncomeScreen> createState() => _IncomeScreenState();
}

class _IncomeScreenState extends State<IncomeScreen> {
  final _now = DateTime.now();
  List<Map<String, dynamic>> _sources = [];
  bool _loading = true;
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
      final data = await _api.getIncome(_now.year, _now.month);
      setState(() {
        _sources = data.cast<Map<String, dynamic>>();
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  Future<void> _editSource(Map<String, dynamic> source) async {
    final expectedController =
        TextEditingController(text: (source['expected'] as num).toStringAsFixed(2));
    final actualController =
        TextEditingController(text: (source['actual'] as num).toStringAsFixed(2));

    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(source['source'] as String),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: expectedController,
              decoration: const InputDecoration(labelText: 'Expected (DT)'),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: actualController,
              decoration: const InputDecoration(labelText: 'Actual (DT)'),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Save')),
        ],
      ),
    );

    if (saved != true) return;

    final expected = double.tryParse(expectedController.text);
    final actual = double.tryParse(actualController.text);
    try {
      await _api.updateIncome(
        _now.year,
        _now.month,
        source['source'] as String,
        expected: expected,
        actual: actual,
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not save: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Income')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text('Error: $_error'))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      for (final s in _sources)
                        Card(
                          child: ListTile(
                            title: Text(s['source'] as String),
                            subtitle: Text(
                              'Expected: ${(s['expected'] as num).toStringAsFixed(2)} DT',
                            ),
                            trailing: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
                                  '${(s['actual'] as num).toStringAsFixed(2)} DT',
                                  style: const TextStyle(fontWeight: FontWeight.bold),
                                ),
                                Text(
                                  '${(s['difference'] as num) >= 0 ? '+' : ''}${(s['difference'] as num).toStringAsFixed(2)}',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: (s['difference'] as num) >= 0
                                        ? Colors.green
                                        : Colors.red,
                                  ),
                                ),
                              ],
                            ),
                            onTap: () => _editSource(s),
                          ),
                        ),
                    ],
                  ),
                ),
    );
  }
}
