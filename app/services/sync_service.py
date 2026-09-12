"""Batch sync for the future mobile app's hourly offline-queue upload.

V1 supports create_transaction only (per spec) - the operation type is
still explicit and extensible so update/delete can be added later without
a breaking schema change.

Idempotency has two layers:
1. The per-year ledger in sync_state (fast path, checked first).
2. The workbook itself: the row's TransactionID is set to the client's own
   client_transaction_id (not a server-generated one), so a second write
   attempt for the same id is detected by scanning the actual data, not
   just the ledger. This matters because the ledger check + write aren't
   atomic across concurrent requests (e.g. two near-simultaneous /sync
   calls hitting separate serverless instances, each with only an
   in-process lock) - the workbook-level check is what actually prevents a
   duplicate row from being written even if both requests race past the
   ledger check. Using the client's own id (rather than generating a new
   uuid server-side) is also what lets the app reference this exact
   transaction later for update/delete.
"""

from __future__ import annotations

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

                month_name = excel_service.month_name(op.month)
                ws = wb[month_name]

                # Authoritative check against the real data, not just the
                # ledger - see module docstring on why both matter.
                try:
                    excel_service.find_row_by_transaction_id(ws, month_name, op.client_transaction_id)
                    self.repo.sync_state.mark_processed(year, op.client_transaction_id)
                    processed.append(op.client_transaction_id)
                    continue
                except excel_service.TransactionNotFoundError:
                    pass

                try:
                    validate_transaction_fields(setup, op.type, op.category, op.subcategory)
                    row = excel_service.find_first_blank_row(ws, month_name)
                    excel_service.write_transaction_row(
                        ws,
                        row,
                        transaction_id=op.client_transaction_id,
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
