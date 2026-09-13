"""Async database engine and session management using SQLAlchemy 2.0."""

from collections.abc import AsyncGenerator

from sqlalchemy import MetaData, event
from sqlalchemy.ext.asyncio import (
    AsyncAttrs,
    AsyncEngine,
    AsyncSession,
    async_sessionmaker,
    create_async_engine,
)
from sqlalchemy.orm import DeclarativeBase

from src.config import settings

# Explicit Postgres/SQLite standard index naming convention
CONVENTION = {
    "ix": "%(column_0_label)s_idx",
    "uq": "%(table_name)s_%(column_0_name)s_key",
    "ck": "%(table_name)s_%(constraint_name)s_check",
    "fk": "%(table_name)s_%(column_0_name)s_fkey",
    "pk": "%(table_name)s_pkey",
}

metadata = MetaData(naming_convention=CONVENTION)


class Base(AsyncAttrs, DeclarativeBase):
    """Base model for all SQLAlchemy entities."""

    metadata = metadata


def enable_sqlite_pragmas(target_engine: AsyncEngine) -> None:
    """Configure SQLite connection with foreign keys and WAL journal mode."""

    def on_connect(dbapi_connection, connection_record):
        cursor = dbapi_connection.cursor()
        cursor.execute("PRAGMA foreign_keys=ON;")
        cursor.execute("PRAGMA journal_mode=WAL;")
        cursor.close()

    event.listen(target_engine.sync_engine, "connect", on_connect)


# Create async engine
engine = create_async_engine(
    settings.DATABASE_URL,
    echo=settings.DEBUG,
    future=True,
)
if "sqlite" in settings.DATABASE_URL:
    enable_sqlite_pragmas(engine)

SessionFactory = async_sessionmaker(
    bind=engine,
    class_=AsyncSession,
    expire_on_commit=False,
    autocommit=False,
    autoflush=False,
)


async def get_db() -> AsyncGenerator[AsyncSession, None]:
    """Dependency for providing request-scoped async database sessions."""
    async with SessionFactory() as session:
        try:
            yield session
            await session.commit()
        except Exception:
            await session.rollback()
            raise


async def init_db() -> None:
    """Initialize database tables."""
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)
