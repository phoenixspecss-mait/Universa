"""Domain-specific exceptions for Module #3.

Decoupled from HTTP semantics to preserve domain isolation.
"""


class TimelineError(Exception):
    """Base exception for all timeline domain operations."""

    def __init__(self, message: str, details: dict | None = None) -> None:
        super().__init__(message)
        self.message = message
        self.details = details or {}


class NormalizationError(TimelineError):
    """Raised when a raw timestamp cannot be normalized."""


class PipelineQueueFullError(TimelineError):
    """Raised when the asynchronous ingestion queue reaches capacity."""

    def __init__(self, queue_size: int, max_size: int) -> None:
        super().__init__(
            f"Pipeline ingestion queue capacity reached: {queue_size}/{max_size}",
            details={"queue_size": queue_size, "max_size": max_size},
        )


class PipelineBackpressureError(TimelineError):
    """Raised when pipeline backpressure rejects new ingestion requests."""


class DuplicateEventError(TimelineError):
    """Raised when an ingested frame/event matches an already processed identifier."""


class EntityNotFoundError(TimelineError):
    """Raised when a requested case, event, or camera cannot be found."""
