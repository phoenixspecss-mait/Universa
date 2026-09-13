"""Pydantic v2 domain schemas for forensic timeline operations."""

from datetime import UTC, datetime
from typing import Any
from uuid import uuid4

from pydantic import BaseModel, ConfigDict, Field, field_serializer

from src.timeline.constants import (
    CorrectionMethod,
    CorrelationType,
    EventType,
    TimestampFormat,
    TimestampSource,
    VendorType,
)


class BoundingBox(BaseModel):
    """Bounding box coordinates normalized between 0.0 and 1.0 or pixel coordinates."""

    model_config = ConfigDict(populate_by_name=True)

    xmin: float = Field(..., description="Top-left X coordinate")
    ymin: float = Field(..., description="Top-left Y coordinate")
    xmax: float = Field(..., description="Bottom-right X coordinate")
    ymax: float = Field(..., description="Bottom-right Y coordinate")


class RawFrameMeta(BaseModel):
    """Metadata received from Core Engine / Codec Parser upstream."""

    model_config = ConfigDict(populate_by_name=True)

    case_id: str = Field(..., min_length=1, description="Unique case identifier")
    evidence_id: str = Field(..., min_length=1, description="Unique evidence file/drive identifier")
    channel_id: str = Field(..., min_length=1, description="Camera/channel identifier, e.g. CAM01")
    vendor_type: VendorType = Field(default=VendorType.GENERIC, description="Detected DVR vendor")
    raw_timestamp_str: str = Field(
        ..., min_length=1, description="Exact raw timestamp string from device"
    )
    timestamp_format: TimestampFormat = Field(
        default=TimestampFormat.AUTO, description="Hint or known format of raw timestamp"
    )
    timestamp_source: TimestampSource = Field(
        default=TimestampSource.UNKNOWN,
        description="Source of timestamp (embedded bitstream vs filesystem/FAT direntry)",
    )
    timezone: str | None = Field(
        default=None, description="Timezone name or offset, e.g. Asia/Kolkata or +05:30"
    )
    frame_index: int = Field(
        ..., ge=0, description="Sequential index of the frame within the segment"
    )
    file_offset_bytes: int | None = Field(
        default=None, ge=0, description="Byte offset in source evidence"
    )
    pts: int | None = Field(default=None, description="Presentation Timestamp (ticks)")
    dts: int | None = Field(default=None, description="Decode Timestamp (ticks)")
    time_base_num: int = Field(
        default=1, ge=1, description="Numerator of media time base (e.g. 1 in 1/15360)"
    )
    time_base_den: int = Field(
        default=1000, ge=1, description="Denominator of media time base (e.g. 15360 in 1/15360)"
    )
    file_path: str | None = Field(default=None, description="Physical path or evidence image URI")
    frame_hash_sha256: str | None = Field(default=None, description="SHA-256 of raw frame buffer")


class NormalizedFrameMeta(BaseModel):
    """Forensically normalized timeline frame metadata."""

    model_config = ConfigDict(populate_by_name=True, from_attributes=True)

    case_id: str
    evidence_id: str
    channel_id: str
    utc_timestamp: datetime = Field(..., description="Standardized UTC timestamp")
    raw_timestamp: str = Field(..., description="Unmodified original raw timestamp")
    timestamp_source: TimestampSource
    applied_offset_ms: float = Field(
        default=0.0, description="Applied clock offset in milliseconds"
    )
    frame_index: int
    file_offset_bytes: int | None = None
    pts: int | None = None
    dts: int | None = None
    time_base_num: int = Field(default=1, ge=1)
    time_base_den: int = Field(default=1000, ge=1)
    anomaly_flags: list[str] = Field(default_factory=list)

    @field_serializer("utc_timestamp", when_used="json")
    def serialize_utc_timestamp(self, dt: datetime) -> str:
        if dt.tzinfo is None:
            dt = dt.replace(tzinfo=UTC)
        return dt.isoformat()


