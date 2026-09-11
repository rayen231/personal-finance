from fastapi import APIRouter, Depends, HTTPException, Query, status

from app.api.deps import get_finance_service, require_api_key
from app.models.transaction import TransactionCreate, TransactionOut, TransactionUpdate
from app.services import excel_service
from app.services.finance_service import FinanceService, ValidationError
from app.services.storage_service import WorkbookNotFoundError

router = APIRouter(prefix="/api/v1", dependencies=[Depends(require_api_key)])


def _error(code: str, message: str, http_status: int) -> HTTPException:
    return HTTPException(status_code=http_status, detail={"error": code, "message": message})


@router.get("/months/{year}/{month}/transactions", response_model=list[TransactionOut])
def list_transactions(
    year: int,
    month: int,
    limit: int = Query(default=50, le=200, gt=0),
    offset: int = Query(default=0, ge=0),
    service: FinanceService = Depends(get_finance_service),
):
    try:
        results = service.list_transactions(year, month)
    except excel_service.WorkbookError as e:
        raise _error("invalid_request", str(e), status.HTTP_400_BAD_REQUEST)
    except WorkbookNotFoundError as e:
        raise _error("not_found", str(e), status.HTTP_404_NOT_FOUND)
    return results[offset : offset + limit]


@router.get("/months/{year}/{month}/transactions/{transaction_id}", response_model=TransactionOut)
def get_transaction(
    year: int,
    month: int,
    transaction_id: str,
    service: FinanceService = Depends(get_finance_service),
):
    try:
        return service.get_transaction(year, month, transaction_id)
    except excel_service.TransactionNotFoundError:
        raise _error("not_found", f"Transaction '{transaction_id}' not found.", status.HTTP_404_NOT_FOUND)
    except excel_service.WorkbookError as e:
        raise _error("invalid_request", str(e), status.HTTP_400_BAD_REQUEST)


@router.post(
    "/months/{year}/{month}/transactions",
    response_model=TransactionOut,
    status_code=status.HTTP_201_CREATED,
)
def create_transaction(
    year: int,
    month: int,
    payload: TransactionCreate,
    service: FinanceService = Depends(get_finance_service),
):
    try:
        return service.create_transaction(year, month, payload)
    except ValidationError as e:
        raise _error(e.code, e.message, status.HTTP_400_BAD_REQUEST)
    except excel_service.TableFullError as e:
        raise _error("table_full", str(e), status.HTTP_409_CONFLICT)
    except excel_service.WorkbookError as e:
        raise _error("invalid_request", str(e), status.HTTP_400_BAD_REQUEST)
    except WorkbookNotFoundError as e:
        raise _error("not_found", str(e), status.HTTP_404_NOT_FOUND)


@router.put("/months/{year}/{month}/transactions/{transaction_id}", response_model=TransactionOut)
def update_transaction(
    year: int,
    month: int,
    transaction_id: str,
    payload: TransactionUpdate,
    service: FinanceService = Depends(get_finance_service),
):
    try:
        return service.update_transaction(year, month, transaction_id, payload)
    except excel_service.TransactionNotFoundError:
        raise _error("not_found", f"Transaction '{transaction_id}' not found.", status.HTTP_404_NOT_FOUND)
    except ValidationError as e:
        raise _error(e.code, e.message, status.HTTP_400_BAD_REQUEST)
    except excel_service.WorkbookError as e:
        raise _error("invalid_request", str(e), status.HTTP_400_BAD_REQUEST)


@router.delete(
    "/months/{year}/{month}/transactions/{transaction_id}",
    status_code=status.HTTP_204_NO_CONTENT,
)
def delete_transaction(
    year: int,
    month: int,
    transaction_id: str,
    service: FinanceService = Depends(get_finance_service),
):
    try:
        service.delete_transaction(year, month, transaction_id)
    except excel_service.TransactionNotFoundError:
        raise _error("not_found", f"Transaction '{transaction_id}' not found.", status.HTTP_404_NOT_FOUND)
    except excel_service.WorkbookError as e:
        raise _error("invalid_request", str(e), status.HTTP_400_BAD_REQUEST)
