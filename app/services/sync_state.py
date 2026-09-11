"""Metadata store for per-year server_version + processed sync IDs.

Deliberately kept out of the workbook itself (not "spreadsheet data" a human
needs to see) and out of a database (no DB in V1) - just a small JSON blob
per year, going through the same StorageService as the workbook itself so
this works identically on local disk and on Vercel Blob (a serverless
function's filesystem is read-only outside /tmp, so this can't assume a
writable local path the way it originally did).
"""

from __future__ import annotations

import json
from threading import Lock

from app.services.storage_service import StorageService, WorkbookNotFoundError

JSON_CONTENT_TYPE = "application/json"

_state_locks: dict[int, Lock] = {}


def _lock_for(year: int) -> Lock:
    return _state_locks.setdefault(year, Lock())


class SyncStateStore:
    def __init__(self, storage: StorageService):
        self.storage = storage

    def _filename(self, year: int) -> str:
        return f"sync_state_{year}.json"

    def _read(self, year: int) -> dict:
        try:
            content = self.storage.download(self._filename(year))
        except WorkbookNotFoundError:
            return {"server_version": 0, "processed_ids": []}
        return json.loads(content)

    def _write(self, year: int, state: dict) -> None:
        self.storage.upload(
            self._filename(year), json.dumps(state).encode("utf-8"), content_type=JSON_CONTENT_TYPE
        )

    def get_version(self, year: int) -> int:
        with _lock_for(year):
            return self._read(year)["server_version"]

    def bump_version(self, year: int) -> int:
        with _lock_for(year):
            state = self._read(year)
            state["server_version"] += 1
            self._write(year, state)
            return state["server_version"]

    def is_processed(self, year: int, client_transaction_id: str) -> bool:
        with _lock_for(year):
            return client_transaction_id in self._read(year)["processed_ids"]

    def mark_processed(self, year: int, client_transaction_id: str) -> None:
        with _lock_for(year):
            state = self._read(year)
            if client_transaction_id not in state["processed_ids"]:
                state["processed_ids"].append(client_transaction_id)
            self._write(year, state)
