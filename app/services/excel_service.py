"""Low-level reads/writes against the workbook's transaction tables.

Keeps openpyxl details out of the business/service layer so Excel could
eventually be swapped for a database without rewriting finance_service.
"""

from __future__ import annotations

import io
from dataclasses import dataclass
from datetime import date
from typing import Optional

import openpyxl
from openpyxl.utils.cell import range_boundaries
from openpyxl.workbook.workbook import Workbook
from openpyxl.worksheet.worksheet import Worksheet

MONTHS = [
    "JANUARY", "FEBRUARY", "MARCH", "APRIL", "MAY", "JUNE",
    "JULY", "AUGUST", "SEPTEMBER", "OCTOBER", "NOVEMBER", "DECEMBER",
]

TX_COLUMNS = {
    "date": 1,
    "type": 2,
    "category": 3,
    "subcategory": 4,
    "item": 5,
    "classification": 6,
    "amount": 10,
    "notes": 11,
    "transaction_id": 12,
}

MONTH_STATUS_CELL = "B2"


class WorkbookError(Exception):
    pass


class TableFullError(WorkbookError):
    pass


class TransactionNotFoundError(WorkbookError):
    pass


def month_name(month: int) -> str:
    if not 1 <= month <= 12:
        raise WorkbookError(f"Invalid month number: {month}")
    return MONTHS[month - 1]


def load_workbook(content: bytes) -> Workbook:
    return openpyxl.load_workbook(io.BytesIO(content))


def save_workbook(wb: Workbook) -> bytes:
    buf = io.BytesIO()
    wb.save(buf)
    return buf.getvalue()


def _transactions_table_bounds(ws: Worksheet, month: str) -> tuple[int, int, int, int]:
    table_name = f"tbl_{month}_Transactions"
    if table_name not in ws.tables:
        raise WorkbookError(f"Table {table_name} not found in sheet {month}")
    return range_boundaries(ws.tables[table_name].ref)


@dataclass
class TransactionRow:
    row: int
    transaction_id: str
    date: Optional[date]
    type: str
    category: str
    subcategory: str
    item: str
    classification: Optional[str]
    amount: float
    notes: Optional[str]


def read_row(ws: Worksheet, row: int) -> TransactionRow:
    def cell(key: str):
        return ws.cell(row=row, column=TX_COLUMNS[key]).value

    return TransactionRow(
        row=row,
        transaction_id=cell("transaction_id"),
        date=cell("date"),
        type=cell("type"),
        category=cell("category"),
        subcategory=cell("subcategory"),
        item=cell("item"),
        classification=cell("classification"),
        amount=cell("amount") or 0,
        notes=cell("notes"),
    )


def _is_row_blank(ws: Worksheet, row: int) -> bool:
    return ws.cell(row=row, column=TX_COLUMNS["transaction_id"]).value is None


def find_first_blank_row(ws: Worksheet, month: str) -> int:
    min_col, min_row, max_col, max_row = _transactions_table_bounds(ws, month)
    header_row = min_row
    for row in range(header_row + 1, max_row + 1):
        if _is_row_blank(ws, row):
            return row
    raise TableFullError(
        f"Transactions table for {month} is full (no blank row up to {max_row})."
    )


def write_transaction_row(
    ws: Worksheet,
    row: int,
    *,
    transaction_id: str,
    tx_date: date,
    tx_type: str,
    category: str,
    subcategory: str,
    item: str,
    amount: float,
    classification: Optional[str] = None,
    notes: Optional[str] = None,
) -> None:
    ws.cell(row=row, column=TX_COLUMNS["date"], value=tx_date)
    ws.cell(row=row, column=TX_COLUMNS["type"], value=tx_type)
    ws.cell(row=row, column=TX_COLUMNS["category"], value=category)
    ws.cell(row=row, column=TX_COLUMNS["subcategory"], value=subcategory)
    ws.cell(row=row, column=TX_COLUMNS["item"], value=item)
    ws.cell(row=row, column=TX_COLUMNS["classification"], value=classification)
    ws.cell(row=row, column=TX_COLUMNS["amount"], value=amount)
    ws.cell(row=row, column=TX_COLUMNS["notes"], value=notes)
    ws.cell(row=row, column=TX_COLUMNS["transaction_id"], value=transaction_id)


