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


class SetupOut(BaseModel):
    income_sources: list[str]
    expense_categories: list[str]
    subcategories: list[SubcategoryOut]
    free_money_categories: list[str]
    investment_areas: list[str]
    classifications: list[str]
    recurring_expenses: list[RecurringExpenseOut]
