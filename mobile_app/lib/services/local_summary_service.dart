import 'data_refresh_service.dart';
import 'db_service.dart';

/// Recomputes the same aggregates as the backend's PlanningService.get_summary,
/// but purely from local data (cached income/plan + local transactions,
/// synced or not). The server-computed `summary` cache only reflects
/// transactions that have already been pushed and re-fetched, so a
/// just-added, not-yet-synced transaction would otherwise be invisible on
/// the Dashboard until the next full sync - this keeps it local-first like
/// everything else in the app.
class LocalSummaryService {
  static Future<Map<String, dynamic>?> compute(int year, int month) async {
    final incomeCached = await DbService.getCache(DataRefreshService.incomeKey(year, month));
    final planCached = await DbService.getCache(DataRefreshService.planKey(year, month));
    if (incomeCached == null || planCached == null) return null;

    final incomeList = (incomeCached.$1 as List).cast<Map<String, dynamic>>();
    final expectedIncome =
        incomeList.fold<double>(0, (sum, r) => sum + (r['expected'] as num).toDouble());
    final actualIncome = incomeList.fold<double>(
      0,
      (sum, r) => sum + ((r['actual'] as num?)?.toDouble() ?? 0),
    );

    final plan = planCached.$1 as Map<String, dynamic>;
    final necessaryPlanned = (plan['necessary_expenses_planned'] as Map)
        .values
        .fold<double>(0, (sum, v) => sum + (v as num).toDouble());
    final freeMoneyPlanned = (plan['free_money_planned'] as Map)
        .values
        .fold<double>(0, (sum, v) => sum + (v as num).toDouble());
    final investmentsPlanned = (plan['investments_planned_total'] as num).toDouble();
    final minimumSavings = (plan['minimum_savings'] as num).toDouble();

    final transactions = await DbService.listForMonth(year, month);
    var necessaryActual = 0.0;
    var freeMoneyActual = 0.0;
    var investmentsActual = 0.0;
    for (final t in transactions) {
      switch (t.type) {
        case 'Expense':
          necessaryActual += t.amount;
        case 'Free Money':
          freeMoneyActual += t.amount;
        case 'Investment':
          investmentsActual += t.amount;
      }
    }

    final extraSavings = (actualIncome - necessaryActual - investmentsActual - freeMoneyActual - minimumSavings)
        .clamp(0.0, double.infinity);
    final totalSavings = minimumSavings + extraSavings;

    return {
      'year': year,
      'month': month,
      'income': {'expected': expectedIncome, 'actual': actualIncome},
      'necessary_expenses_planned': necessaryPlanned,
      'necessary_expenses_actual': necessaryActual,
      'free_money': {
        'planned': freeMoneyPlanned,
        'spent': freeMoneyActual,
        'remaining': freeMoneyPlanned - freeMoneyActual,
      },
      'investments_planned': investmentsPlanned,
      'investments_actual': investmentsActual,
      'minimum_savings': minimumSavings,
      'extra_savings': extraSavings,
      'total_savings': totalSavings,
    };
  }
}
