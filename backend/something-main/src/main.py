"""Main FastAPI Application and Lifespan Orchestration."""

import logging
from contextlib import asynccontextmanager
from typing import Any

from fastapi import FastAPI, Request, status
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse

from src.config import settings
from src.database import init_db
from src.timeline.exceptions import (
    DuplicateEventError,
    EntityNotFoundError,
    NormalizationError,
    PipelineQueueFullError,
)
from src.timeline.pipeline import pipeline_instance
from src.timeline.router import router as timeline_router
from src.timeline.router import ws_manager, ws_router

# Configure logging
logging.basicConfig(
    level=logging.DEBUG if settings.DEBUG else logging.INFO,
    format="%(asctime)s [%(levelname)s] %(name)s: %(message)s",
)
logger = logging.getLogger(__name__)


@asynccontextmanager
async def lifespan(app: FastAPI):
    """Application lifecycle: Initialize DB, launch background pipeline worker, cleanup on shutdown."""
    logger.info("Initializing database tables...")
    await init_db()

    # Hook WebSocket manager into pipeline broadcast bus
    pipeline_instance.register_broadcast_listener(ws_manager.broadcast)

    logger.info("Starting background ingestion pipeline worker...")
    await pipeline_instance.start()

    yield

    logger.info("Shutting down background ingestion pipeline worker...")
    await pipeline_instance.stop()


# FastAPI app initialization following FASTAPI_BEST_PRACTICES.md
app_kwargs: dict[str, Any] = {
    "title": settings.APP_NAME,
    "version": settings.APP_VERSION,
    "description": (
        "Module #3 (Timeline & Integration Engineer) for NTRO Problem Statement 26150.\n\n"
        "Forensic analysis tool for timestamp normalization, chronological unified timeline "
        "construction, multi-camera sliding-window event correlation, and async pipeline integration."
    ),
    "lifespan": lifespan,
}

if settings.ENVIRONMENT not in {"local", "staging", "dev"}:
    app_kwargs["openapi_url"] = None

app = FastAPI(**app_kwargs)

# Allow CORS for Flutter Frontend (Module #6)
app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.CORS_ORIGINS,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


# Global Exception Handlers translating domain exceptions to HTTP semantics
@app.exception_handler(PipelineQueueFullError)
async def pipeline_queue_full_handler(request: Request, exc: PipelineQueueFullError):
    return JSONResponse(
        status_code=status.HTTP_429_TOO_MANY_REQUESTS,
        content={"error": "PipelineQueueFull", "detail": exc.message, "details": exc.details},
    )


@app.exception_handler(DuplicateEventError)
async def duplicate_event_handler(request: Request, exc: DuplicateEventError):
    return JSONResponse(
        status_code=status.HTTP_409_CONFLICT,
        content={"error": "DuplicateEvent", "detail": exc.message},
    )


@app.exception_handler(EntityNotFoundError)
async def entity_not_found_handler(request: Request, exc: EntityNotFoundError):
    return JSONResponse(
        status_code=status.HTTP_404_NOT_FOUND,
        content={"error": "EntityNotFound", "detail": exc.message},
    )


@app.exception_handler(NormalizationError)
async def normalization_error_handler(request: Request, exc: NormalizationError):
    return JSONResponse(
        status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
        content={"error": "NormalizationError", "detail": exc.message, "details": exc.details},
    )


# Mount Timeline & Integration Router
app.include_router(timeline_router)
app.include_router(ws_router)


@app.get("/health", tags=["Health"])
async def health_check() -> dict[str, Any]:
    """Health check endpoint for container and process probes."""
    return {
        "status": "healthy",
        "app": settings.APP_NAME,
        "version": settings.APP_VERSION,
        "environment": settings.ENVIRONMENT,
        "pipeline": pipeline_instance.get_status().model_dump(),
    }
