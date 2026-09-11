"""Relocates tbl_Subcategories out of its overlapping E4:F29 range into a
fresh, non-overlapping area of SETUP (columns H:I), and restores the
subcategories that were unreadable due to the overlap (Food/Fast Food,
Food/Snacks, Motorcycle/Fuel, Motorcycle/Oil, Motorcycle/Maintenance -
confirmed by the original project spec section 7's example hierarchy, not
guessed).

tbl_Classifications (E15:E19) and tbl_Recurring (A24:F30) are left
completely untouched - only the old tbl_Subcategories table definition and
its now-redundant cells (rows 5-13, 20-23 of columns E:F) are cleared.

Usage:
    python scripts/relocate_subcategories_table.py <path-to-workbook.xlsx>

Modifies the file in place. Not idempotent - only run once per workbook
(it will error clearly if tbl_Subcategories is already at the new location).
"""

import sys
from pathlib import Path

import openpyxl
from openpyxl.worksheet.table import Table, TableColumn, TableStyleInfo

NEW_ANCHOR = "H7"
NEW_HEADER_ROW = 7

# The 13 pairs that were safely readable (rows 5-13, 20-23 of the old E:F
# range), plus the 5 recovered ones the spec confirms belong to Food and
# Motorcycle. Order matches the spec's own example hierarchy.
SUBCATEGORIES = [
    ("Housing", "Rent"),
    ("Housing", "Cleaning"),
    ("Housing", "Grocery"),
    ("Housing", "Electricity"),
    ("Housing", "Water"),
    ("Food", "Chicken"),
    ("Food", "Eggs"),
    ("Food", "Rice"),
    ("Food", "Vegetables"),
    ("Food", "Fast Food"),
    ("Food", "Snacks"),
    ("Motorcycle", "Fuel"),
    ("Motorcycle", "Oil"),
    ("Motorcycle", "Maintenance"),
    ("Motorcycle", "Repair"),
    ("Motorcycle", "Insurance"),
    ("Motorcycle", "Accessories"),
    ("Communications", "Internet"),
]

OLD_TABLE_NAME = "tbl_Subcategories"
# Rows in the old E:F range that were genuinely this table's own data
# (i.e. NOT claimed by tbl_Classifications E15:E19 or tbl_Recurring
# A24:F30). Row 14's stray label is deliberately left untouched.
OLD_DATA_ROWS = list(range(5, 14)) + list(range(20, 24))


def relocate(path: Path) -> None:
    wb = openpyxl.load_workbook(path)
    ws = wb["SETUP"]

    if OLD_TABLE_NAME not in ws.tables:
        raise SystemExit(f"{OLD_TABLE_NAME} not found - already relocated?")

    old_table = ws.tables[OLD_TABLE_NAME]
    old_style = old_table.tableStyleInfo
    old_ref = old_table.ref
    print(f"Old table ref: {old_ref}")

    del ws.tables[OLD_TABLE_NAME]

    for row in OLD_DATA_ROWS:
        ws.cell(row=row, column=5).value = None  # E
        ws.cell(row=row, column=6).value = None  # F
    print(f"Cleared old data rows: {OLD_DATA_ROWS}")

    header_row = NEW_HEADER_ROW
    ws.cell(row=header_row, column=8, value="Category")
    ws.cell(row=header_row, column=9, value="Subcategory")
    for i, (category, subcategory) in enumerate(SUBCATEGORIES, start=1):
        ws.cell(row=header_row + i, column=8, value=category)
        ws.cell(row=header_row + i, column=9, value=subcategory)

    last_row = header_row + len(SUBCATEGORIES)
    new_ref = f"H{header_row}:I{last_row}"

    new_table = Table(displayName=OLD_TABLE_NAME, ref=new_ref)
    new_table.tableColumns = [
        TableColumn(id=1, name="Category"),
        TableColumn(id=2, name="Subcategory"),
    ]
    new_table.tableStyleInfo = old_style or TableStyleInfo(
        name="TableStyleMedium2", showRowStripes=True
    )
    ws.add_table(new_table)
    print(f"New table ref: {new_ref} ({len(SUBCATEGORIES)} rows)")

    wb.save(path)
    print(f"Saved: {path}")


if __name__ == "__main__":
    if len(sys.argv) != 2:
        print(__doc__)
        sys.exit(1)
    relocate(Path(sys.argv[1]))
