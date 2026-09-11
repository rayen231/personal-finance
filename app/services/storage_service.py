from abc import ABC, abstractmethod
from pathlib import Path

import httpx

from app.config import Settings, get_settings

BLOB_API_BASE = "https://blob.vercel-storage.com"
BLOB_API_VERSION = "12"
XLSX_CONTENT_TYPE = "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"


def _store_id_from_token(token: str) -> str:
    # Read-write tokens are shaped "vercel_blob_rw_<storeId>_<secret>".
    parts = token.split("_")
    if len(parts) < 4:
        raise ValueError("BLOB_READ_WRITE_TOKEN doesn't look like a valid Vercel Blob token.")
    return parts[3]


class WorkbookNotFoundError(Exception):
    pass


class StorageService(ABC):
    """Downloads/uploads a named workbook file as raw bytes.

    Callers never see whether the backing store is local disk or Vercel Blob.
    """

    @abstractmethod
    def exists(self, filename: str) -> bool: ...

    @abstractmethod
    def download(self, filename: str) -> bytes: ...

    @abstractmethod
    def upload(self, filename: str, content: bytes) -> None: ...


class LocalFileStorage(StorageService):
    def __init__(self, base_dir: Path):
        self.base_dir = base_dir
        self.base_dir.mkdir(parents=True, exist_ok=True)

    def _path(self, filename: str) -> Path:
        return self.base_dir / filename

    def exists(self, filename: str) -> bool:
        return self._path(filename).exists()

    def download(self, filename: str) -> bytes:
        path = self._path(filename)
        if not path.exists():
            raise WorkbookNotFoundError(filename)
        return path.read_bytes()

    def upload(self, filename: str, content: bytes) -> None:
        path = self._path(filename)
        tmp_path = path.with_suffix(path.suffix + ".tmp")
        tmp_path.write_bytes(content)
        tmp_path.replace(path)


class VercelBlobStorage(StorageService):
    """Stores each workbook as a fixed-pathname *private* blob (no random
    suffix, so the same filename always overwrites the same blob instead of
    piling up new URLs each time)."""

    def __init__(self, token: str):
        if not token:
            raise ValueError("BLOB_READ_WRITE_TOKEN is not set.")
        self._token = token
        self._store_id = _store_id_from_token(token)

    def _auth_headers(self, **extra: str) -> dict:
        return {
            "Authorization": f"Bearer {self._token}",
            "x-api-version": BLOB_API_VERSION,
            **extra,
        }

    def _blob_url(self, filename: str) -> str:
        return f"https://{self._store_id}.private.blob.vercel-storage.com/{filename}"

    def exists(self, filename: str) -> bool:
        # cache=0 bypasses Vercel's CDN cache: a blob just overwritten can
        # otherwise read back stale for up to ~60s, which would corrupt
        # read-modify-write operations on the workbook.
        resp = httpx.head(
            self._blob_url(filename), params={"cache": "0"}, headers=self._auth_headers(), timeout=30
        )
        if resp.status_code == 404:
            return False
        resp.raise_for_status()
        return True

    def download(self, filename: str) -> bytes:
        resp = httpx.get(
            self._blob_url(filename), params={"cache": "0"}, headers=self._auth_headers(), timeout=60
        )
        if resp.status_code == 404:
            raise WorkbookNotFoundError(filename)
        resp.raise_for_status()
        return resp.content

    def upload(self, filename: str, content: bytes) -> None:
        resp = httpx.put(
            f"{BLOB_API_BASE}/",
            params={"pathname": filename},
            content=content,
            headers=self._auth_headers(**{
                "x-content-type": XLSX_CONTENT_TYPE,
                "x-add-random-suffix": "0",
                "x-allow-overwrite": "1",
                "x-vercel-blob-access": "private",
            }),
            timeout=60,
        )
        resp.raise_for_status()


def get_storage_service(settings: Settings | None = None) -> StorageService:
    settings = settings or get_settings()
    if settings.storage_backend == "local":
        return LocalFileStorage(settings.local_data_dir)
    if settings.storage_backend == "vercel_blob":
        return VercelBlobStorage(settings.blob_read_write_token)
    raise NotImplementedError(
        f"Storage backend '{settings.storage_backend}' is not implemented yet."
    )
