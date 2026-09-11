from fastapi import FastAPI

from app.api import transactions

app = FastAPI(title="Personal Finance API", version="0.1.0")

app.include_router(transactions.router)


@app.get("/health")
def health():
    return {"status": "ok"}
