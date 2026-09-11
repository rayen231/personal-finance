from datetime import date
from typing import Literal, Optional

from pydantic import BaseModel, Field, field_validator

TxType = Literal["Expense", "Free Money", "Investment"]


class TransactionCreate(BaseModel):
    date: date
    type: TxType
    category: str
    subcategory: str
    item: str = Field(..., min_length=1)
    amount: float = Field(..., gt=0)
    classification: Optional[str] = None
    notes: Optional[str] = None

    @field_validator("amount")
    @classmethod
    def amount_must_be_positive(cls, v: float) -> float:
        if v <= 0:
            raise ValueError("Amount must be greater than zero.")
        return v


class TransactionUpdate(BaseModel):
    date: Optional[date] = None
    type: Optional[TxType] = None
    category: Optional[str] = None
    subcategory: Optional[str] = None
    item: Optional[str] = None
    amount: Optional[float] = Field(default=None, gt=0)
    classification: Optional[str] = None
    notes: Optional[str] = None


class TransactionOut(BaseModel):
    id: str
    date: Optional[date]
    type: str
    category: str
    subcategory: str
    item: str
    amount: float
    classification: Optional[str] = None
    notes: Optional[str] = None
