"""Pytest configuration and async client fixtures following FASTAPI_BEST_PRACTICES.md."""

from collections.abc import AsyncGenerator

import pytest
from httpx import ASGITransport, AsyncClient
from sqlalchemy.ext.asyncio import (
    AsyncSession,
    async_sessionmaker,
    create_async_engine,
)
from sqlalchemy.pool import StaticPool

from src.database import Base, enable_sqlite_pragmas, get_db
from src.main import app
from src.timeline.dependencies import pipeline_instance
from src.timeline.pipeline import set_default_pipeline_session_factory

# Isolated in-memory SQLite database for testing (StaticPool ensures connection sharing)
TEST_DATABASE_URL = "sqlite+aiosqlite:///:memory:"
test_engine = create_async_engine(
    TEST_DATABASE_URL,
    echo=False,
    connect_args={"check_same_thread": False},
    poolclass=StaticPool,
)
enable_sqlite_pragmas(test_engine)

TestSessionFactory = async_sessionmaker(
    bind=test_engine, class_=AsyncSession, expire_on_commit=False
)
set_default_pipeline_session_factory(TestSessionFactory)
pipeline_instance.set_session_factory(TestSessionFactory)


async def override_get_db() -> AsyncGenerator[AsyncSession, None]:
    """Dependency override providing test database session."""
    async with TestSessionFactory() as session:
        yield session
        await session.commit()


@pytest.fixture(scope="session", autouse=True)
async def setup_test_database():
    """Create all tables in test database and isolate pipeline."""
    pipeline_instance.set_session_factory(TestSessionFactory)
    set_default_pipeline_session_factory(TestSessionFactory)
    async with test_engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)
    yield
    async with test_engine.begin() as conn:
        await conn.run_sync(Base.metadata.drop_all)


@pytest.fixture
async def db_session() -> AsyncGenerator[AsyncSession, None]:
    """Provide clean database session for direct service testing."""
    async with TestSessionFactory() as session:
        yield session
        await session.rollback()


@pytest.fixture
async def client() -> AsyncGenerator[AsyncClient, None]:
    """Async HTTP client using ASGITransport as recommended in FASTAPI_BEST_PRACTICES.md."""
    app.dependency_overrides[get_db] = override_get_db
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://testserver") as ac:
        yield ac
    app.dependency_overrides.clear()
