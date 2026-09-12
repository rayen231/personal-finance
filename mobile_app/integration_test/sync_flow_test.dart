// Live integration check against the real deployed API, run as an actual
// app process (not the flutter_test unit-test sandbox, which fakes out
// HttpClient and every plugin channel) - proves the local DB -> /sync ->
// API path genuinely works end to end. Requires a real API key, passed at
// run time (never hardcoded - this repo is public):
//   flutter test integration_test/sync_flow_test.dart -d windows \
//     --dart-define=TEST_API_KEY=<the real key>
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:integration_test/integration_test.dart';
import 'package:money_handler/config/app_config.dart';
import 'package:money_handler/models/transaction.dart';
import 'package:money_handler/services/api_client.dart';
import 'package:money_handler/services/db_service.dart';
import 'package:money_handler/services/sync_service.dart';

const _testApiKey = String.fromEnvironment('TEST_API_KEY');

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('local transaction survives DB insert, sync, and appears via API',
      (tester) async {
    if (_testApiKey.isEmpty) {
      fail('Pass --dart-define=TEST_API_KEY=<real key> to run this check.');
    }
    final config = AppConfig(baseUrl: AppConfig.defaultBaseUrl, apiKey: _testApiKey);
    final api = ApiClient(config);

    final tx = LocalTransaction(
      clientTransactionId: 'flutter-integration-test-${DateTime.now().millisecondsSinceEpoch}',
      year: 2026,
      month: 9,
      date: DateTime(2026, 9, 11),
      type: 'Expense',
      category: 'Food',
      subcategory: 'Chicken',
      item: 'Flutter integration test',
      amount: 7,
    );

    await DbService.insert(tx);
    final unsyncedBefore = await DbService.listUnsynced();
    expect(unsyncedBefore.any((t) => t.clientTransactionId == tx.clientTransactionId), isTrue);

    final outcome = await SyncService(api).syncPending();
    expect(outcome.failedCount, 0, reason: outcome.failures.toString());

    final unsyncedAfter = await DbService.listUnsynced();
    expect(unsyncedAfter.any((t) => t.clientTransactionId == tx.clientTransactionId), isFalse);

    // Confirm it actually landed server-side, then clean it up.
    final remote = await api.getTransactions(2026, 9);
    final match = remote.cast<Map<String, dynamic>>().firstWhere(
          (t) => t['item'] == 'Flutter integration test',
          orElse: () => {},
        );
    expect(match, isNotEmpty, reason: 'transaction not found via GET after sync');

    final delResp = await http.delete(
      Uri.parse('${config.baseUrl}/api/v1/months/2026/9/transactions/${match['id']}'),
      headers: {'X-API-Key': _testApiKey},
    );
    expect(delResp.statusCode, 204);
  });

  testWidgets(
      'a transaction needing a brand-new subcategory syncs via the pending_ops queue',
      (tester) async {
    if (_testApiKey.isEmpty) {
      fail('Pass --dart-define=TEST_API_KEY=<real key> to run this check.');
    }
    final config = AppConfig(baseUrl: AppConfig.defaultBaseUrl, apiKey: _testApiKey);
    final api = ApiClient(config);
    final newSub = 'IntegrationTestSub-${DateTime.now().millisecondsSinceEpoch}';

    // Simulates exactly what AddTransactionScreen does offline: queue the
    // subcategory instead of calling the API, then insert the transaction
    // locally as unsynced.
    await DbService.addPendingOp(
      'add_subcategory:Food:$newSub',
      'add_subcategory',
      {'year': 2026, 'category': 'Food', 'subcategory': newSub},
    );

    final tx = LocalTransaction(
      clientTransactionId: 'flutter-pending-ops-test-${DateTime.now().millisecondsSinceEpoch}',
      year: 2026,
      month: 9,
      date: DateTime(2026, 9, 12),
      type: 'Expense',
      category: 'Food',
      subcategory: newSub,
      item: 'Pending ops integration test',
      amount: 3,
    );
    await DbService.insert(tx);

    final outcome = await SyncService(api).syncPending();
    expect(outcome.opFailures, isEmpty, reason: outcome.opFailures.toString());
    expect(outcome.failedCount, 0, reason: outcome.failures.toString());

    // The pending op must be gone (processed), and the subcategory must be
    // real on the server now.
    final remainingOps = await DbService.listPendingOps();
    expect(remainingOps.any((o) => o.$2 == 'add_subcategory'), isFalse);

    final setup = await api.getSetup(2026);
    final subs = (setup['subcategories'] as List).cast<Map<String, dynamic>>();
    expect(subs.any((p) => p['category'] == 'Food' && p['subcategory'] == newSub), isTrue);

    // Clean up: delete the transaction, then the subcategory.
    final remote = await api.getTransactions(2026, 9);
    final match = remote.cast<Map<String, dynamic>>().firstWhere(
          (t) => t['item'] == 'Pending ops integration test',
          orElse: () => {},
        );
    expect(match, isNotEmpty);
    await http.delete(
      Uri.parse('${config.baseUrl}/api/v1/months/2026/9/transactions/${match['id']}'),
      headers: {'X-API-Key': _testApiKey},
    );
    await http.delete(
      Uri.parse('${config.baseUrl}/api/v1/setup/2026/subcategories/Food/$newSub'),
      headers: {'X-API-Key': _testApiKey},
    );
  });
}
