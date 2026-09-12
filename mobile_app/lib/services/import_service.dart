import '../models/transaction.dart';
import 'api_client.dart';
import 'db_service.dart';

/// Pulls transactions that exist server-side (e.g. entered directly in
/// Excel, or synced from another device) into the local cache, so the app
/// shows real history rather than only what was added on this device.
class ImportService {
  final ApiClient api;
  ImportService(this.api);

  Future<int> importMonth(int year, int month) async {
    final remote = await api.getTransactions(year, month);
    var imported = 0;
    for (final raw in remote.cast<Map<String, dynamic>>()) {
      final tx = LocalTransaction(
        clientTransactionId: raw['id'] as String,
        year: year,
        month: month,
        date: DateTime.parse(raw['date'] as String),
        type: raw['type'] as String,
        category: raw['category'] as String,
        subcategory: raw['subcategory'] as String,
        item: raw['item'] as String,
        amount: (raw['amount'] as num).toDouble(),
        classification: raw['classification'] as String?,
        notes: raw['notes'] as String?,
        synced: true,
      );
      await DbService.insertOrIgnore(tx);
      imported++;
    }
    return imported;
  }
}
