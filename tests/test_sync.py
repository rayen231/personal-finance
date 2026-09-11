from fastapi.testclient import TestClient


def _op(client_transaction_id, **overrides):
    op = {
        "operation": "create_transaction",
        "client_transaction_id": client_transaction_id,
        "year": 2026,
        "month": 9,
        "date": "2026-09-11",
        "type": "Expense",
        "category": "Food",
        "subcategory": "Chicken",
        "item": "Chicken breast",
        "amount": 18,
    }
    op.update(overrides)
    return op


def test_sync_batch_creates_all_transactions(client: TestClient):
    resp = client.post(
        "/api/v1/sync",
        json={
            "client_id": "android-device-001",
            "operations": [
                _op("tx-001"),
                _op("tx-002", type="Free Money", category="Restaurants", subcategory="Dinner", item="Pizza"),
                _op("tx-003", type="Investment", category="Education", subcategory="Course", item="IELTS"),
            ],
        },
    )
    assert resp.status_code == 200
    body = resp.json()
    assert body["success"] is True
    assert body["processed"] == ["tx-001", "tx-002", "tx-003"]
    assert body["failed"] == []
    assert body["server_version"] == 1

    listed = client.get("/api/v1/months/2026/9/transactions").json()
    assert len(listed) == 3


def test_sync_is_idempotent_on_retry(client: TestClient):
    payload = {"operations": [_op("tx-dup")]}
    first = client.post("/api/v1/sync", json=payload).json()
    assert first["processed"] == ["tx-dup"]
    assert first["server_version"] == 1

    # Simulate the phone retrying the same batch after a dropped response.
    second = client.post("/api/v1/sync", json=payload).json()
    assert second["processed"] == ["tx-dup"]
    assert second["failed"] == []
    # No new write happened - version stays where it was.
    assert second["server_version"] == 1

    listed = client.get("/api/v1/months/2026/9/transactions").json()
    assert len(listed) == 1


def test_sync_partial_failure_reports_both_lists(client: TestClient):
    resp = client.post(
        "/api/v1/sync",
        json={
            "operations": [
                _op("tx-good"),
                _op("tx-bad", category="NotARealCategory"),
            ]
        },
    )
    assert resp.status_code == 200
    body = resp.json()
    assert body["success"] is False
    assert body["processed"] == ["tx-good"]
    assert len(body["failed"]) == 1
    assert body["failed"][0]["client_transaction_id"] == "tx-bad"
    assert "invalid" in body["failed"][0]["reason"].lower() or "not valid" in body["failed"][0]["reason"].lower()


def test_sync_rejects_mixed_year_batch(client: TestClient):
    resp = client.post(
        "/api/v1/sync",
        json={"operations": [_op("tx-a", year=2026), _op("tx-b", year=2027)]},
    )
    assert resp.status_code == 400
    assert resp.json()["detail"]["error"] == "mixed_year_batch"
