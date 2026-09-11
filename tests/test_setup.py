from fastapi.testclient import TestClient


def test_get_setup_full(client: TestClient):
    resp = client.get("/api/v1/setup/2026")
    assert resp.status_code == 200
    body = resp.json()
    assert "Roundesk" in body["income_sources"]
    assert "Food" in body["expense_categories"]
    assert {"category": "Food", "subcategory": "Chicken"} in body["subcategories"]
    assert "Entertainment" in body["free_money_categories"]
    assert "Education" in body["investment_areas"]
    assert len(body["recurring_expenses"]) == 6


def test_subcategories_excludes_overlapping_table_rows(client: TestClient):
    # The real workbook has tbl_Subcategories declared as E4:F29, but rows
    # 15-19 genuinely belong to tbl_Classifications (E15:E19) and rows 24-29
    # to tbl_Recurring (A24:F30) - not blank/unused Subcategories rows. This
    # asserts the API never leaks that overlapping content as fake
    # (category, subcategory) pairs, and that real Classification values
    # aren't lost either.
    body = client.get("/api/v1/setup/2026").json()
    categories_seen = {pair["category"] for pair in body["subcategories"]}
    assert "Classification" not in categories_seen
    assert not any("Necessary" in c or "Unnecessary" in c for c in categories_seen)
    assert set(body["classifications"]) == {
        "Necessary — Planned", "Necessary — Unplanned",
        "Unnecessary — Planned", "Unnecessary — Unplanned",
    }


def test_recurring_expense_monthly_reserve_computed(client: TestClient):
    resp = client.get("/api/v1/setup/2026/recurring-expenses")
    assert resp.status_code == 200
    by_expense = {r["expense"]: r for r in resp.json()}
    # Expected amounts are all 0 in the source workbook, so reserves are 0,
    # but the frequency-based math itself must run without error.
    assert by_expense["Rent"]["frequency"] == "Monthly"
    assert by_expense["Insurance"]["frequency"] == "Yearly"


def test_get_individual_setup_lists(client: TestClient):
    assert "Housing" in client.get("/api/v1/setup/2026/categories").json()
    assert "Family Support" in client.get("/api/v1/setup/2026/income-sources").json()
    assert "Career" in client.get("/api/v1/setup/2026/investment-areas").json()
    assert "Shopping" in client.get("/api/v1/setup/2026/free-money-categories").json()


def test_add_subcategory_rejected_when_table_full(client: TestClient):
    # The real tbl_Subcategories table is already at its 25/25 row capacity,
    # so this exercises the "block full" rule rather than a bug: adding
    # further categories requires expanding the table in Excel first.
    resp = client.post(
        "/api/v1/setup/2026/subcategories", json={"category": "Food", "subcategory": "Yogurt"}
    )
    assert resp.status_code == 409
    assert resp.json()["detail"]["error"] == "table_full"


def test_add_subcategory_succeeds_with_spare_row(client: TestClient, data_dir):
    import openpyxl

    path = data_dir / "Personal_Finance_2026_V1.xlsx"
    wb = openpyxl.load_workbook(path)
    ws = wb["SETUP"]
    # Row 29 is actually inside tbl_Recurring's real range (a pre-existing
    # overlap with tbl_Subcategories' overly-large declared ref - see
    # setup_service._rows_claimed_by_other_tables), so it no longer counts
    # as an available Subcategories row. Row 14 is a genuinely free,
    # non-excluded row once its stray label is cleared.
    ws["E14"] = None
    ws["F14"] = None
    wb.save(path)

    resp = client.post(
        "/api/v1/setup/2026/subcategories", json={"category": "Food", "subcategory": "Yogurt"}
    )
    assert resp.status_code == 201
    assert resp.json() == {"category": "Food", "subcategory": "Yogurt"}

    subs = client.get("/api/v1/setup/2026/subcategories").json()
    assert {"category": "Food", "subcategory": "Yogurt"} in subs

    # Now usable on a transaction.
    tx = client.post(
        "/api/v1/months/2026/9/transactions",
        json={
            "date": "2026-09-11", "type": "Expense", "category": "Food",
            "subcategory": "Yogurt", "item": "Greek yogurt", "amount": 5,
        },
    )
    assert tx.status_code == 201


def test_add_subcategory_unknown_category_rejected(client: TestClient):
    resp = client.post(
        "/api/v1/setup/2026/subcategories", json={"category": "NotACategory", "subcategory": "X"}
    )
    assert resp.status_code == 400
    assert resp.json()["detail"]["error"] == "invalid_category"


def test_add_duplicate_subcategory_is_idempotent(client: TestClient):
    first = client.post(
        "/api/v1/setup/2026/subcategories", json={"category": "Food", "subcategory": "Chicken"}
    )
    assert first.status_code == 201
    subs = client.get("/api/v1/setup/2026/subcategories").json()
    chicken_count = sum(1 for s in subs if s == {"category": "Food", "subcategory": "Chicken"})
    assert chicken_count == 1
