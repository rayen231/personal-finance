from fastapi import APIRouter, Depends, HTTPException, status

from app.api.deps import get_planning_service, require_api_key
from app.models.plan import PlanOut, PlanUpdate
from app.services import excel_service
from app.services.planning_service import PlanningService

router = APIRouter(prefix="/api/v1", dependencies=[Depends(require_api_key)])


@router.get("/plan/{year}/{month}", response_model=PlanOut)
def get_plan(year: int, month: int, service: PlanningService = Depends(get_planning_service)):
    return service.get_plan(year, month)


@router.put("/plan/{year}/{month}", response_model=PlanOut)
def update_plan(
    year: int,
    month: int,
    payload: PlanUpdate,
    service: PlanningService = Depends(get_planning_service),
):
    try:
        return service.update_plan(year, month, payload)
    except excel_service.LabelNotFoundError as e:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail={"error": "unknown_category", "message": str(e)},
        )
