from __future__ import annotations

from app.models.setup import RecurringExpenseOut, SetupOut, SubcategoryOut
from app.services import setup_service
from app.services.workbook_repository import WorkbookRepository


class SetupApiService:
    def __init__(self, repo: WorkbookRepository):
        self.repo = repo

    def get_setup(self, year: int) -> SetupOut:
        wb = self.repo.open_for_read(year)
        config = setup_service.read_setup_config(wb)
        recurring = setup_service.read_recurring_expenses(wb)
        return SetupOut(
            income_sources=config.income_sources,
            expense_categories=config.expense_categories,
            subcategories=[SubcategoryOut(category=c, subcategory=s) for c, s in config.subcategories],
            free_money_categories=config.free_money_categories,
            investment_areas=config.investment_areas,
            classifications=config.classifications,
            recurring_expenses=[RecurringExpenseOut(**r) for r in recurring],
        )

    def add_subcategory(self, year: int, category: str, subcategory: str) -> SubcategoryOut:
        with self.repo.open_for_write(year) as wb:
            setup_service.add_subcategory(wb, category, subcategory)
        return SubcategoryOut(category=category, subcategory=subcategory)
