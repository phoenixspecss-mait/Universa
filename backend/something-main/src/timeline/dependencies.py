"""Dependency injection providers for FastAPI route handlers."""

from typing import Annotated

from fastapi import Depends
from sqlalchemy.ext.asyncio import AsyncSession

from src.database import get_db
from src.timeline.pipeline import PipelineOrchestrator, pipeline_instance
from src.timeline.service import TimelineService


async def get_timeline_service(
    session: Annotated[AsyncSession, Depends(get_db)],
) -> TimelineService:
    """Provide request-scoped TimelineService."""
    return TimelineService(session)


def get_pipeline() -> PipelineOrchestrator:
    """Provide singleton PipelineOrchestrator."""
    return pipeline_instance


# Modern Annotated dependency aliases
TimelineServiceDep = Annotated[TimelineService, Depends(get_timeline_service)]
PipelineDep = Annotated[PipelineOrchestrator, Depends(get_pipeline)]
