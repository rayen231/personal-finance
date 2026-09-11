from __future__ import annotations

import uuid

from app.models.transaction import TransactionCreate, TransactionOut, TransactionUpdate
from app.services import excel_service
from app.services.setup_service import read_setup_config
from app.services.workbook_repository import WorkbookRepository


class ValidationError(Exception):
    def __init__(self, code: str, message: str):
        self.code = code
        self.message = message
        super().__init__(message)


def _validate_against_setup(setup, tx_type: str, category: str, subcategory: str) -> None:
    if not setup.is_valid_category_for_type(tx_type, category):
        raise ValidationError(
            "invalid_category",
            f"Category '{category}' is not valid for type '{tx_type}'.",
        )
    if not setup.is_valid_subcategory(tx_type, category, subcategory):
        raise ValidationError(
            "invalid_subcategory",
            f"Subcategory '{subcategory}' does not belong to category '{category}'.",
        )


def _row_to_out(row: excel_service.TransactionRow) -> TransactionOut:
    return TransactionOut(
        id=row.transaction_id,
        date=row.date,
        type=row.type,
        category=row.category,
        subcategory=row.subcategory,
        item=row.item,
        amount=row.amount,
        classification=row.classification,
        notes=row.notes,
    )


class FinanceService:
    def __init__(self, repo: WorkbookRepository):
        self.repo = repo

    def list_transactions(self, year: int, month: int) -> list[TransactionOut]:
        month_name = excel_service.month_name(month)
        wb = self.repo.open_for_read(year)
        rows = excel_service.list_transactions(wb[month_name], month_name)
        return [_row_to_out(r) for r in rows]

    def get_transaction(self, year: int, month: int, transaction_id: str) -> TransactionOut:
        month_name = excel_service.month_name(month)
        wb = self.repo.open_for_read(year)
        row = excel_service.get_transaction(wb[month_name], month_name, transaction_id)
        return _row_to_out(row)

    def create_transaction(
        self, year: int, month: int, payload: TransactionCreate, transaction_id: str | None = None
    ) -> TransactionOut:
        month_name = excel_service.month_name(month)
        transaction_id = transaction_id or str(uuid.uuid4())

        with self.repo.open_for_write(year) as wb:
            setup = read_setup_config(wb)
            _validate_against_setup(setup, payload.type, payload.category, payload.subcategory)

            ws = wb[month_name]
            row = excel_service.find_first_blank_row(ws, month_name)
            excel_service.write_transaction_row(
                ws,
                row,
                transaction_id=transaction_id,
                tx_date=payload.date,
                tx_type=payload.type,
                category=payload.category,
                subcategory=payload.subcategory,
                item=payload.item,
                amount=payload.amount,
                classification=payload.classification,
                notes=payload.notes,
            )
            excel_service.ensure_month_active(ws)
            result = excel_service.read_row(ws, row)

        return _row_to_out(result)

    def update_transaction(
        self, year: int, month: int, transaction_id: str, payload: TransactionUpdate
    ) -> TransactionOut:
        month_name = excel_service.month_name(month)

        with self.repo.open_for_write(year) as wb:
            ws = wb[month_name]
            row = excel_service.find_row_by_transaction_id(ws, month_name, transaction_id)
            current = excel_service.read_row(ws, row)

            new_type = payload.type or current.type
            new_category = payload.category or current.category
            new_subcategory = payload.subcategory or current.subcategory

            setup = read_setup_config(wb)
            _validate_against_setup(setup, new_type, new_category, new_subcategory)

            excel_service.write_transaction_row(
                ws,
                row,
                transaction_id=transaction_id,
                tx_date=payload.date or current.date,
                tx_type=new_type,
                category=new_category,
                subcategory=new_subcategory,
                item=payload.item or current.item,
                amount=payload.amount if payload.amount is not None else current.amount,
                classification=payload.classification
                if payload.classification is not None
                else current.classification,
                notes=payload.notes if payload.notes is not None else current.notes,
            )
            result = excel_service.read_row(ws, row)

        return _row_to_out(result)

    def delete_transaction(self, year: int, month: int, transaction_id: str) -> None:
        month_name = excel_service.month_name(month)
        with self.repo.open_for_write(year) as wb:
            ws = wb[month_name]
            row = excel_service.find_row_by_transaction_id(ws, month_name, transaction_id)
            excel_service.clear_transaction_row(ws, row)


def get_finance_service(repo: WorkbookRepository) -> FinanceService:
    return FinanceService(repo)
