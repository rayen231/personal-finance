"""Vercel serverless entry point. Wraps the FastAPI ASGI app for Mangum.

Not used for local dev (run `uvicorn app.main:app` instead) - this only
matters once actually deploying to Vercel, at which point storage_backend
must also be switched to vercel_blob (local disk isn't available there).
"""

from mangum import Mangum

from app.main import app

handler = Mangum(app)
