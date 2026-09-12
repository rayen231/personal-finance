import 'api_client.dart';
import 'db_service.dart';
import 'import_service.dart';

/// The ONLY thing that's allowed to call the API for "read" data (setup,
/// income, plan, summary, transactions) - screens read from DbService's
/// cache instead of hitting the network themselves. Triggered by Sync Now,
/// the hourly timer, or an explicit pull-to-refresh - never by simply
/// opening/navigating to a screen.
class DataRefreshService {
  final ApiClient api;
  DataRefreshService(this.api);

  static String setupKey(int year) => 'setup:$year';
  static String incomeKey(int year, int month) => 'income:$year:$month';
  static String planKey(int year, int month) => 'plan:$year:$month';
  static String summaryKey(int year, int month) => 'summary:$year:$month';

  Future<void> refreshMonth(int year, int month) async {
    final setup = await api.getSetup(year);
    await DbService.setCache(setupKey(year), setup);

    final income = await api.getIncome(year, month);
    await DbService.setCache(incomeKey(year, month), income);

    final plan = await api.getPlan(year, month);
    await DbService.setCache(planKey(year, month), plan);

    final summary = await api.getSummary(year, month);
    await DbService.setCache(summaryKey(year, month), summary);

    await ImportService(api).importMonth(year, month);
  }

  /// Cheaper than refreshMonth() - used by TransactionsScreen's own
  /// pull-to-refresh, which only needs the transaction list, not the whole
  /// setup/income/plan/summary cache.
  Future<void> importTransactionsOnly(int year, int month) => ImportService(api).importMonth(year, month);
}
