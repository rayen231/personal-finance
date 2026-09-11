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
}
