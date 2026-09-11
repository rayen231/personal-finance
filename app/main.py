from fastapi import FastAPI

from app.api import income, plan, summary, transactions

app = FastAPI(title="Personal Finance API", version="0.1.0")

app.include_router(transactions.router)
app.include_router(income.router)
app.include_router(plan.router)
app.include_router(summary.router)


@app.get("/health")
def health():
    return {"status": "ok"}
