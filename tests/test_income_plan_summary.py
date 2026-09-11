from fastapi.testclient import TestClient


def test_list_income_defaults(client: TestClient):
    resp = client.get("/api/v1/months/2026/9/income")
    assert resp.status_code == 200
    sources = {r["source"]: r for r in resp.json()}
    assert set(sources) == {"Roundesk", "GoMyCode", "Freelance", "Family Support"}
    assert sources["Roundesk"]["expected"] == 0
    assert sources["Roundesk"]["difference"] == 0


def test_update_income_source(client: TestClient):
    resp = client.put(
        "/api/v1/months/2026/9/income/Roundesk", json={"expected": 1500, "actual": 1550}
    )
    assert resp.status_code == 200
    body = resp.json()
    assert body["expected"] == 1500
    assert body["actual"] == 1550
    assert body["difference"] == 50

    listed = {r["source"]: r for r in client.get("/api/v1/months/2026/9/income").json()}
    assert listed["Roundesk"]["actual"] == 1550
    assert listed["GoMyCode"]["actual"] == 0  # untouched


def test_update_unknown_income_source_rejected(client: TestClient):
    resp = client.put("/api/v1/months/2026/9/income/NotARealSource", json={"expected": 100})
    assert resp.status_code == 404
    assert resp.json()["detail"]["error"] == "unknown_income_source"


def test_get_plan_defaults(client: TestClient):
    resp = client.get("/api/v1/plan/2026/9")
    assert resp.status_code == 200
    body = resp.json()
    assert body["minimum_savings"] == 0
    assert body["necessary_expenses_planned"]["Food"] == 0
    assert body["investments_planned_total"] == 0


def test_update_plan(client: TestClient):
    resp = client.put(
        "/api/v1/plan/2026/9",
        json={
            "minimum_savings": 500,
            "necessary_expenses_planned": {"Food": 200, "Housing": 600},
            "free_money_planned": {"Entertainment": 50},
        },
    )
    assert resp.status_code == 200
    body = resp.json()
    assert body["minimum_savings"] == 500
    assert body["necessary_expenses_planned"]["Food"] == 200
    assert body["necessary_expenses_planned"]["Housing"] == 600
    assert body["necessary_expenses_planned"]["Motorcycle"] == 0  # untouched
    assert body["free_money_planned"]["Entertainment"] == 50


def test_update_plan_unknown_category_rejected(client: TestClient):
    resp = client.put(
        "/api/v1/plan/2026/9",
        json={"necessary_expenses_planned": {"NotACategory": 100}},
    )
    assert resp.status_code == 404
    assert resp.json()["detail"]["error"] == "unknown_category"


def test_summary_computes_from_transactions_and_plan(client: TestClient):
    client.put("/api/v1/months/2026/9/income/Roundesk", json={"expected": 1500, "actual": 1500})
    client.put("/api/v1/plan/2026/9", json={"minimum_savings": 200})

    client.post(
        "/api/v1/months/2026/9/transactions",
        json={
            "date": "2026-09-11", "type": "Expense", "category": "Food",
            "subcategory": "Chicken", "item": "Chicken breast", "amount": 50,
        },
    )
    client.post(
        "/api/v1/months/2026/9/transactions",
        json={
            "date": "2026-09-11", "type": "Free Money", "category": "Restaurants",
            "subcategory": "Dinner", "item": "Restaurant", "amount": 30,
        },
    )
    client.post(
        "/api/v1/months/2026/9/transactions",
        json={
            "date": "2026-09-11", "type": "Investment", "category": "Education",
            "subcategory": "Course", "item": "IELTS", "amount": 100,
        },
    )

    resp = client.get("/api/v1/summary/2026/9")
    assert resp.status_code == 200
    body = resp.json()
    assert body["income"]["actual"] == 1500
    assert body["necessary_expenses_actual"] == 50
    assert body["free_money"]["spent"] == 30
    assert body["investments_actual"] == 100
    assert body["minimum_savings"] == 200
    # extra_savings = max(0, 1500 - 50 - 100 - 30 - 200) = 1120
    assert body["extra_savings"] == 1120
    assert body["total_savings"] == 1320
