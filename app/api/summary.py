from fastapi import APIRouter, Depends

from app.api.deps import get_planning_service, require_api_key
from app.models.summary import MonthlySummary
from app.services.planning_service import PlanningService

router = APIRouter(prefix="/api/v1", dependencies=[Depends(require_api_key)])


@router.get("/summary/{year}/{month}", response_model=MonthlySummary)
def get_monthly_summary(year: int, month: int, service: PlanningService = Depends(get_planning_service)):
    return service.get_summary(year, month)
