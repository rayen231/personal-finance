from fastapi import Depends, Header, HTTPException, status

from app.config import Settings, get_settings
from app.services.finance_service import FinanceService
from app.services.planning_service import PlanningService
from app.services.recurring_flags import RecurringFlagsStore
from app.services.setup_api_service import SetupApiService
from app.services.storage_service import get_storage_service
from app.services.sync_state import SyncStateStore
from app.services.workbook_repository import WorkbookRepository


def require_api_key(
    x_api_key: str = Header(default=""),
    settings: Settings = Depends(get_settings),
) -> None:
    if x_api_key != settings.api_key:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid or missing API key.")


def get_repo(settings: Settings = Depends(get_settings)) -> WorkbookRepository:
    storage = get_storage_service(settings)
    sync_state = SyncStateStore(storage)
    return WorkbookRepository(storage, settings, sync_state)


def get_finance_service(repo: WorkbookRepository = Depends(get_repo)) -> FinanceService:
    return FinanceService(repo)


def get_recurring_flags(settings: Settings = Depends(get_settings)) -> RecurringFlagsStore:
    return RecurringFlagsStore(get_storage_service(settings))


def get_planning_service(
    repo: WorkbookRepository = Depends(get_repo),
    recurring_flags: RecurringFlagsStore = Depends(get_recurring_flags),
) -> PlanningService:
    return PlanningService(repo, recurring_flags)


def get_setup_service(
    repo: WorkbookRepository = Depends(get_repo),
    recurring_flags: RecurringFlagsStore = Depends(get_recurring_flags),
) -> SetupApiService:
    return SetupApiService(repo, recurring_flags)
