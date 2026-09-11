"""Reads configuration lists (categories, subcategories, etc.) from SETUP."""

from __future__ import annotations

from dataclasses import dataclass, field

from openpyxl.utils.cell import range_boundaries
from openpyxl.workbook.workbook import Workbook

from app.services.excel_service import LabelNotFoundError, TableFullError, WorkbookError

VALID_TX_TYPES = ["Expense", "Free Money", "Investment"]

# Mirrors the IF() formula in tbl_Recurring's "Monthly Reserve" column, so
# the API can return a real number instead of an unevaluated formula string
# (openpyxl never computes formulas).
_FREQUENCY_DIVISORS = {
    "Monthly": 1,
    "Yearly": 12,
    "Every 6 months": 6,
    "Every 3 months": 3,
}


def _monthly_reserve(frequency: str, expected_amount: float) -> float:
    if not expected_amount:
        return 0.0
    if frequency == "Weekly":
        return expected_amount * 52 / 12
    return expected_amount / _FREQUENCY_DIVISORS.get(frequency, 1)


def _table_single_column(ws, table_name: str) -> list[str]:
    if table_name not in ws.tables:
        raise WorkbookError(f"Table {table_name} not found in SETUP")
    min_col, min_row, max_col, max_row = range_boundaries(ws.tables[table_name].ref)
    values = []
    for row in range(min_row + 1, max_row + 1):
        val = ws.cell(row=row, column=min_col).value
        if val is not None:
            values.append(str(val))
    return values


def _table_two_columns(ws, table_name: str) -> list[tuple[str, str]]:
    if table_name not in ws.tables:
        raise WorkbookError(f"Table {table_name} not found in SETUP")
    min_col, min_row, max_col, max_row = range_boundaries(ws.tables[table_name].ref)
    pairs = []
    for row in range(min_row + 1, max_row + 1):
        a = ws.cell(row=row, column=min_col).value
        b = ws.cell(row=row, column=min_col + 1).value
        if a is not None and b is not None:
            pairs.append((str(a), str(b)))
    return pairs


@dataclass
class SetupConfig:
    income_sources: list[str] = field(default_factory=list)
    expense_categories: list[str] = field(default_factory=list)
    subcategories: list[tuple[str, str]] = field(default_factory=list)  # (category, subcategory)
    free_money_categories: list[str] = field(default_factory=list)
    investment_areas: list[str] = field(default_factory=list)
    classifications: list[str] = field(default_factory=list)

    def subcategories_for(self, category: str) -> list[str]:
        return [sub for cat, sub in self.subcategories if cat == category]

    def is_valid_category_for_type(self, tx_type: str, category: str) -> bool:
        if tx_type == "Expense":
            return category in self.expense_categories
        if tx_type == "Free Money":
            return category in self.free_money_categories
        if tx_type == "Investment":
            return category in self.investment_areas
        return False

    def is_valid_subcategory(self, tx_type: str, category: str, subcategory: str) -> bool:
        if tx_type == "Expense":
            return subcategory in self.subcategories_for(category)
        # Free Money / Investment categories don't have a SETUP subcategory table;
        # subcategory is a free-text label for those types.
        return True


def read_setup_config(wb: Workbook) -> SetupConfig:
    ws = wb["SETUP"]
    return SetupConfig(
        income_sources=_table_single_column(ws, "tbl_IncomeSources"),
        expense_categories=_table_single_column(ws, "tbl_ExpenseCategories"),
        subcategories=_table_two_columns(ws, "tbl_Subcategories"),
        free_money_categories=_table_single_column(ws, "tbl_FreeMoneyCategories"),
        investment_areas=_table_single_column(ws, "tbl_InvestmentAreas"),
        classifications=_table_single_column(ws, "tbl_Classifications"),
    )


def read_recurring_expenses(wb: Workbook) -> list[dict]:
    ws = wb["SETUP"]
    table_name = "tbl_Recurring"
    if table_name not in ws.tables:
        raise WorkbookError(f"Table {table_name} not found in SETUP")
    min_col, min_row, max_col, max_row = range_boundaries(ws.tables[table_name].ref)

    results = []
    for row in range(min_row + 1, max_row + 1):
        expense = ws.cell(row=row, column=min_col).value
        if expense is None:
            continue
        category = ws.cell(row=row, column=min_col + 1).value
        frequency = ws.cell(row=row, column=min_col + 2).value
        expected_amount = ws.cell(row=row, column=min_col + 3).value or 0
        notes = ws.cell(row=row, column=min_col + 5).value
        results.append({
            "expense": expense,
            "category": category,
            "frequency": frequency,
            "expected_amount": expected_amount,
            "monthly_reserve": _monthly_reserve(frequency, expected_amount),
            "notes": notes,
        })
    return results


def add_subcategory(wb: Workbook, category: str, subcategory: str) -> bool:
    """Returns True if a new row was written, False if the pair already
    existed (idempotent no-op) - callers use this to decide whether the
    workbook actually needs to be re-saved."""
    ws = wb["SETUP"]
    table_name = "tbl_Subcategories"
    if table_name not in ws.tables:
        raise WorkbookError(f"Table {table_name} not found in SETUP")

    config = read_setup_config(wb)
    if category not in config.expense_categories:
        raise LabelNotFoundError(f"'{category}' is not a known expense category.")
    if subcategory in config.subcategories_for(category):
        return False  # already exists - adding is idempotent

    min_col, min_row, max_col, max_row = range_boundaries(ws.tables[table_name].ref)
    for row in range(min_row + 1, max_row + 1):
        if ws.cell(row=row, column=min_col).value is None:
            ws.cell(row=row, column=min_col, value=category)
            ws.cell(row=row, column=min_col + 1, value=subcategory)
            return True

    raise TableFullError(
        f"{table_name} is full (no blank row up to row {max_row}). Add rows to the table in Excel first."
    )
