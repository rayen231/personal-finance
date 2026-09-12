"""Income, monthly plan, and computed summaries.

Summary figures are computed here from raw data (transactions + planning
cells) rather than read from the workbook's own dashboard formulas: openpyxl
never evaluates formulas, so any cached formula result would already be
stale the moment our own writes save the file. Recomputing independently
also sidesteps two pre-existing bugs in the workbook's own formulas (see
excel_service.read_planned_investments_total and the flagged row-41-vs-43
SUMIFS mismatch) without touching them.
"""

from __future__ import annotations

from app.models.income import IncomeSourceOut, IncomeUpdate
from app.models.plan import PlanOut, PlanUpdate
from app.models.summary import FreeMoneySummary, IncomeSummary, MonthlySummary
from app.services import excel_service
from app.services.recurring_flags import RecurringFlagsStore
from app.services.workbook_repository import WorkbookRepository

# How many months back to look, at most, when carrying a recurring value
# forward - a safety cap, not something normal use should ever approach.
_MAX_CARRY_FORWARD_LOOKBACK = 60


class PlanningService:
    def __init__(self, repo: WorkbookRepository, recurring_flags: RecurringFlagsStore):
        self.repo = repo
        self.recurring_flags = recurring_flags

    def _previous_month(self, year: int, month: int) -> tuple[int, int]:
        return (year - 1, 12) if month == 1 else (year, month - 1)

    def _carry_forward(self, year: int, month: int, raw_extractor) -> float:
        """Walks backward from (year, month) - excluding it - until
        `raw_extractor(ws)` returns something other than None (i.e. a month
        where *this specific field* was actually entered, not just a month
        that happens to be "Active" for some unrelated reason - a different
        field being touched must never make this stop early and report a
        false 0). Stops (returns 0) if it runs off the start of recorded
        history or hits the lookback cap, without ever creating a workbook
        for a year that doesn't exist yet."""
        y, m = year, month
        for _ in range(_MAX_CARRY_FORWARD_LOOKBACK):
            y, m = self._previous_month(y, m)
            if not self.repo.workbook_exists(y):
                return 0.0
            ws = self.repo.open_for_read(y)[excel_service.month_name(m)]
            value = raw_extractor(ws)
            if value is not None:
                return value
        return 0.0

    def list_income(self, year: int, month: int) -> list[IncomeSourceOut]:
        ws = self.repo.open_for_read(year)[excel_service.month_name(month)]
        rows = excel_service.read_income(ws)
        recurring_sources = self.recurring_flags.get(year)["income_sources"]
        results = []
        for r in rows:
            expected = r["expected"]
            raw_expected = excel_service.read_income_expected_raw(ws, r["source"])
            # A blank "expected" on a recurring source means it hasn't been
            # given its own figure this month yet - carry the last actually
            # entered one forward rather than showing 0. Changing a month's
            # own value only ever affects months *after* it, since this only
            # ever looks backward from the current month.
            if raw_expected is None and r["source"] in recurring_sources:
                expected = self._carry_forward(
                    year, month, lambda ws, s=r["source"]: excel_service.read_income_expected_raw(ws, s)
                )
            actual = r["actual"]  # None until the user actually logs it - never carried forward.
            results.append(
                IncomeSourceOut(
                    source=r["source"],
                    expected=expected,
                    actual=actual,
                    difference=None if actual is None else actual - expected,
                )
            )
        return results

    def update_income(self, year: int, month: int, source: str, payload: IncomeUpdate) -> IncomeSourceOut:
        month_name = excel_service.month_name(month)
        with self.repo.open_for_write(year) as handle:
            ws = handle.wb[month_name]
            # Still validates `source` exists even if there's nothing to write.
            excel_service.write_income(ws, source, expected=payload.expected, actual=payload.actual)
            if payload.expected is None and payload.actual is None:
                handle.changed = False
            else:
                excel_service.ensure_month_active(ws)

        updated = next(r for r in self.list_income(year, month) if r.source == source)
        return updated

    def get_plan(self, year: int, month: int) -> PlanOut:
        ws = self.repo.open_for_read(year)[excel_service.month_name(month)]
        free_money_planned = excel_service.read_free_money_planned(ws)
        recurring_categories = self.recurring_flags.get(year)["free_money_categories"]
        for category in free_money_planned:
            raw = excel_service.read_free_money_planned_raw(ws, category)
            if raw is None and category in recurring_categories:
                free_money_planned[category] = self._carry_forward(
                    year, month, lambda ws, c=category: excel_service.read_free_money_planned_raw(ws, c)
                )
        return PlanOut(
            minimum_savings=excel_service.read_minimum_savings(ws),
            necessary_expenses_planned=excel_service.read_necessary_expense_planned(ws),
            free_money_planned=free_money_planned,
            investments_planned_total=excel_service.read_planned_investments_total(ws),
        )

    def update_plan(self, year: int, month: int, payload: PlanUpdate) -> PlanOut:
        month_name = excel_service.month_name(month)
        with self.repo.open_for_write(year) as handle:
            ws = handle.wb[month_name]
            changed = False
            if payload.minimum_savings is not None:
                excel_service.write_minimum_savings(ws, payload.minimum_savings)
                changed = True
            for category, amount in (payload.necessary_expenses_planned or {}).items():
                excel_service.write_necessary_expense_planned(ws, category, amount)
                changed = True
            for category, amount in (payload.free_money_planned or {}).items():
                excel_service.write_free_money_planned(ws, category, amount)
                changed = True
            handle.changed = changed
            if changed:
                excel_service.ensure_month_active(ws)

        return self.get_plan(year, month)

    def get_summary(self, year: int, month: int) -> MonthlySummary:
        month_name = excel_service.month_name(month)
        ws = self.repo.open_for_read(year)[month_name]

        income_rows = excel_service.read_income(ws)
        expected_income = sum(r["expected"] for r in income_rows)
        actual_income = sum((r["actual"] or 0) for r in income_rows)

        transactions = excel_service.list_transactions(ws, month_name)
        necessary_actual = sum(t.amount for t in transactions if t.type == "Expense")
        free_money_actual = sum(t.amount for t in transactions if t.type == "Free Money")
        investments_actual = sum(t.amount for t in transactions if t.type == "Investment")

        necessary_planned = sum(excel_service.read_necessary_expense_planned(ws).values())
        free_money_planned = sum(excel_service.read_free_money_planned(ws).values())
        investments_planned = excel_service.read_planned_investments_total(ws)
        minimum_savings = excel_service.read_minimum_savings(ws)

        extra_savings = max(
            0.0,
            actual_income - necessary_actual - investments_actual - free_money_actual - minimum_savings,
        )
        total_savings = minimum_savings + extra_savings

        return MonthlySummary(
            year=year,
            month=month,
            income=IncomeSummary(expected=expected_income, actual=actual_income),
            necessary_expenses_planned=necessary_planned,
            necessary_expenses_actual=necessary_actual,
            free_money=FreeMoneySummary(
                planned=free_money_planned,
                spent=free_money_actual,
                remaining=free_money_planned - free_money_actual,
            ),
            investments_planned=investments_planned,
            investments_actual=investments_actual,
            minimum_savings=minimum_savings,
            extra_savings=extra_savings,
            total_savings=total_savings,
        )
