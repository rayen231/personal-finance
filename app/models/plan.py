from pydantic import BaseModel, Field


class PlanOut(BaseModel):
    minimum_savings: float
    necessary_expenses_planned: dict[str, float]
    free_money_planned: dict[str, float]
    investments_planned_total: float


class PlanUpdate(BaseModel):
    minimum_savings: float | None = Field(default=None, ge=0)
    necessary_expenses_planned: dict[str, float] | None = None
    free_money_planned: dict[str, float] | None = None