class AIDetectionPayload(BaseModel):
    """Input payload emitted by Module #4 (AI/ML Engine)."""

    model_config = ConfigDict(populate_by_name=True)

    case_id: str
    evidence_id: str
    channel_id: str
    utc_timestamp: datetime | None = None
    raw_timestamp_str: str | None = None
    frame_index: int = Field(..., ge=0)
    object_class: str = Field(
        ..., min_length=1, description="Detected object class (e.g. person, car)"
    )
    confidence: float = Field(..., ge=0.0, le=1.0, description="Detection confidence score")
    bounding_box: BoundingBox | None = None
    track_id: str | int | None = Field(
        default=None,
        description="Local tracking identifier assigned by single-camera tracker",
    )
    is_global_track_id: bool = Field(
        default=False,
        description="Must be explicitly True if tracking has established cross-camera global identity",
    )
    embedding: list[float] | None = Field(
        default=None,
        description="Optional visual feature vector (e.g. 128-d or 512-d ReID embedding)",
    )
    detection_metadata: dict[str, Any] = Field(default_factory=dict)

    @field_serializer("utc_timestamp", when_used="json")
    def serialize_utc_timestamp(self, dt: datetime | None) -> str | None:
        if dt is None:
            return None
        if dt.tzinfo is None:
            dt = dt.replace(tzinfo=UTC)
        return dt.isoformat()


class TimelineEvent(BaseModel):
    """Canonical chronological event entity stored in forensic timeline."""

    model_config = ConfigDict(populate_by_name=True, from_attributes=True)

    event_id: str = Field(default_factory=lambda: str(uuid4()))
    case_id: str
    evidence_id: str
    channel_id: str
    utc_timestamp: datetime
    raw_timestamp: str
    timestamp_source: TimestampSource = TimestampSource.UNKNOWN
    applied_offset_ms: float = 0.0
    event_type: EventType
    frame_index: int | None = None
    file_offset_bytes: int | None = None
    pts: int | None = None
    dts: int | None = None
    time_base_num: int = Field(default=1, ge=1)
    time_base_den: int = Field(default=1000, ge=1)
    payload: dict[str, Any] = Field(default_factory=dict)
    source_reference: dict[str, Any] = Field(default_factory=dict)
    anomaly_flags: list[str] = Field(default_factory=list)

    @field_serializer("utc_timestamp", when_used="json")
    def serialize_utc_timestamp(self, dt: datetime) -> str:
        if dt.tzinfo is None:
            dt = dt.replace(tzinfo=UTC)
        return dt.isoformat()


class CorrelatedEvent(BaseModel):
    """Forensic correlation across one or more camera streams."""

    model_config = ConfigDict(populate_by_name=True, from_attributes=True)

    correlation_id: str = Field(default_factory=lambda: str(uuid4()))
    case_id: str
    primary_channel: str
    secondary_channels: list[str] = Field(default_factory=list)
    source_event_ids: list[str] = Field(default_factory=list)
    start_time_utc: datetime
    end_time_utc: datetime
    event_type: str
    correlation_type: CorrelationType
    confidence: float = Field(..., ge=0.0, le=1.0)
    explanation: str
    metadata: dict[str, Any] = Field(default_factory=dict)

    @field_serializer("start_time_utc", "end_time_utc", when_used="json")
    def serialize_times(self, dt: datetime) -> str:
        if dt.tzinfo is None:
            dt = dt.replace(tzinfo=UTC)
        return dt.isoformat()


class TimestampCorrection(BaseModel):
    """Forensic audit record of clock offset or drift applied to a channel."""

    model_config = ConfigDict(populate_by_name=True, from_attributes=True)

    id: str = Field(default_factory=lambda: str(uuid4()))
    case_id: str
    channel_id: str
    applied_offset_ms: float
    correction_method: CorrectionMethod = CorrectionMethod.FIXED_OFFSET
    drift_rate_ppm: float = 0.0
    reference_timestamp: datetime | None = None
    reason: str
    source: str
    created_at: datetime = Field(default_factory=lambda: datetime.now(UTC))

    @field_serializer("reference_timestamp", "created_at", when_used="json")
    def serialize_times(self, dt: datetime | None) -> str | None:
        if dt is None:
            return None
        if dt.tzinfo is None:
            dt = dt.replace(tzinfo=UTC)
        return dt.isoformat()


