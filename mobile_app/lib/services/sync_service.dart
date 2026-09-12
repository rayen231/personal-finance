import '../models/transaction.dart';
import 'api_client.dart';
import 'db_service.dart';

class SyncOutcome {
  final int processedCount;
  final int failedCount;
  final List<Map<String, dynamic>> failures;
  final List<String> opFailures;
  SyncOutcome(this.processedCount, this.failedCount, this.failures, this.opFailures);
}

/// Pushes everything queued locally to the API. Meant to be called both
/// manually ("Sync Now") and roughly hourly while the app is open (see
/// HomeScreen's periodic Timer) - a real background sync while the app is
/// closed would need platform-specific work (e.g. WorkManager on Android)
/// that's out of scope for this first version.
///
/// Two queues are pushed, in order:
/// 1. pending_ops - everything that isn't a transaction create (new
///    subcategories, income/plan edits, category management, edits/deletes
///    of already-synced transactions). Processed first because a queued
///    transaction create might depend on a queued subcategory existing.
/// 2. Unsynced transactions - via the batch /sync endpoint.
class SyncService {
  final ApiClient api;
  SyncService(this.api);

  Future<List<String>> processPendingOps() async {
    final failures = <String>[];
    final ops = await DbService.listPendingOps();
    for (final (id, type, payload) in ops) {
      try {
        await _dispatch(type, payload);
        await DbService.removePendingOp(id);
      } catch (e) {
        failures.add('$type failed: $e');
      }
    }
    return failures;
  }

  Future<void> _dispatch(String type, Map<String, dynamic> p) async {
    switch (type) {
      case 'add_subcategory':
        await api.addSubcategory(p['year'] as int, p['category'] as String, p['subcategory'] as String);
      case 'update_income':
        await api.updateIncome(
          p['year'] as int,
          p['month'] as int,
          p['source'] as String,
          expected: (p['expected'] as num?)?.toDouble(),
          actual: (p['actual'] as num?)?.toDouble(),
        );
      case 'update_plan':
        await api.updatePlan(
          p['year'] as int,
          p['month'] as int,
          minimumSavings: (p['minimum_savings'] as num?)?.toDouble(),
          necessaryExpensesPlanned: (p['necessary_expenses_planned'] as Map?)
              ?.map((k, v) => MapEntry(k as String, (v as num).toDouble())),
          freeMoneyPlanned: (p['free_money_planned'] as Map?)
              ?.map((k, v) => MapEntry(k as String, (v as num).toDouble())),
        );
      case 'add_list_value':
        await api.addListValue(p['year'] as int, p['list_kind'] as String, p['value'] as String);
      case 'rename_list_value':
        await api.renameListValue(
          p['year'] as int,
          p['list_kind'] as String,
          p['old_value'] as String,
          p['new_value'] as String,
        );
      case 'delete_list_value':
        await api.deleteListValue(p['year'] as int, p['list_kind'] as String, p['value'] as String);
      case 'rename_subcategory':
        await api.renameSubcategory(
          p['year'] as int,
          p['category'] as String,
          p['old_subcategory'] as String,
          p['new_subcategory'] as String,
        );
      case 'delete_subcategory':
        await api.deleteSubcategory(p['year'] as int, p['category'] as String, p['subcategory'] as String);
      case 'update_transaction':
        await api.updateTransaction(
          p['year'] as int,
          p['month'] as int,
          p['id'] as String,
          Map<String, dynamic>.from(p['fields'] as Map),
        );
      case 'delete_transaction':
        await api.deleteTransaction(p['year'] as int, p['month'] as int, p['id'] as String);
      case 'set_income_source_recurring':
        await api.setIncomeSourceRecurring(p['year'] as int, p['source'] as String, p['recurring'] as bool);
      case 'set_free_money_category_recurring':
        await api.setFreeMoneyCategoryRecurring(
            p['year'] as int, p['category'] as String, p['recurring'] as bool);
      case 'set_subcategory_recurring':
        await api.setSubcategoryRecurring(
          p['year'] as int,
          p['category'] as String,
          p['subcategory'] as String,
          p['recurring'] as bool,
        );
      default:
        throw StateError('Unknown pending op type: $type');
    }
  }

  Future<SyncOutcome> syncPending() async {
    final opFailures = await processPendingOps();

    final pending = await DbService.listUnsynced();
    if (pending.isEmpty) {
      return SyncOutcome(0, 0, [], opFailures);
    }

    // /sync requires every operation in a batch to target the same year.
    final byYear = <int, List<LocalTransaction>>{};
    for (final tx in pending) {
      byYear.putIfAbsent(tx.year, () => []).add(tx);
    }

    var processedCount = 0;
    final failures = <Map<String, dynamic>>[];

    for (final entry in byYear.entries) {
      final result = await api.sync(entry.value);
      await DbService.markSynced(result.processed);
      processedCount += result.processed.length;
      failures.addAll(result.failed);
    }

    return SyncOutcome(processedCount, failures.length, failures, opFailures);
  }
}
