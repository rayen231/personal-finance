"""Tracks which SETUP items (income sources, free-money categories,
necessary-expense subcategories) are flagged "recurring".

Kept as a small JSON blob per year (same StorageService-backed pattern as
SyncStateStore) rather than as extra columns in the SETUP Excel tables -
those tables have already been bitten once by row-range overlaps with
neighboring tables, so a new, independent file avoids that risk entirely.

A flagged item's value carries forward from month to month (see
PlanningService's carry-forward logic for income/free-money, and the
mobile app's local carry-forward for necessary-expense subcategories,
whose per-subcategory breakdown never reaches the server); an unflagged
item starts blank/zero each month for manual entry.
"""

from __future__ import annotations

import json
from threading import Lock

from app.services.storage_service import StorageService, WorkbookNotFoundError

JSON_CONTENT_TYPE = "application/json"

_flag_locks: dict[int, Lock] = {}


def _lock_for(year: int) -> Lock:
    return _flag_locks.setdefault(year, Lock())


def _subcategory_key(category: str, subcategory: str) -> str:
    return f"{category}|{subcategory}"


class RecurringFlagsStore:
    def __init__(self, storage: StorageService):
        self.storage = storage

    def _filename(self, year: int) -> str:
        return f"recurring_flags_{year}.json"

    def _read(self, year: int) -> dict:
        try:
            content = self.storage.download(self._filename(year))
        except WorkbookNotFoundError:
            return {"income_sources": [], "free_money_categories": [], "subcategories": []}
        return json.loads(content)

    def _write(self, year: int, data: dict) -> None:
        self.storage.upload(
            self._filename(year), json.dumps(data).encode("utf-8"), content_type=JSON_CONTENT_TYPE
        )

    def get(self, year: int) -> dict:
        """Returns {"income_sources": [...], "free_money_categories": [...],
        "subcategories": [{"category":..., "subcategory":...}, ...]}."""
        with _lock_for(year):
            data = self._read(year)
        return {
            "income_sources": sorted(data["income_sources"]),
            "free_money_categories": sorted(data["free_money_categories"]),
            "subcategories": [
                {"category": c, "subcategory": s}
                for c, s in sorted(
                    (key.split("|", 1)[0], key.split("|", 1)[1]) for key in data["subcategories"]
                )
            ],
        }

    def is_income_source_recurring(self, year: int, source: str) -> bool:
        with _lock_for(year):
            return source in self._read(year)["income_sources"]

    def is_free_money_category_recurring(self, year: int, category: str) -> bool:
        with _lock_for(year):
            return category in self._read(year)["free_money_categories"]

    def set_income_source(self, year: int, source: str, recurring: bool) -> None:
        with _lock_for(year):
            data = self._read(year)
            items = set(data["income_sources"])
            items.add(source) if recurring else items.discard(source)
            data["income_sources"] = sorted(items)
            self._write(year, data)

    def set_free_money_category(self, year: int, category: str, recurring: bool) -> None:
        with _lock_for(year):
            data = self._read(year)
            items = set(data["free_money_categories"])
            items.add(category) if recurring else items.discard(category)
            data["free_money_categories"] = sorted(items)
            self._write(year, data)

    def set_subcategory(self, year: int, category: str, subcategory: str, recurring: bool) -> None:
        with _lock_for(year):
            data = self._read(year)
            key = _subcategory_key(category, subcategory)
            items = set(data["subcategories"])
            items.add(key) if recurring else items.discard(key)
            data["subcategories"] = sorted(items)
            self._write(year, data)