def clear_transaction_row(ws: Worksheet, row: int) -> None:
    for key in TX_COLUMNS:
        ws.cell(row=row, column=TX_COLUMNS[key]).value = None


def find_row_by_transaction_id(ws: Worksheet, month: str, transaction_id: str) -> int:
    min_col, min_row, max_col, max_row = _transactions_table_bounds(ws, month)
    id_col = TX_COLUMNS["transaction_id"]
    for row in range(min_row + 1, max_row + 1):
        if ws.cell(row=row, column=id_col).value == transaction_id:
            return row
    raise TransactionNotFoundError(transaction_id)


def list_transactions(ws: Worksheet, month: str) -> list[TransactionRow]:
    min_col, min_row, max_col, max_row = _transactions_table_bounds(ws, month)
    results = []
    for row in range(min_row + 1, max_row + 1):
        if _is_row_blank(ws, row):
            continue
        results.append(read_row(ws, row))
    return results


def get_transaction(ws: Worksheet, month: str, transaction_id: str) -> TransactionRow:
    row = find_row_by_transaction_id(ws, month, transaction_id)
    return read_row(ws, row)


def get_month_status(ws: Worksheet) -> str:
    return ws[MONTH_STATUS_CELL].value


def set_month_status(ws: Worksheet, status: str) -> None:
    ws[MONTH_STATUS_CELL] = status


def ensure_month_active(ws: Worksheet) -> None:
    if get_month_status(ws) == "Not Started":
        set_month_status(ws, "Active")


class LabelNotFoundError(WorkbookError):
    pass


# --- Fixed-row planning blocks -------------------------------------------
# These are plain formula grids (not Excel Tables), sized to match SETUP's
# list at the time the workbook was built. Labels are matched by text, not
# by fixed row index, so re-ordering the block in Excel doesn't break the
# API - but the row RANGE itself is fixed, so a block that's already at
# capacity raises PlanningBlockFullError rather than overwriting a
# neighboring section.

INCOME_ROWS = range(6, 10)  # A=source, B=expected, C=actual
INCOME_LABEL_COL, INCOME_EXPECTED_COL, INCOME_ACTUAL_COL = 1, 2, 3

NECESSARY_EXPENSE_ROWS = range(14, 21)  # A=category, B=planned
NEC_EXP_LABEL_COL, NEC_EXP_PLANNED_COL = 1, 2

FREE_MONEY_ROWS = range(22, 27)  # F=category, G=planned
FREE_MONEY_LABEL_COL, FREE_MONEY_PLANNED_COL = 6, 7

INVESTMENT_PLAN_ROWS = range(25, 35)  # A=Date, B=Area, C=Subcategory, D=Amount, E=Notes
INVESTMENT_PLAN_AMOUNT_COL = 4

MINIMUM_SAVINGS_CELL = "G6"


def _numeric_or_none(value) -> Optional[float]:
    """Planned-value cells are normally numbers; a couple of them hold a
    stray formula in the source workbook (a pre-existing bug flagged
    separately). Treat unreadable/formula values as "not set" rather than
    guessing at their result, since openpyxl never evaluates formulas."""
    if isinstance(value, (int, float)):
        return float(value)
    return None


def _find_label_row(ws: Worksheet, rows: range, label_col: int, label: str) -> int:
    for row in rows:
        if ws.cell(row=row, column=label_col).value == label:
            return row
    raise LabelNotFoundError(
        f"'{label}' not found in row range {rows.start}-{rows.stop - 1}. "
        "Add it as a labeled row in Excel first."
    )


def read_income(ws: Worksheet) -> list[dict]:
    results = []
    for row in INCOME_ROWS:
        source = ws.cell(row=row, column=INCOME_LABEL_COL).value
        if source is None:
            continue
        results.append({
            "source": source,
            "expected": _numeric_or_none(ws.cell(row=row, column=INCOME_EXPECTED_COL).value) or 0,
            # Not coerced to 0: blank means "not yet received/entered this
            # month" for callers that need to tell the two apart.
            "actual": _numeric_or_none(ws.cell(row=row, column=INCOME_ACTUAL_COL).value),
        })
    return results


