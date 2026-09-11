from typing import Optional

from pydantic import BaseModel, Field


class IncomeSourceOut(BaseModel):
    source: str
    expected: float
    actual: float
    difference: float


class IncomeUpdate(BaseModel):
    expected: Optional[float] = Field(default=None, ge=0)
    actual: Optional[float] = Field(default=None, ge=0)
