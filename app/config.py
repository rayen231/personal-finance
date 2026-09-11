from functools import lru_cache
from pathlib import Path

from pydantic import Field
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", env_prefix="FINANCE_", populate_by_name=True)

    api_key: str = "dev-local-key"
    storage_backend: str = "local"  # "local" or "vercel_blob"
    local_data_dir: Path = Path("data")
    template_filename: str = "Personal_Finance_TEMPLATE.xlsx"

    # Not FINANCE_-prefixed: this is the standard env var name Vercel's Blob
    # integration injects on its own.
    blob_read_write_token: str = Field(default="", validation_alias="BLOB_READ_WRITE_TOKEN")

    def workbook_filename(self, year: int) -> str:
        return f"Personal_Finance_{year}_V1.xlsx"


@lru_cache
def get_settings() -> Settings:
    return Settings()