class NormalizationRequest(BaseModel):
    """Request payload for standalone timestamp normalization."""

    raw_timestamp_str: str
    timestamp_format: TimestampFormat = TimestampFormat.AUTO
    timestamp_source: TimestampSource = TimestampSource.UNKNOWN
    timezone: str | None = None
    channel_offset_ms: float = 0.0
    drift_rate_ppm: float = 0.0
    pts: int | None = None
    time_base_num: int = Field(default=1, ge=1)
    time_base_den: int = Field(default=1000, ge=1)


class NormalizationResponse(BaseModel):
    """Result of timestamp normalization."""

    model_config = ConfigDict(populate_by_name=True)

    success: bool
    raw_timestamp: str
    utc_timestamp: datetime | None = None
    applied_offset_ms: float = 0.0
    timestamp_source: TimestampSource
    detected_format: str
    anomaly_flags: list[str] = Field(default_factory=list)
    errors: list[str] = Field(default_factory=list)

    @field_serializer("utc_timestamp", when_used="json")
    def serialize_utc_timestamp(self, dt: datetime | None) -> str | None:
        if dt is None:
            return None
        if dt.tzinfo is None:
            dt = dt.replace(tzinfo=UTC)
        return dt.isoformat()


class CorrelationRequest(BaseModel):
    """Request payload to trigger cross-camera correlation."""

    case_id: str
    window_seconds: float | None = Field(default=None, ge=0.1, le=3600.0)
    channel_ids: list[str] | None = None
    start_time: datetime | None = None
    end_time: datetime | None = None


class CorrelationResponse(BaseModel):
    """Response containing correlated cross-camera events."""

    case_id: str
    correlated_count: int
    correlations: list[CorrelatedEvent]


class TimelineQuery(BaseModel):
    """Query parameters for timeline filtering."""

    model_config = ConfigDict(populate_by_name=True)

    case_id: str
    channel_id: str | None = None
    event_types: list[EventType] | None = None
    start_time: datetime | None = None
    end_time: datetime | None = None
    limit: int = Field(default=100, ge=1, le=1000)
    offset: int = Field(default=0, ge=0)


class TimelineResponse(BaseModel):
    """Standardized response for timeline query operations."""

    case_id: str
    total_events: int
    limit: int
    offset: int
    events: list[TimelineEvent]


class TimelineExportResponse(BaseModel):
    """Forensic export package for reporting and court presentation."""

    case_id: str
    export_generated_at_utc: datetime = Field(default_factory=lambda: datetime.now(UTC))
    forensic_tool: str = "NTRO PS-26150 Multi-Vendor DVR/NVR Forensic Tool (Module #3)"
    total_events: int
    total_correlations: int
    total_corrections: int
    events: list[TimelineEvent]
    correlations: list[CorrelatedEvent]
    timestamp_corrections: list[TimestampCorrection]
    integrity_statement: str = (
        "All normalized timestamps are mathematically derived without mutating original "
        "evidence bitstreams. Raw timestamps, byte offsets, and source hashes are preserved "
        "in full for forensic chain-of-custody verification."
    )

    @field_serializer("export_generated_at_utc", when_used="json")
    def serialize_export_time(self, dt: datetime) -> str:
        return dt.isoformat()


class PipelineStatus(BaseModel):
    """Metrics reporting asynchronous ingestion pipeline status."""

    queue_size: int
    queue_max_size: int
    is_healthy: bool
    processed_events_count: int
    dropped_events_count: int
    detected_anomalies_count: int


class SemanticSearchRequest(BaseModel):
    """Query payload for multi-camera semantic search."""

    query: str = Field(..., min_length=1, description="Natural language search query")
    case_id: str | None = Field(default=None, description="Optional case identifier filter")
    top_k: int = Field(default=10, ge=1, le=100, description="Maximum number of matches")


class SemanticSearchResult(BaseModel):
    """Search result matching Flutter SearchResultModel."""

    id: str
    cameraName: str
    timestamp: str
    confidence: float
    objectType: str
    description: str
    boundingBox: BoundingBox
    similarity: float = 1.0

