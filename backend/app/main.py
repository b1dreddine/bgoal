import asyncio
import contextlib
import logging
from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.middleware.gzip import GZipMiddleware

from app.config import get_settings
from app.db import create_all
from app.routers import devices, images, matches, teams

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(name)s: %(message)s")


@asynccontextmanager
async def lifespan(app: FastAPI):
    await create_all()
    worker_task = None
    if get_settings().run_worker_in_api:
        from app.notifications.sender import build_sender
        from app.providers import get_provider
        from app.worker import Worker

        settings = get_settings()
        worker = Worker(get_provider(), build_sender(settings.firebase_credentials_file), settings)
        worker_task = asyncio.create_task(worker.run_forever())
        logging.getLogger(__name__).info("worker running inside the API (provider=%s)", settings.provider)
    yield
    if worker_task:
        worker_task.cancel()
        with contextlib.suppress(asyncio.CancelledError):
            await worker_task


app = FastAPI(title="BGoal API", version="1.0.0", lifespan=lifespan)
app.add_middleware(GZipMiddleware, minimum_size=1024)
app.add_middleware(
    CORSMiddleware,
    allow_origins=[o.strip() for o in get_settings().cors_origins.split(",")],
    allow_methods=["*"],
    allow_headers=["*"],
)
app.include_router(matches.router)
app.include_router(teams.router)
app.include_router(devices.router)
app.include_router(images.router)


@app.get("/health")
async def health():
    return {"ok": True, "provider": get_settings().provider}
