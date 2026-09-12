import 'package:flutter/material.dart';

import '../config/app_config.dart';
import '../models/transaction.dart';
import '../services/api_client.dart';
import '../services/db_service.dart';

/// Editing/deleting an already-synced transaction requires connectivity -
/// it goes straight to the API (PUT/DELETE), not through the offline
/// /sync queue (which only supports creates in V1). A not-yet-synced
/// transaction is only ever edited/deleted locally - it doesn't exist on
/// the server yet, so there's nothing to call.
class EditTransactionScreen extends StatefulWidget {
  final AppConfig config;
  final LocalTransaction tx;
  const EditTransactionScreen({super.key, required this.config, required this.tx});

  @override
  State<EditTransactionScreen> createState() => _EditTransactionScreenState();
}

class _EditTransactionScreenState extends State<EditTransactionScreen> {
  late final _itemController = TextEditingController(text: widget.tx.item);
  late final _subcategoryController = TextEditingController(text: widget.tx.subcategory);
  late final _amountController = TextEditingController(text: widget.tx.amount.toString());
  late DateTime _date = widget.tx.date;

  bool _saving = false;
  String? _error;

  ApiClient get _api => ApiClient(widget.config);

  Future<void> _pickDate() async {
    // Kept within the transaction's original month: the row physically
    // lives in that month's sheet server-side, and PUT only updates fields
    // in place - it doesn't relocate the row to a different month's sheet.
    final firstOfMonth = DateTime(widget.tx.year, widget.tx.month, 1);
    final lastOfMonth = DateTime(widget.tx.year, widget.tx.month + 1, 0);
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: firstOfMonth,
      lastDate: lastOfMonth,
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _save() async {
    final amount = double.tryParse(_amountController.text);
    if (amount == null || amount <= 0) {
      setState(() => _error = 'Amount must be a positive number.');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    final updated = LocalTransaction(
      clientTransactionId: widget.tx.clientTransactionId,
      year: _date.year,
      month: _date.month,
      date: _date,
      type: widget.tx.type,
      category: widget.tx.category,
      subcategory: _subcategoryController.text.trim(),
      item: _itemController.text.trim(),
      amount: amount,
      classification: widget.tx.classification,
      notes: widget.tx.notes,
      synced: widget.tx.synced,
    );

    try {
      if (widget.tx.synced) {
        await _api.updateTransaction(widget.tx.year, widget.tx.month, widget.tx.clientTransactionId, {
          'date': _date.toIso8601String().substring(0, 10),
          'subcategory': updated.subcategory,
          'item': updated.item,
          'amount': updated.amount,
        });
      }
      await DbService.update(updated);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      setState(() {
        _error = 'Could not save: $e';
        _saving = false;
      });
    }
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete transaction?'),
        content: Text('${widget.tx.category} / ${widget.tx.subcategory} - ${widget.tx.item}'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _saving = true);
    try {
      if (widget.tx.synced) {
        await _api.deleteTransaction(widget.tx.year, widget.tx.month, widget.tx.clientTransactionId);
      }
      await DbService.delete(widget.tx.clientTransactionId);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      setState(() {
        _error = 'Could not delete: $e';
        _saving = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Edit Transaction'),
        actions: [
          IconButton(icon: const Icon(Icons.delete_outline), onPressed: _saving ? null : _delete),
        ],
      ),
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
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.category),
                      title: Text(widget.tx.type),
                      subtitle: Text(widget.tx.category),
                    ),
                    const Divider(),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.calendar_today),
                      title: const Text('Date'),
                      subtitle: Text(
                          '${_date.year}-${_date.month.toString().padLeft(2, '0')}-${_date.day.toString().padLeft(2, '0')}'),
                      onTap: _pickDate,
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _subcategoryController,
                      decoration: const InputDecoration(labelText: 'Subcategory'),
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
            const SizedBox(height: 8),
            Text(
              widget.tx.synced
                  ? 'This transaction is already synced - changes save immediately.'
                  : 'Not synced yet - changes are saved locally until the next sync.',
              style: Theme.of(context).textTheme.bodySmall,
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
