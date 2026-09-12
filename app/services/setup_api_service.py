from __future__ import annotations

from app.models.setup import RecurringExpenseOut, SetupOut, SubcategoryOut
from app.services import setup_service
from app.services.workbook_repository import WorkbookRepository

# Maps the API's list-kind names to the SETUP table they actually live in.
_LIST_TABLES = {
    "categories": "tbl_ExpenseCategories",
    "income-sources": "tbl_IncomeSources",
    "free-money-categories": "tbl_FreeMoneyCategories",
    "investment-areas": "tbl_InvestmentAreas",
}


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

    def add_list_value(self, year: int, list_kind: str, value: str) -> str:
        table_name = _LIST_TABLES[list_kind]
        with self.repo.open_for_write(year) as handle:
            handle.changed = setup_service.add_single_value(handle.wb, table_name, value)
        return value

    def edit_list_value(self, year: int, list_kind: str, old_value: str, new_value: str) -> str:
        table_name = _LIST_TABLES[list_kind]
        with self.repo.open_for_write(year) as handle:
            setup_service.edit_single_value(handle.wb, table_name, old_value, new_value)
        return new_value

    def delete_list_value(self, year: int, list_kind: str, value: str) -> None:
        table_name = _LIST_TABLES[list_kind]
        with self.repo.open_for_write(year) as handle:
            setup_service.delete_single_value(handle.wb, table_name, value)

    def add_subcategory(self, year: int, category: str, subcategory: str) -> SubcategoryOut:
        with self.repo.open_for_write(year) as handle:
            handle.changed = setup_service.add_subcategory(handle.wb, category, subcategory)
        return SubcategoryOut(category=category, subcategory=subcategory)

    def edit_subcategory(
        self, year: int, category: str, old_subcategory: str, new_subcategory: str
    ) -> SubcategoryOut:
        with self.repo.open_for_write(year) as handle:
            setup_service.edit_subcategory(handle.wb, category, old_subcategory, new_subcategory)
        return SubcategoryOut(category=category, subcategory=new_subcategory)

    def delete_subcategory(self, year: int, category: str, subcategory: str) -> None:
        with self.repo.open_for_write(year) as handle:
            setup_service.delete_subcategory(handle.wb, category, subcategory)
