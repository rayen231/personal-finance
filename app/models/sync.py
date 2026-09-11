from datetime import date
from typing import Literal, Optional

from pydantic import BaseModel, Field

from app.models.transaction import TxType


class SyncOperation(BaseModel):
    operation: Literal["create_transaction"]
    client_transaction_id: str = Field(..., min_length=1)
    year: int
    month: int
    date: date
    type: TxType
    category: str
    subcategory: str
    item: str = Field(..., min_length=1)
    amount: float = Field(..., gt=0)
    classification: Optional[str] = None
    notes: Optional[str] = None


class SyncRequest(BaseModel):
    client_id: Optional[str] = None
    operations: list[SyncOperation] = Field(..., min_length=1)


class SyncFailure(BaseModel):
    client_transaction_id: str
    reason: str


class SyncResponse(BaseModel):
    success: bool
    processed: list[str]
    failed: list[SyncFailure]
    server_version: int
