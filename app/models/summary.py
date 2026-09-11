from pydantic import BaseModel


class IncomeSummary(BaseModel):
    expected: float
    actual: float


class FreeMoneySummary(BaseModel):
    planned: float
    spent: float
    remaining: float


class MonthlySummary(BaseModel):
    year: int
    month: int
    income: IncomeSummary
    necessary_expenses_planned: float
    necessary_expenses_actual: float
    free_money: FreeMoneySummary
    investments_planned: float
    investments_actual: float
    minimum_savings: float
    extra_savings: float
    total_savings: float
