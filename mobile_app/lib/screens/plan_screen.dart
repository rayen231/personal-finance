import 'package:flutter/material.dart';

import '../config/app_config.dart';
import '../services/api_client.dart';
import '../services/data_refresh_service.dart';
import '../services/db_service.dart';
import '../widgets/month_selector.dart';

class PlanScreen extends StatefulWidget {
  final AppConfig config;
  const PlanScreen({super.key, required this.config});

  @override
  State<PlanScreen> createState() => _PlanScreenState();
}

class _PlanScreenState extends State<PlanScreen> {
  late int _year = DateTime.now().year;
  late int _month = DateTime.now().month;

  final _minSavingsController = TextEditingController();
  // category -> list of (subcategory, controller). Purely a local input
  // convenience: the API only stores one planned total per category, so
  // these per-subcategory amounts are kept in local cache and summed into
  // that total on save - they aren't sent individually.
  final Map<String, List<(String, TextEditingController)>> _necessaryDetail = {};
  final Map<String, TextEditingController> _freeMoneyControllers = {};

  double _investmentsPlannedTotal = 0;
  DateTime? _lastUpdated;
  bool _loading = true;
  bool _saving = false;
  String? _error;

  ApiClient get _api => ApiClient(widget.config);

  static String _detailKey(int year, int month) => 'plan_subcat_detail:$year:$month';

  static const _maxCarryForwardLookback = 24;

  @override
  void initState() {
    super.initState();
    _loadFromCache();
  }

  (int, int) _previousMonth(int year, int month) => month == 1 ? (year - 1, 12) : (year, month - 1);

  /// Looks back through previously-saved months' local subcategory detail
  /// (never sent to the server - it's a local-only breakdown of the
  /// server's per-category total) for the nearest value of each recurring
  /// subcategory. Only used the first time a month is opened locally (no
  /// detail cached for it yet) - editing a month later never reaches back
  /// into earlier months.
  Future<Map<String, double>> _carryForwardSubcategoryAmounts(Set<String> recurringKeys) async {
    final result = <String, double>{};
    var y = _year;
    var m = _month;
    for (var i = 0; i < _maxCarryForwardLookback && result.length < recurringKeys.length; i++) {
      (y, m) = _previousMonth(y, m);
      final cached = await DbService.getCache(_detailKey(y, m));
      if (cached == null) continue;
      final detail = (cached.$1 as Map<String, dynamic>);
      detail.forEach((category, subs) {
        (subs as Map<String, dynamic>).forEach((sub, amount) {
          final key = '$category|$sub';
          if (recurringKeys.contains(key) && !result.containsKey(key)) {
            result[key] = (amount as num).toDouble();
          }
        });
      });
    }
    return result;
  }

  Future<void> _loadFromCache() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final planCached = await DbService.getCache(DataRefreshService.planKey(_year, _month));
      final setupCached = await DbService.getCache(DataRefreshService.setupKey(_year));
      final detailCached = await DbService.getCache(_detailKey(_year, _month));

      if (planCached == null || setupCached == null) {
        setState(() {
          _lastUpdated = null;
          _loading = false;
        });
        return;
      }

      final plan = planCached.$1 as Map<String, dynamic>;
      final setup = setupCached.$1 as Map<String, dynamic>;
      final detail = (detailCached?.$1 as Map<String, dynamic>?) ?? {};

      _minSavingsController.text = (plan['minimum_savings'] as num).toStringAsFixed(2);

      final subcategoriesByCategory = <String, List<String>>{};
      for (final pair in (setup['subcategories'] as List).cast<Map<String, dynamic>>()) {
        subcategoriesByCategory
            .putIfAbsent(pair['category'] as String, () => [])
            .add(pair['subcategory'] as String);
      }

      final recurringSubKeys = <String>{
        for (final p in ((setup['recurring_flags'] as Map?)?['subcategories'] as List? ?? []))
          '${p['category']}|${p['subcategory']}',
      };
      final carried = detailCached == null && recurringSubKeys.isNotEmpty
          ? await _carryForwardSubcategoryAmounts(recurringSubKeys)
          : <String, double>{};

      _necessaryDetail.clear();
      final necessary = (plan['necessary_expenses_planned'] as Map).cast<String, dynamic>();
      necessary.forEach((category, total) {
        final subs = subcategoriesByCategory[category] ?? [];
        final categoryDetail = (detail[category] as Map<String, dynamic>?) ?? {};
        if (subs.isEmpty) {
          // No known subcategories for this one (e.g. "Other") - fall back
          // to a single total field, same as before.
          _necessaryDetail[category] = [
            ('(total)', TextEditingController(text: (total as num).toStringAsFixed(2)))
          ];
        } else {
          _necessaryDetail[category] = [
            for (final sub in subs)
              (
                sub,
                TextEditingController(
                  text: ((categoryDetail[sub] as num?)?.toDouble() ?? carried['$category|$sub'] ?? 0)
                      .toStringAsFixed(2),
                )
              )
          ];
        }
      });

      _freeMoneyControllers.clear();
      final freeMoney = (plan['free_money_planned'] as Map).cast<String, dynamic>();
      freeMoney.forEach((category, amount) {
        _freeMoneyControllers[category] =
            TextEditingController(text: (amount as num).toStringAsFixed(2));
      });

