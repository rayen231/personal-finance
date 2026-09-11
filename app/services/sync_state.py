"""Local metadata store for per-year server_version + processed sync IDs.

Deliberately kept out of the workbook itself (not "spreadsheet data" a human
needs to see) and out of a database (no DB in V1) - just a small JSON file
per year next to the workbook data.
"""

from __future__ import annotations

import json
from pathlib import Path
from threading import Lock

_file_locks: dict[int, Lock] = {}


def _lock_for(year: int) -> Lock:
    return _file_locks.setdefault(year, Lock())


class SyncStateStore:
    def __init__(self, base_dir: Path):
        self.base_dir = base_dir
        self.base_dir.mkdir(parents=True, exist_ok=True)

    def _path(self, year: int) -> Path:
        return self.base_dir / f"sync_state_{year}.json"

    def _read(self, year: int) -> dict:
        path = self._path(year)
        if not path.exists():
            return {"server_version": 0, "processed_ids": []}
        return json.loads(path.read_text())

    def _write(self, year: int, state: dict) -> None:
        path = self._path(year)
        tmp = path.with_suffix(".tmp")
        tmp.write_text(json.dumps(state))
        tmp.replace(path)

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
