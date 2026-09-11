import shutil
from pathlib import Path

import pytest
from fastapi.testclient import TestClient

from app.config import Settings, get_settings
from app.main import app

REPO_ROOT = Path(__file__).resolve().parent.parent
SOURCE_WORKBOOK = REPO_ROOT / "data" / "Personal_Finance_2026_V1.xlsx"
SOURCE_TEMPLATE = REPO_ROOT / "data" / "Personal_Finance_TEMPLATE.xlsx"
API_KEY = "test-key"


@pytest.fixture
def data_dir(tmp_path: Path) -> Path:
    d = tmp_path / "data"
    d.mkdir()
    shutil.copy(SOURCE_WORKBOOK, d / "Personal_Finance_2026_V1.xlsx")
    shutil.copy(SOURCE_TEMPLATE, d / "Personal_Finance_TEMPLATE.xlsx")
    return d


@pytest.fixture
def client(data_dir: Path):
    def override_settings() -> Settings:
        return Settings(
            api_key=API_KEY,
            storage_backend="local",
            local_data_dir=data_dir,
        )

    app.dependency_overrides[get_settings] = override_settings
    yield TestClient(app, headers={"X-API-Key": API_KEY})
    app.dependency_overrides.clear()
