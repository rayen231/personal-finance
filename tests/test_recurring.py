from fastapi.testclient import TestClient


def test_recurring_flag_toggle_and_setup_listing(client: TestClient):
    resp = client.get("/api/v1/setup/2026")
    flags = resp.json()["recurring_flags"]
    assert flags == {"income_sources": [], "free_money_categories": [], "subcategories": []}

    resp = client.put("/api/v1/setup/2026/recurring/income-sources/Roundesk", json={"recurring": True})
    assert resp.status_code == 204

    flags = client.get("/api/v1/setup/2026").json()["recurring_flags"]
    assert flags["income_sources"] == ["Roundesk"]

    resp = client.put("/api/v1/setup/2026/recurring/income-sources/Roundesk", json={"recurring": False})
    assert resp.status_code == 204
    flags = client.get("/api/v1/setup/2026").json()["recurring_flags"]
    assert flags["income_sources"] == []


def test_income_expected_carries_forward_for_recurring_source(client: TestClient):
    client.put("/api/v1/setup/2026/recurring/income-sources/Roundesk", json={"recurring": True})

    # September: user enters a real expected figure.
    client.put("/api/v1/months/2026/9/income/Roundesk", json={"expected": 500})

    # October: never touched - should show September's expected, carried
    # forward, while a non-recurring source (GoMyCode) stays at 0.
    october = {r["source"]: r for r in client.get("/api/v1/months/2026/10/income").json()}
    assert october["Roundesk"]["expected"] == 500
    assert october["Roundesk"]["actual"] is None  # actual never carries, only expected
    assert october["GoMyCode"]["expected"] == 0

    # Editing October's actual (receiving the money) shouldn't touch September,
    # and shouldn't corrupt carry-forward for later months either (a month
    # touched only via "actual" must not be mistaken for one with a real
    # "expected" of its own).
    client.put("/api/v1/months/2026/10/income/Roundesk", json={"actual": 500})
    september = {r["source"]: r for r in client.get("/api/v1/months/2026/9/income").json()}
    assert september["Roundesk"]["expected"] == 500
    assert september["Roundesk"]["actual"] is None

    november = {r["source"]: r for r in client.get("/api/v1/months/2026/11/income").json()}
    assert november["Roundesk"]["expected"] == 500  # still carried from September, not October's blank


def test_income_carry_forward_uses_nearest_month_not_just_previous(client: TestClient):
    client.put("/api/v1/setup/2026/recurring/income-sources/Roundesk", json={"recurring": True})
    client.put("/api/v1/months/2026/9/income/Roundesk", json={"expected": 500})

    # October and November are both left untouched - November should still
    # see September's value by walking back past the untouched October.
    november = {r["source"]: r for r in client.get("/api/v1/months/2026/11/income").json()}
    assert november["Roundesk"]["expected"] == 500


def test_changing_a_later_month_does_not_affect_earlier_months(client: TestClient):
    client.put("/api/v1/setup/2026/recurring/income-sources/Roundesk", json={"recurring": True})
    client.put("/api/v1/months/2026/9/income/Roundesk", json={"expected": 500})
    client.put("/api/v1/months/2026/10/income/Roundesk", json={"expected": 800})

    september = {r["source"]: r for r in client.get("/api/v1/months/2026/9/income").json()}
    november = {r["source"]: r for r in client.get("/api/v1/months/2026/11/income").json()}
    assert september["Roundesk"]["expected"] == 500  # untouched by October's change
    assert november["Roundesk"]["expected"] == 800  # picks up the nearest (October) value


def test_free_money_planned_carries_forward_for_recurring_category(client: TestClient):
    client.put(
        "/api/v1/setup/2026/recurring/free-money-categories/Entertainment", json={"recurring": True}
    )
    client.put("/api/v1/plan/2026/9", json={"free_money_planned": {"Entertainment": 60}})

    october_plan = client.get("/api/v1/plan/2026/10").json()
    assert october_plan["free_money_planned"]["Entertainment"] == 60


def test_non_recurring_income_source_never_carries(client: TestClient):
    client.put("/api/v1/months/2026/9/income/GoMyCode", json={"expected": 200})
    october = {r["source"]: r for r in client.get("/api/v1/months/2026/10/income").json()}
    assert october["GoMyCode"]["expected"] == 0
