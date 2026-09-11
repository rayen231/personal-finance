from fastapi import APIRouter, Depends, HTTPException, status

from app.api.deps import get_planning_service, require_api_key
from app.models.income import IncomeSourceOut, IncomeUpdate
from app.services import excel_service
from app.services.planning_service import PlanningService

router = APIRouter(prefix="/api/v1", dependencies=[Depends(require_api_key)])


@router.get("/months/{year}/{month}/income", response_model=list[IncomeSourceOut])
def list_income(year: int, month: int, service: PlanningService = Depends(get_planning_service)):
    return service.list_income(year, month)


@router.put("/months/{year}/{month}/income/{source}", response_model=IncomeSourceOut)
def update_income(
    year: int,
    month: int,
    source: str,
    payload: IncomeUpdate,
    service: PlanningService = Depends(get_planning_service),
):
    try:
        return service.update_income(year, month, source, payload)
    except excel_service.LabelNotFoundError as e:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail={"error": "unknown_income_source", "message": str(e)},
        )
