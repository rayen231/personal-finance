from typing import Literal

from fastapi import APIRouter, Depends, HTTPException, status

from app.api.deps import get_setup_service, require_api_key
from app.models.setup import ListValuePayload, SetupOut, SubcategoryCreate, SubcategoryOut, SubcategoryRename
from app.services import excel_service
from app.services.setup_api_service import SetupApiService

router = APIRouter(prefix="/api/v1/setup", dependencies=[Depends(require_api_key)])

ListKind = Literal["categories", "income-sources", "free-money-categories", "investment-areas"]


def _handle_label_errors(fn, *args):
    try:
        return fn(*args)
    except excel_service.LabelNotFoundError as e:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail={"error": "not_found", "message": str(e)},
        )
    except excel_service.TableFullError as e:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail={"error": "table_full", "message": str(e)},
        )


@router.get("/{year}", response_model=SetupOut)
def get_setup(year: int, service: SetupApiService = Depends(get_setup_service)):
    return service.get_setup(year)


@router.get("/{year}/categories", response_model=list[str])
def get_categories(year: int, service: SetupApiService = Depends(get_setup_service)):
    return service.get_setup(year).expense_categories


@router.get("/{year}/subcategories", response_model=list[SubcategoryOut])
def get_subcategories(year: int, service: SetupApiService = Depends(get_setup_service)):
    return service.get_setup(year).subcategories


@router.get("/{year}/income-sources", response_model=list[str])
def get_income_sources(year: int, service: SetupApiService = Depends(get_setup_service)):
    return service.get_setup(year).income_sources


@router.get("/{year}/free-money-categories", response_model=list[str])
def get_free_money_categories(year: int, service: SetupApiService = Depends(get_setup_service)):
    return service.get_setup(year).free_money_categories


@router.get("/{year}/investment-areas", response_model=list[str])
def get_investment_areas(year: int, service: SetupApiService = Depends(get_setup_service)):
    return service.get_setup(year).investment_areas


@router.get("/{year}/recurring-expenses")
def get_recurring_expenses(year: int, service: SetupApiService = Depends(get_setup_service)):
    return service.get_setup(year).recurring_expenses


@router.post("/{year}/subcategories", response_model=SubcategoryOut, status_code=status.HTTP_201_CREATED)
def create_subcategory(
    year: int, payload: SubcategoryCreate, service: SetupApiService = Depends(get_setup_service)
):
    try:
        return service.add_subcategory(year, payload.category, payload.subcategory)
    except excel_service.LabelNotFoundError as e:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail={"error": "invalid_category", "message": str(e)},
        )
    except excel_service.TableFullError as e:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail={"error": "table_full", "message": str(e)},
        )


@router.put("/{year}/subcategories/{category}/{subcategory}", response_model=SubcategoryOut)
def rename_subcategory(
    year: int,
    category: str,
    subcategory: str,
    payload: SubcategoryRename,
    service: SetupApiService = Depends(get_setup_service),
):
    return _handle_label_errors(
        service.edit_subcategory, year, category, subcategory, payload.subcategory
    )


@router.delete("/{year}/subcategories/{category}/{subcategory}", status_code=status.HTTP_204_NO_CONTENT)
def remove_subcategory(
    year: int, category: str, subcategory: str, service: SetupApiService = Depends(get_setup_service)
):
    _handle_label_errors(service.delete_subcategory, year, category, subcategory)


# --- Generic add/rename/delete for the four single-column SETUP lists ----

@router.post("/{year}/{list_kind}", status_code=status.HTTP_201_CREATED)
def add_list_value(
    year: int,
    list_kind: ListKind,
    payload: ListValuePayload,
    service: SetupApiService = Depends(get_setup_service),
):
    return {"value": _handle_label_errors(service.add_list_value, year, list_kind, payload.value)}


@router.put("/{year}/{list_kind}/{value}")
def rename_list_value(
    year: int,
    list_kind: ListKind,
    value: str,
    payload: ListValuePayload,
    service: SetupApiService = Depends(get_setup_service),
):
    return {
        "value": _handle_label_errors(service.edit_list_value, year, list_kind, value, payload.value)
    }


@router.delete("/{year}/{list_kind}/{value}", status_code=status.HTTP_204_NO_CONTENT)
def delete_list_value(
    year: int, list_kind: ListKind, value: str, service: SetupApiService = Depends(get_setup_service)
):
    _handle_label_errors(service.delete_list_value, year, list_kind, value)
