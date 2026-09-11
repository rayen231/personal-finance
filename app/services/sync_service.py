"""Batch sync for the future mobile app's hourly offline-queue upload.

V1 supports create_transaction only (per spec) - the operation type is
still explicit and extensible so update/delete can be added later without
a breaking schema change. Idempotency is enforced via client_transaction_id
against the per-year ledger in sync_state, so a retried batch (e.g. after a
dropped response) never double-creates a transaction.
"""

from __future__ import annotations

import uuid

from app.models.sync import SyncFailure, SyncRequest, SyncResponse
from app.services import excel_service
from app.services.setup_service import read_setup_config
from app.services.validation import ValidationError, validate_transaction_fields
from app.services.workbook_repository import WorkbookRepository


class MixedYearBatchError(Exception):
    pass


class SyncService:
    def __init__(self, repo: WorkbookRepository):
        self.repo = repo

    def process_batch(self, request: SyncRequest) -> SyncResponse:
        years = {op.year for op in request.operations}
        if len(years) > 1:
            raise MixedYearBatchError(
                "All operations in one /sync batch must target the same year; "
                f"got {sorted(years)}. Split into separate batches per year."
            )
        year = years.pop()

        processed: list[str] = []
        failed: list[SyncFailure] = []
        any_written = False

        with self.repo.open_for_write(year) as handle:
            wb = handle.wb
            setup = read_setup_config(wb)

            for op in request.operations:
                if self.repo.sync_state.is_processed(year, op.client_transaction_id):
                    processed.append(op.client_transaction_id)
                    continue

                try:
                    validate_transaction_fields(setup, op.type, op.category, op.subcategory)
                    month_name = excel_service.month_name(op.month)
                    ws = wb[month_name]
                    row = excel_service.find_first_blank_row(ws, month_name)
                    excel_service.write_transaction_row(
                        ws,
                        row,
                        transaction_id=str(uuid.uuid4()),
                        tx_date=op.date,
                        tx_type=op.type,
                        category=op.category,
                        subcategory=op.subcategory,
                        item=op.item,
                        amount=op.amount,
                        classification=op.classification,
                        notes=op.notes,
                    )
                    excel_service.ensure_month_active(ws)
                except (ValidationError, excel_service.WorkbookError) as e:
                    reason = e.message if isinstance(e, ValidationError) else str(e)
                    failed.append(SyncFailure(client_transaction_id=op.client_transaction_id, reason=reason))
                    continue

                self.repo.sync_state.mark_processed(year, op.client_transaction_id)
                processed.append(op.client_transaction_id)
                any_written = True

            handle.changed = any_written

        return SyncResponse(
            success=len(failed) == 0,
            processed=processed,
            failed=failed,
            server_version=self.repo.sync_state.get_version(year),
        )