def read_income_expected_raw(ws: Worksheet, source: str) -> Optional[float]:
    """Single-source lookup used by recurring-value carry-forward. Returns
    None - not 0 - when the cell is genuinely blank (never entered), so a
    month that was touched for some *other* reason (e.g. only "actual" was
    filled in) doesn't get mistaken for one where "expected" was actually
    set. Also None if this month's sheet doesn't have that source as a row
    at all (e.g. it was added to SETUP after this month's template was laid
    down)."""
    try:
        row = _find_label_row(ws, INCOME_ROWS, INCOME_LABEL_COL, source)
    except LabelNotFoundError:
        return None
    return _numeric_or_none(ws.cell(row=row, column=INCOME_EXPECTED_COL).value)


def write_income(ws: Worksheet, source: str, *, expected: Optional[float] = None, actual: Optional[float] = None) -> None:
    row = _find_label_row(ws, INCOME_ROWS, INCOME_LABEL_COL, source)
    if expected is not None:
        ws.cell(row=row, column=INCOME_EXPECTED_COL, value=expected)
    if actual is not None:
        ws.cell(row=row, column=INCOME_ACTUAL_COL, value=actual)


def read_necessary_expense_planned(ws: Worksheet) -> dict[str, float]:
    result = {}
    for row in NECESSARY_EXPENSE_ROWS:
        category = ws.cell(row=row, column=NEC_EXP_LABEL_COL).value
        if category is None:
            continue
        result[category] = _numeric_or_none(ws.cell(row=row, column=NEC_EXP_PLANNED_COL).value) or 0
    return result


def write_necessary_expense_planned(ws: Worksheet, category: str, amount: float) -> None:
    row = _find_label_row(ws, NECESSARY_EXPENSE_ROWS, NEC_EXP_LABEL_COL, category)
    ws.cell(row=row, column=NEC_EXP_PLANNED_COL, value=amount)


def read_free_money_planned(ws: Worksheet) -> dict[str, float]:
    result = {}
    for row in FREE_MONEY_ROWS:
        category = ws.cell(row=row, column=FREE_MONEY_LABEL_COL).value
        if category is None:
            continue
        result[category] = _numeric_or_none(ws.cell(row=row, column=FREE_MONEY_PLANNED_COL).value) or 0
    return result


def read_free_money_planned_raw(ws: Worksheet, category: str) -> Optional[float]:
    """Single-category lookup used by recurring-value carry-forward - see
    read_income_expected_raw for why this returns None (never entered)
    rather than 0 for a blank cell."""
    try:
        row = _find_label_row(ws, FREE_MONEY_ROWS, FREE_MONEY_LABEL_COL, category)
    except LabelNotFoundError:
        return None
    return _numeric_or_none(ws.cell(row=row, column=FREE_MONEY_PLANNED_COL).value)


def write_free_money_planned(ws: Worksheet, category: str, amount: float) -> None:
    row = _find_label_row(ws, FREE_MONEY_ROWS, FREE_MONEY_LABEL_COL, category)
    ws.cell(row=row, column=FREE_MONEY_PLANNED_COL, value=amount)


def read_planned_investments_total(ws: Worksheet) -> float:
    """Sums the Amount column of the (read-only, manually-filled)
    Investments planning block. Deliberately does NOT read the workbook's
    own G8 "Planned Investments" formula, which sums the wrong column
    (a pre-existing bug, flagged separately) - this recomputes it correctly."""
    total = 0.0
    for row in INVESTMENT_PLAN_ROWS:
        total += _numeric_or_none(ws.cell(row=row, column=INVESTMENT_PLAN_AMOUNT_COL).value) or 0
    return total


def read_minimum_savings(ws: Worksheet) -> float:
    return _numeric_or_none(ws[MINIMUM_SAVINGS_CELL].value) or 0


def write_minimum_savings(ws: Worksheet, amount: float) -> None:
    ws[MINIMUM_SAVINGS_CELL] = amount
