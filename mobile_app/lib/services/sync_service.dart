import '../models/transaction.dart';
import 'api_client.dart';
import 'db_service.dart';

class SyncOutcome {
  final int processedCount;
  final int failedCount;
  final List<Map<String, dynamic>> failures;
  SyncOutcome(this.processedCount, this.failedCount, this.failures);
}

/// Pushes locally-queued (unsynced) transactions to /sync. Meant to be
/// called both manually ("Sync Now") and roughly hourly while the app is
/// open (see HomeScreen's periodic Timer) - a real background sync while
/// the app is closed would need platform-specific work (e.g. WorkManager on
/// Android) that's out of scope for this first version.
class SyncService {
  final ApiClient api;
  SyncService(this.api);

  Future<SyncOutcome> syncPending() async {
    final pending = await DbService.listUnsynced();
    if (pending.isEmpty) {
      return SyncOutcome(0, 0, []);
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

    return SyncOutcome(processedCount, failures.length, failures);
  }
}
