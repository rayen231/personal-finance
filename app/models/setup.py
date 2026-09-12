from typing import Optional

from pydantic import BaseModel


class SubcategoryOut(BaseModel):
    category: str
    subcategory: str


class SubcategoryCreate(BaseModel):
    category: str
    subcategory: str


class ListValuePayload(BaseModel):
    value: str


class SubcategoryRename(BaseModel):
    subcategory: str


class RecurringExpenseOut(BaseModel):
    expense: str
    category: Optional[str]
    frequency: Optional[str]
    expected_amount: float
    monthly_reserve: float
    notes: Optional[str]


class RecurringFlagsOut(BaseModel):
    """Which SETUP items carry their value forward month to month instead of
    resetting to blank/zero. Unrelated to RecurringExpenseOut above, which is
    just a read-only monthly-reserve calculator."""

    income_sources: list[str]
    free_money_categories: list[str]
    subcategories: list[SubcategoryOut]


class RecurringFlagPayload(BaseModel):
    recurring: bool


class SetupOut(BaseModel):
    income_sources: list[str]
    expense_categories: list[str]
    subcategories: list[SubcategoryOut]
    free_money_categories: list[str]
    investment_areas: list[str]
    classifications: list[str]
    recurring_expenses: list[RecurringExpenseOut]
    recurring_flags: RecurringFlagsOut
