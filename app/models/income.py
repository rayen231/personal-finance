from typing import Optional

from pydantic import BaseModel, Field


class IncomeSourceOut(BaseModel):
    source: str
    expected: float
    # None means "not yet received/entered this month" - distinct from a
    # genuine 0, so the app can avoid showing a misleading negative
    # difference before the user has actually logged anything.
    actual: Optional[float]
    difference: Optional[float]


class IncomeUpdate(BaseModel):
    expected: Optional[float] = Field(default=None, ge=0)
    actual: Optional[float] = Field(default=None, ge=0)
