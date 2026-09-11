import openpyxl
from fastapi.testclient import TestClient


def _create_payload(**overrides):
    payload = {
        "date": "2026-09-11",
        "type": "Expense",
        "category": "Food",
        "subcategory": "Chicken",
        "item": "Chicken breast",
        "amount": 18,
    }
    payload.update(overrides)
    return payload


def test_create_transaction_persists_to_workbook(client: TestClient, data_dir):
    resp = client.post("/api/v1/months/2026/9/transactions", json=_create_payload())
    assert resp.status_code == 201
    body = resp.json()
    assert body["id"]
    assert body["amount"] == 18
    assert body["category"] == "Food"

    # Reopen the actual saved file from disk (not through the API) to prove
    # the write really landed and the workbook is still a valid xlsx.
    wb = openpyxl.load_workbook(data_dir / "Personal_Finance_2026_V1.xlsx")
    ws = wb["SEPTEMBER"]
    table = ws.tables["tbl_SEPTEMBER_Transactions"]
    assert table.ref == "A42:L2000"

    row43 = [ws.cell(row=43, column=c).value for c in range(1, 6)]
    assert row43[2] == "Food"
    assert row43[3] == "Chicken"
    assert row43[4] == "Chicken breast"
    assert ws.cell(row=43, column=12).value == body["id"]


def test_month_status_auto_activates_on_first_write(client: TestClient, data_dir):
    wb = openpyxl.load_workbook(data_dir / "Personal_Finance_2026_V1.xlsx")
    wb["SEPTEMBER"]["B2"] = "Not Started"
    wb.save(data_dir / "Personal_Finance_2026_V1.xlsx")

    client.post("/api/v1/months/2026/9/transactions", json=_create_payload())

    wb2 = openpyxl.load_workbook(data_dir / "Personal_Finance_2026_V1.xlsx")
    assert wb2["SEPTEMBER"]["B2"].value == "Active"


def test_list_get_update_delete_roundtrip(client: TestClient):
    created = client.post("/api/v1/months/2026/9/transactions", json=_create_payload()).json()
    tx_id = created["id"]

    listed = client.get("/api/v1/months/2026/9/transactions").json()
    assert any(t["id"] == tx_id for t in listed)

    fetched = client.get(f"/api/v1/months/2026/9/transactions/{tx_id}").json()
    assert fetched["amount"] == 18

    updated = client.put(
        f"/api/v1/months/2026/9/transactions/{tx_id}", json={"amount": 25}
    ).json()
    assert updated["amount"] == 25
    assert updated["category"] == "Food"  # unchanged fields preserved

    del_resp = client.delete(f"/api/v1/months/2026/9/transactions/{tx_id}")
    assert del_resp.status_code == 204

    get_after_delete = client.get(f"/api/v1/months/2026/9/transactions/{tx_id}")
    assert get_after_delete.status_code == 404


def test_invalid_category_rejected(client: TestClient):
    resp = client.post(
        "/api/v1/months/2026/9/transactions",
        json=_create_payload(category="NotARealCategory"),
    )
    assert resp.status_code == 400
    assert resp.json()["detail"]["error"] == "invalid_category"


def test_invalid_subcategory_rejected(client: TestClient):
    resp = client.post(
        "/api/v1/months/2026/9/transactions",
        json=_create_payload(category="Food", subcategory="NotARealSubcategory"),
    )
    assert resp.status_code == 400
    assert resp.json()["detail"]["error"] == "invalid_subcategory"


def test_missing_api_key_rejected(client: TestClient):
    resp = client.post(
        "/api/v1/months/2026/9/transactions",
        json=_create_payload(),
        headers={"X-API-Key": "wrong-key"},
    )
    assert resp.status_code == 401


def test_multiple_creates_fill_successive_rows(client: TestClient, data_dir):
    first = client.post("/api/v1/months/2026/9/transactions", json=_create_payload()).json()
    second = client.post(
        "/api/v1/months/2026/9/transactions", json=_create_payload(item="Eggs")
    ).json()
    assert first["id"] != second["id"]

    wb = openpyxl.load_workbook(data_dir / "Personal_Finance_2026_V1.xlsx")
    ws = wb["SEPTEMBER"]
    assert ws.cell(row=43, column=12).value == first["id"]
    assert ws.cell(row=44, column=12).value == second["id"]
