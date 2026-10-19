"""FastAPI entrypoint: `uvicorn app.main:app`."""
import logging
from contextlib import asynccontextmanager

from fastapi import Depends, FastAPI

from . import db as dbmod
from . import auth
from .auth import require_token
from .config import get_settings
from .routes import capture, crud

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(name)s: %(message)s")


@asynccontextmanager
async def lifespan(app: FastAPI):
    # Tests pre-populate DB.db with a fake and skip connecting.
    if dbmod.DB.db is None:
        await dbmod.connect(get_settings())
    yield
    await dbmod.disconnect()


app = FastAPI(title="Spaces API", version="1.0.0", lifespan=lifespan)


@app.get("/health")
async def health():
    ok = True
    try:
        if dbmod.DB.client is not None:
            await dbmod.DB.client.admin.command("ping")
    except Exception:  # noqa: BLE001
        ok = False
    return {"status": "ok" if ok else "degraded", "db": ok, "atlas_search": dbmod.DB.atlas_search}


app.include_router(auth.router)
app.include_router(capture.router, dependencies=[Depends(require_token)])
app.include_router(crud.router, dependencies=[Depends(require_token)])
