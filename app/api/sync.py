from fastapi import APIRouter, Depends, HTTPException, status

from app.api.deps import get_repo, require_api_key
from app.models.sync import SyncRequest, SyncResponse
from app.services.sync_service import MixedYearBatchError, SyncService
from app.services.workbook_repository import WorkbookRepository

router = APIRouter(prefix="/api/v1", dependencies=[Depends(require_api_key)])


@router.post("/sync", response_model=SyncResponse)
def sync(payload: SyncRequest, repo: WorkbookRepository = Depends(get_repo)):
    service = SyncService(repo)
    try:
        return service.process_batch(payload)
    except MixedYearBatchError as e:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail={"error": "mixed_year_batch", "message": str(e)},
        )
