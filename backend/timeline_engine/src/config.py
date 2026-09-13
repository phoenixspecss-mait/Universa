"""Global and domain configuration using Pydantic Settings v2."""

from pydantic import Field
from pydantic_settings import BaseSettings, SettingsConfigDict


class AppSettings(BaseSettings):
    """Application-level configuration."""

    model_config = SettingsConfigDict(
        env_file=".env",
        env_file_encoding="utf-8",
        extra="ignore",
    )

    APP_NAME: str = "Forensic Timeline & Integration Engine"
    APP_VERSION: str = "1.0.0"
    ENVIRONMENT: str = "local"
    DEBUG: bool = False
    PORT: int = 8000
    HOST: str = "0.0.0.0"

    # Database
    DATABASE_URL: str = "sqlite+aiosqlite:///./forensic_timeline.db"

    # CORS Settings
    CORS_ORIGINS: list[str] = Field(
        default=[
            "http://localhost:3000",
            "http://localhost:8000",
            "http://localhost:8080",
            "http://127.0.0.1:3000",
            "http://127.0.0.1:8000",
            "http://127.0.0.1:8080",
        ],
        description="Allowed CORS origin domains for frontend integration",
    )

    # Pipeline Settings (Configurable buffers & backpressure thresholds)
    PIPELINE_QUEUE_MAX_SIZE: int = Field(
        default=2000,
        ge=10,
        le=100000,
        description="Maximum capacity of asynchronous ingestion queue before backpressure occurs",
    )
    PIPELINE_WORKER_BATCH_SIZE: int = Field(
        default=50,
        ge=1,
        le=1000,
        description="Batch size for draining ingestion queue to database",
    )
    PIPELINE_DRAIN_TIMEOUT_SECONDS: float = Field(
        default=5.0,
        ge=0.1,
        description="Timeout for draining pending queue records during graceful shutdown",
    )
    DEDUPLICATION_CACHE_SIZE: int = Field(
        default=10000,
        ge=100,
        description="Number of recent frame/event hash signatures to retain in memory for deduplication",
    )

    # Correlation Settings
    CORRELATION_WINDOW_SECONDS: float = Field(
        default=5.0,
        ge=0.1,
        le=3600.0,
        description="Default temporal window (+/- seconds) for cross-camera event correlation",
    )
    CORRELATION_BUFFER_MAX_SIZE: int = Field(
        default=5000,
        ge=100,
        description="Maximum in-memory sliding buffer size for active correlation matching",
    )
    ALLOWED_LATENESS_SECONDS: float = Field(
        default=10.0,
        ge=0.0,
        description="Temporal margin beyond correlation window to retain out-of-order late arriving events",
    )
    COSINE_SIMILARITY_THRESHOLD: float = Field(
        default=0.82,
        ge=0.0,
        le=1.0,
        description="Cosine similarity cutoff to declare an EMBEDDING_MATCH correlation",
    )

    # Normalization & Anomaly Detection Settings
    TIMELINE_GAP_THRESHOLD_SECONDS: float = Field(
        default=30.0,
        ge=1.0,
        description="Threshold of elapsed time between consecutive frames on same channel to flag TIMELINE_GAP_DETECTED",
    )
    TIME_REGRESSION_THRESHOLD_SECONDS: float = Field(
        default=1.0,
        ge=0.01,
        description="Threshold of backward timestamp jump while frame index increments to flag TIME_REGRESSION_DETECTED",
    )
    DEFAULT_FALLBACK_TIMEZONE: str = "UTC"


settings = AppSettings()