      setState(() {
        _investmentsPlannedTotal = (plan['investments_planned_total'] as num).toDouble();
        _lastUpdated = planCached.$2;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  Future<void> _refreshFromServer() async {
    setState(() => _saving = true);
    try {
      final setup = await _api.getSetup(_year);
      await DbService.setCache(DataRefreshService.setupKey(_year), setup);
      final plan = await _api.getPlan(_year, _month);
      await DbService.setCache(DataRefreshService.planKey(_year, _month), plan);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Refresh failed: $e')));
      }
    }
    await _loadFromCache();
    if (mounted) setState(() => _saving = false);
  }

  void _onMonthChanged((int, int) ym) {
    setState(() {
      _year = ym.$1;
      _month = ym.$2;
    });
    _loadFromCache();
  }

  double _categoryTotal(String category) =>
      _necessaryDetail[category]!.fold(0.0, (sum, e) => sum + (double.tryParse(e.$2.text) ?? 0));

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      // Persist the per-subcategory breakdown locally (the API has no
      // storage for it - only the category total is sent).
      final detailToCache = <String, Map<String, double>>{};
      for (final entry in _necessaryDetail.entries) {
        if (entry.value.length == 1 && entry.value.first.$1 == '(total)') continue;
        detailToCache[entry.key] = {
          for (final (sub, controller) in entry.value) sub: double.tryParse(controller.text) ?? 0,
        };
      }
      await DbService.setCache(_detailKey(_year, _month), detailToCache);

      final minimumSavings = double.tryParse(_minSavingsController.text);
      final necessaryExpensesPlanned = {
        for (final category in _necessaryDetail.keys) category: _categoryTotal(category),
      };
      final freeMoneyPlanned = _freeMoneyControllers.map(
        (category, c) => MapEntry(category, double.tryParse(c.text) ?? 0),
      );

      // Queued, not sent immediately - only Sync Now / the hourly timer
      // talk to the API. Replaces any earlier not-yet-synced edit to this
      // same month (same op id) rather than piling up redundant ops.
      await DbService.addPendingOp(
        'update_plan:$_year:$_month',
        'update_plan',
        {
          'year': _year,
          'month': _month,
          'minimum_savings': minimumSavings,
          'necessary_expenses_planned': necessaryExpensesPlanned,
          'free_money_planned': freeMoneyPlanned,
        },
      );

      // Update the cached copy optimistically so the change is reflected
      // immediately without waiting for a sync.
      final cached = await DbService.getCache(DataRefreshService.planKey(_year, _month));
      if (cached != null) {
        final plan = Map<String, dynamic>.from(cached.$1 as Map);
        if (minimumSavings != null) plan['minimum_savings'] = minimumSavings;
        plan['necessary_expenses_planned'] = necessaryExpensesPlanned;
        plan['free_money_planned'] = freeMoneyPlanned;
        await DbService.setCache(DataRefreshService.planKey(_year, _month), plan);
      }

      await _loadFromCache();
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Plan saved locally - will sync soon.')));
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
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: MonthSelector(year: _year, month: _month, onChanged: _onMonthChanged),
          ),
          Text(
            _lastUpdated == null ? 'Never synced' : 'Last synced: ${_lastUpdated!.toLocal()}'.split('.').first,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 4),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? Center(child: Text('Error: $_error'))
                    : _lastUpdated == null
                        ? RefreshIndicator(
                            onRefresh: _refreshFromServer,
                            child: ListView(
                              children: const [
                                SizedBox(height: 120),
                                Center(child: Text('No cached plan data. Pull down to fetch.')),
                              ],
                            ),
                          )
                        : RefreshIndicator(
                            onRefresh: _refreshFromServer,
                            child: ListView(
                              padding: const EdgeInsets.all(16),
                              children: [
                                Card(
                                  child: Padding(
                                    padding: const EdgeInsets.all(16),
                                    child: TextField(
                                      controller: _minSavingsController,
                                      decoration:
                                          const InputDecoration(labelText: 'Minimum Savings (DT)'),
                                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 16),
                                Text('Necessary Expenses - Planned',
                                    style: Theme.of(context).textTheme.titleMedium),
                                const SizedBox(height: 8),
                                for (final category in _necessaryDetail.keys) _buildCategoryCard(category),
                                const SizedBox(height: 16),
                                Text('Free Money - Planned Allocation',
                                    style: Theme.of(context).textTheme.titleMedium),
                                const SizedBox(height: 8),
                                Card(
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 16),
                                    child: Column(
                                      children: [
                                        const SizedBox(height: 8),
                                        for (final entry in _freeMoneyControllers.entries)
                                          Padding(
                                            padding: const EdgeInsets.only(bottom: 10),
                                            child: TextField(
                                              controller: entry.value,
                                              decoration: InputDecoration(
                                                  labelText: entry.key, suffixText: 'DT'),
                                              keyboardType:
                                                  const TextInputType.numberWithOptions(decimal: true),
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
                                          width: 16,
                                          height: 16,
                                          child: CircularProgressIndicator(strokeWidth: 2))
                                      : const Icon(Icons.check),
                                  label: const Text('Save Plan'),
                                ),
                              ],
                            ),
                          ),
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryCard(String category) {
    final entries = _necessaryDetail[category]!;
    final isSingleTotal = entries.length == 1 && entries.first.$1 == '(total)';

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(category, style: Theme.of(context).textTheme.titleSmall),
                if (!isSingleTotal)
                  Text(
                    '= ${_categoryTotal(category).toStringAsFixed(2)} DT',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            for (final (label, controller) in entries)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: TextField(
                  controller: controller,
                  decoration: InputDecoration(
                    labelText: isSingleTotal ? 'Planned total' : label,
                    suffixText: 'DT',
                  ),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  onChanged: (_) => setState(() {}), // live-update the sum shown above
                ),
              ),
          ],
        ),
      ),
    );
  }
}
