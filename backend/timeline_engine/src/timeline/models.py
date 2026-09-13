"""SQLAlchemy 2.0 async ORM models for forensic timeline storage."""

try:
    from datetime import UTC, datetime
except ImportError:
    from datetime import datetime, timezone
    UTC = timezone.utc


from sqlalchemy import (
    BigInteger,
    DateTime,
    Float,
    ForeignKey,
    Index,
    Integer,
    String,
    Text,
)
from sqlalchemy.orm import Mapped, mapped_column, relationship

from src.database import Base


class CaseModel(Base):
    """Case investigation container."""

    __tablename__ = "case"

    id: Mapped[str] = mapped_column(String(64), primary_key=True)
    case_number: Mapped[str] = mapped_column(String(64), unique=True, index=True)
    title: Mapped[str] = mapped_column(String(255))
    description: Mapped[str | None] = mapped_column(Text, nullable=True)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=lambda: datetime.now(UTC)
    )

    cameras: Mapped[list["CameraModel"]] = relationship(
        "CameraModel", back_populates="case", cascade="all, delete-orphan"
    )


class CameraModel(Base):
    """Camera / channel configuration and clock state."""

    __tablename__ = "camera"

    id: Mapped[str] = mapped_column(String(64), primary_key=True)
    case_id: Mapped[str] = mapped_column(
        String(64), ForeignKey("case.id", ondelete="CASCADE"), index=True
    )
    channel_id: Mapped[str] = mapped_column(String(32), index=True)
    name: Mapped[str] = mapped_column(String(128))
    vendor_type: Mapped[str] = mapped_column(String(32))
    location_description: Mapped[str | None] = mapped_column(String(255), nullable=True)
    clock_offset_ms: Mapped[float] = mapped_column(Float, default=0.0)
    drift_rate_ppm: Mapped[float] = mapped_column(Float, default=0.0)
    timezone: Mapped[str] = mapped_column(String(64), default="UTC")
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=lambda: datetime.now(UTC)
    )

    case: Mapped["CaseModel"] = relationship("CaseModel", back_populates="cameras")


class TimelineEventModel(Base):
    """Normalized forensic event entry."""

    __tablename__ = "timeline_event"

    id: Mapped[str] = mapped_column(String(64), primary_key=True)
    case_id: Mapped[str] = mapped_column(String(64), index=True)
    evidence_id: Mapped[str] = mapped_column(String(64), index=True)
    channel_id: Mapped[str] = mapped_column(String(32), index=True)
    utc_timestamp: Mapped[datetime] = mapped_column(DateTime(timezone=True), index=True)
    raw_timestamp: Mapped[str] = mapped_column(String(128))
    timestamp_source: Mapped[str] = mapped_column(String(64))
    applied_offset_ms: Mapped[float] = mapped_column(Float, default=0.0)
    event_type: Mapped[str] = mapped_column(String(64), index=True)
    frame_index: Mapped[int | None] = mapped_column(Integer, nullable=True)
    file_offset_bytes: Mapped[int | None] = mapped_column(BigInteger, nullable=True)
    pts: Mapped[int | None] = mapped_column(BigInteger, nullable=True)
    dts: Mapped[int | None] = mapped_column(BigInteger, nullable=True)
    time_base_num: Mapped[int] = mapped_column(Integer, default=1)
    time_base_den: Mapped[int] = mapped_column(Integer, default=1000)
    payload_json: Mapped[str] = mapped_column(Text, default="{}")
    source_reference_json: Mapped[str] = mapped_column(Text, default="{}")
    anomaly_flags_json: Mapped[str] = mapped_column(Text, default="[]")
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=lambda: datetime.now(UTC)
    )

    __table_args__ = (
        Index("ix_timeline_event_case_time", "case_id", "utc_timestamp"),
        Index("ix_timeline_event_case_channel_time", "case_id", "channel_id", "utc_timestamp"),
        Index("ix_timeline_event_case_type", "case_id", "event_type"),
    )


class CorrelatedEventModel(Base):
    """Multi-camera correlated forensic event."""

    __tablename__ = "correlated_event"

    id: Mapped[str] = mapped_column(String(64), primary_key=True)
    correlation_id: Mapped[str] = mapped_column(String(64), unique=True, index=True)
    case_id: Mapped[str] = mapped_column(String(64), index=True)
    primary_channel: Mapped[str] = mapped_column(String(32), index=True)
    secondary_channels_json: Mapped[str] = mapped_column(Text, default="[]")
    source_event_ids_json: Mapped[str] = mapped_column(Text, default="[]")
    start_time_utc: Mapped[datetime] = mapped_column(DateTime(timezone=True), index=True)
    end_time_utc: Mapped[datetime] = mapped_column(DateTime(timezone=True))
    event_type: Mapped[str] = mapped_column(String(64))
    correlation_type: Mapped[str] = mapped_column(String(64), index=True)
    confidence: Mapped[float] = mapped_column(Float)
    explanation: Mapped[str] = mapped_column(Text)
    metadata_json: Mapped[str] = mapped_column(Text, default="{}")
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=lambda: datetime.now(UTC)
    )

    __table_args__ = (
        Index("ix_correlated_event_case_time", "case_id", "start_time_utc"),
        Index("ix_correlated_event_case_type", "case_id", "correlation_type"),
    )


class TimestampCorrectionModel(Base):
    """Audit record of clock offset or drift calibrations."""

    __tablename__ = "timestamp_correction"

    id: Mapped[str] = mapped_column(String(64), primary_key=True)
    case_id: Mapped[str] = mapped_column(String(64), index=True)
    channel_id: Mapped[str] = mapped_column(String(32), index=True)
    applied_offset_ms: Mapped[float] = mapped_column(Float)
    correction_method: Mapped[str] = mapped_column(String(32))
    drift_rate_ppm: Mapped[float] = mapped_column(Float, default=0.0)
    reference_timestamp: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), nullable=True
    )
    reason: Mapped[str] = mapped_column(String(255))
    source: Mapped[str] = mapped_column(String(255))
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=lambda: datetime.now(UTC)
    )
