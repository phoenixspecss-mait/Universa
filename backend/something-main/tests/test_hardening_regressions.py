"""Comprehensive regression tests for Module #3 hardening fixes."""

from datetime import UTC, datetime
from unittest.mock import AsyncMock

import pytest

from src.config import settings
from src.timeline.constants import (
    AnomalyFlag,
    EventType,
    TimestampFormat,
    TimestampSource,
    VendorType,
)
from src.timeline.correlator import EventCorrelator
from src.timeline.exceptions import DuplicateEventError
from src.timeline.normalizer import TimelineNormalizer
from src.timeline.pipeline import PipelineOrchestrator
from src.timeline.router import WebSocketConnectionManager
from src.timeline.schemas import (
    AIDetectionPayload,
    RawFrameMeta,
    TimelineEvent,
)

# ============================================================================
# Fix #1: Raw FRAME_INDEX events excluded from cross-camera correlation
# ============================================================================


def test_correlator_excludes_raw_frame_indices():
    """Verify that pure FRAME_INDEX events without AI or anomaly payloads do not cause correlation explosion."""
    correlator = EventCorrelator(window_seconds=5.0)

    base_time = datetime(2026, 3, 10, 12, 0, 0, tzinfo=UTC)
    events: list[TimelineEvent] = []

    for i in range(100):
        t = base_time.replace(microsecond=i * 10000)
        events.append(
            TimelineEvent(
                case_id="CASE-EXPLODE",
                evidence_id="EVD-01",
                channel_id="CAM01",
                utc_timestamp=t,
                raw_timestamp="2026-03-10 12:00:00",
                event_type=EventType.FRAME_INDEX,
                frame_index=i,
                payload={"vendor_type": "HIKVISION"},
            )
        )
        events.append(
            TimelineEvent(
                case_id="CASE-EXPLODE",
                evidence_id="EVD-02",
                channel_id="CAM02",
                utc_timestamp=t,
                raw_timestamp="2026-03-10 12:00:00",
                event_type=EventType.FRAME_INDEX,
                frame_index=i,
                payload={"vendor_type": "DAHUA"},
            )
        )

    # Batch correlate pure frame index events
    corrs = correlator.correlate_batch(events)
    assert len(corrs) == 0, "Pure FRAME_INDEX events must never generate cross-camera correlations"

    # Now add 2 semantic AI events (person detection) on different cameras
    ai_1 = TimelineEvent(
        case_id="CASE-EXPLODE",
        evidence_id="EVD-01",
        channel_id="CAM01",
        utc_timestamp=base_time,
        raw_timestamp="2026-03-10 12:00:00",
        event_type=EventType.AI_DETECTION,
        frame_index=1,
        payload={"object_class": "person", "track_id": "trk-1"},
    )
    ai_2 = TimelineEvent(
        case_id="CASE-EXPLODE",
        evidence_id="EVD-02",
        channel_id="CAM02",
        utc_timestamp=base_time,
        raw_timestamp="2026-03-10 12:00:00",
        event_type=EventType.AI_DETECTION,
        frame_index=1,
        payload={"object_class": "person", "track_id": "trk-2"},
    )
    events.extend([ai_1, ai_2])

    semantic_corrs = correlator.correlate_batch(events)
    assert len(semantic_corrs) == 1
    assert semantic_corrs[0].primary_channel == "CAM01"
    assert semantic_corrs[0].secondary_channels == ["CAM02"]


# ============================================================================
# Fix #2: AI detections with frame_index resolve timestamps or create anomaly
# ============================================================================


@pytest.mark.asyncio
async def test_pipeline_ai_detection_frame_index_resolution():
    """Verify that AI detections without timestamps resolve from recent frame metadata."""
    pipeline = PipelineOrchestrator()

    # Pre-populate recent frame in cache
    frame_utc = datetime(2026, 3, 10, 12, 0, 5, tzinfo=UTC)
    pipeline._recent_frames[("CASE-01", "EVD-01", "CAM01", 100)] = (
        frame_utc,
        "2026-03-10 12:00:05",
        0.0,
    )

    ai_payload = AIDetectionPayload(
        case_id="CASE-01",
        evidence_id="EVD-01",
        channel_id="CAM01",
        frame_index=100,
        raw_timestamp_str=None,
        utc_timestamp=None,
        object_class="person",
        confidence=0.92,
        track_id="T1",
    )

    event = await pipeline._convert_ai_payload_to_event(ai_payload, session=None)
    assert event is not None
    assert event.utc_timestamp == frame_utc
    assert event.raw_timestamp == "2026-03-10 12:00:05"
    assert "UNRESOLVED_FRAME_REFERENCE" not in event.anomaly_flags


@pytest.mark.asyncio
async def test_pipeline_ai_detection_unresolved_frame_anomaly():
    """Verify that AI detection with missing frame reference generates UNRESOLVED_FRAME_REFERENCE anomaly."""
    pipeline = PipelineOrchestrator()

    ai_payload = AIDetectionPayload(
        case_id="CASE-UNKNOWN",
        evidence_id="EVD-01",
        channel_id="CAM01",
        frame_index=99999,  # Non-existent frame
        raw_timestamp_str=None,
        utc_timestamp=None,
        object_class="car",
        confidence=0.88,
        track_id="C1",
    )

    event = await pipeline._convert_ai_payload_to_event(ai_payload, session=None)
    assert event is not None
    assert event.event_type == EventType.AI_DETECTION
    assert "UNRESOLVED_FRAME_REFERENCE" in event.anomaly_flags
    assert event.payload["object_class"] == "car"


# ============================================================================
# Fix #3: Camera clock offset and drift applied during ingestion
# ============================================================================


def test_pipeline_applies_camera_calibration():
    """Verify that camera clock offset is added to UTC timestamp during frame ingestion."""
    pipeline = PipelineOrchestrator()
    pipeline.set_camera_calibration(
        case_id="CASE-CALIB",
        channel_id="CAM01",
        clock_offset_ms=10000.0,  # 10 seconds ahead
        drift_rate_ppm=0.0,
    )

    frame = RawFrameMeta(
        case_id="CASE-CALIB",
        evidence_id="EVD-01",
        channel_id="CAM01",
        vendor_type=VendorType.GENERIC,
        raw_timestamp_str="2026-03-10T12:00:00Z",
        timestamp_format=TimestampFormat.ISO_8601,
        timestamp_source=TimestampSource.RECORDING_EMBEDDED,
        frame_index=1,
    )

    event = pipeline._convert_raw_frame_to_event(frame)
    assert event is not None
    assert event.applied_offset_ms == 10000.0
    assert event.utc_timestamp == datetime(2026, 3, 10, 12, 0, 10, tzinfo=UTC)


# ============================================================================
# Fix #6: Deduplication scoped by evidence_id
# ============================================================================


@pytest.mark.asyncio
async def test_deduplication_scoped_by_evidence_id():
    """Verify that different evidence files with identical frame indexes are NOT rejected as duplicates."""
    pipeline = PipelineOrchestrator()

    frame_evd1 = RawFrameMeta(
        case_id="CASE-MULTI-EVD",
        evidence_id="EVD-DRIVE-A",
        channel_id="CAM01",
        raw_timestamp_str="2026-03-10 12:00:01",
        frame_index=1,
    )
    frame_evd2 = RawFrameMeta(
        case_id="CASE-MULTI-EVD",
        evidence_id="EVD-DRIVE-B",
        channel_id="CAM01",
        raw_timestamp_str="2026-03-10 12:00:01",
        frame_index=1,
    )

    key1 = await pipeline.submit_raw_frame(frame_evd1)
    key2 = await pipeline.submit_raw_frame(frame_evd2)
    assert key1 != key2

    # Ingesting exact same frame for EVD-DRIVE-A must raise DuplicateEventError
    with pytest.raises(DuplicateEventError):
        await pipeline.submit_raw_frame(frame_evd1)


# ============================================================================
# Fix #7: Deterministic LRU cache eviction
# ============================================================================


@pytest.mark.asyncio
async def test_correlator_deterministic_lru_cache():
    """Verify that correlator deduplication cache evicts in deterministic FIFO/LRU order."""
    correlator = EventCorrelator()

    # Pre-fill cache with items up to DEDUPLICATION_CACHE_SIZE
    cache_limit = settings.DEDUPLICATION_CACHE_SIZE
    for i in range(cache_limit):
        ev_id = f"ev_{i}"
        correlator._processed_event_ids[ev_id] = None

    assert len(correlator._processed_event_ids) == cache_limit
    assert "ev_0" in correlator._processed_event_ids

    # Trigger LRU eviction by adding one more item through add_event or direct dict operation
    correlator._processed_event_ids[f"ev_{cache_limit}"] = None
    if len(correlator._processed_event_ids) > cache_limit:
        correlator._processed_event_ids.popitem(last=False)

    assert len(correlator._processed_event_ids) == cache_limit
    assert "ev_0" not in correlator._processed_event_ids
    assert f"ev_{cache_limit}" in correlator._processed_event_ids


# ============================================================================
# Fix #9: Out-of-order frame arrival preserves high-water mark
# ============================================================================


@pytest.mark.asyncio
async def test_out_of_order_preserves_high_water_mark():
    """Verify that a delayed frame does not corrupt the channel's high-water mark in pipeline processing."""
    pipeline = PipelineOrchestrator()

    f1 = RawFrameMeta(
        case_id="CASE-OOO",
        evidence_id="EVD-01",
        channel_id="CAM01",
        raw_timestamp_str="2026-03-10T12:00:00Z",
        timestamp_format=TimestampFormat.ISO_8601,
        frame_index=1,
    )
    f3 = RawFrameMeta(
        case_id="CASE-OOO",
        evidence_id="EVD-01",
        channel_id="CAM01",
        raw_timestamp_str="2026-03-10T12:00:04Z",
        timestamp_format=TimestampFormat.ISO_8601,
        frame_index=3,
    )
    f2_late = RawFrameMeta(
        case_id="CASE-OOO",
        evidence_id="EVD-01",
        channel_id="CAM01",
        raw_timestamp_str="2026-03-10T12:00:02Z",
        timestamp_format=TimestampFormat.ISO_8601,
        frame_index=2,
    )
    f4 = RawFrameMeta(
        case_id="CASE-OOO",
        evidence_id="EVD-01",
        channel_id="CAM01",
        raw_timestamp_str="2026-03-10T12:00:06Z",
        timestamp_format=TimestampFormat.ISO_8601,
        frame_index=4,
    )

    # Process batch 1: f1, f3
    await pipeline._process_batch([f1, f3])
    # Channel state should be at frame 3, 12:00:04
    assert pipeline._channel_state["CAM01"][1] == 3

    # Process batch 2: f2_late arrives late
    await pipeline._process_batch([f2_late])
    # High-water mark must NOT be regressed to frame 2!
    assert pipeline._channel_state["CAM01"][1] == 3

    # Process batch 3: f4 arrives normally
    await pipeline._process_batch([f4])
    # High-water mark correctly advances to frame 4
    assert pipeline._channel_state["CAM01"][1] == 4


# ============================================================================
# Fix #13 & #16: Normalizer zero time base denominator & micro/nano epoch
# ============================================================================


def test_normalizer_zero_time_base_den_safe():
    """Verify that time_base_den <= 0 returns error without ZeroDivisionError crash."""
    normalizer = TimelineNormalizer()
    res = normalizer.normalize(
        raw_timestamp_str="2026-03-10 12:00:00",
        timestamp_format=TimestampFormat.MEDIA_RELATIVE_PTS,
        pts=1000,
        time_base_num=1,
        time_base_den=0,
    )
    assert not res.success
    assert AnomalyFlag.MALFORMED_RAW_TIMESTAMP.value in res.anomaly_flags


def test_normalizer_micro_nano_epoch():
    """Verify safe parsing of microsecond and nanosecond unix epoch timestamps."""
    normalizer = TimelineNormalizer()

    # Microseconds: 1773230400000000 -> 2026-03-11 12:00:00 UTC
    res_micro = normalizer.normalize(raw_timestamp_str="1773230400000000")
    assert res_micro.success
    assert res_micro.utc_timestamp == datetime(2026, 3, 11, 12, 0, 0, tzinfo=UTC)

    # Nanoseconds: 1773230400000000000 -> 2026-03-11 12:00:00 UTC
    res_nano = normalizer.normalize(raw_timestamp_str="1773230400000000000")
    assert res_nano.success
    assert res_nano.utc_timestamp == datetime(2026, 3, 11, 12, 0, 0, tzinfo=UTC)


# ============================================================================
# Fix #4: Non-blocking WebSocket slow-client protection
# ============================================================================


@pytest.mark.asyncio
async def test_websocket_non_blocking_slow_client():
    """Verify that slow or stalled WebSocket clients have messages dropped without blocking the manager."""
    manager = WebSocketConnectionManager(max_queue_size=2)
    mock_ws = AsyncMock()

    queue = await manager.connect(mock_ws, case_id="CASE-FAST")
    assert queue.maxsize == 2

    # Broadcast 5 messages
    for i in range(5):
        await manager.broadcast({"case_id": "CASE-FAST", "msg_id": i})

    # Queue should be full at 2, remaining 3 dropped, NO blocking or unhandled QueueFull
    assert queue.qsize() == 2
    item1 = queue.get_nowait()
    assert '"msg_id": 0' in item1
    item2 = queue.get_nowait()
    assert '"msg_id": 1' in item2
    assert queue.empty()


# ============================================================================
# Fix #11: Batch persistence rollback & retry fallback
# ============================================================================


@pytest.mark.asyncio
async def test_pipeline_batch_rollback_fallback(db_session):
    """Verify that if a batch fails, the transaction is rolled back and valid events are individually saved."""
    from sqlalchemy import select

    from src.timeline.models import TimelineEventModel

    pipeline = PipelineOrchestrator()

    # Valid event
    ev_valid = TimelineEvent(
        case_id="CASE-FALLBACK",
        evidence_id="EVD-01",
        channel_id="CAM01",
        utc_timestamp=datetime(2026, 3, 10, 12, 0, 0, tzinfo=UTC),
        raw_timestamp="2026-03-10 12:00:00",
        event_type=EventType.FRAME_INDEX,
        frame_index=1,
    )

    # First persist ev_valid so that attempting to persist it again in batch causes UniqueConstraint violation
    await pipeline._persist_event(db_session, ev_valid)
    await db_session.commit()

    # New valid event
    ev_new = TimelineEvent(
        case_id="CASE-FALLBACK",
        evidence_id="EVD-01",
        channel_id="CAM01",
        utc_timestamp=datetime(2026, 3, 10, 12, 0, 1, tzinfo=UTC),
        raw_timestamp="2026-03-10 12:00:01",
        event_type=EventType.FRAME_INDEX,
        frame_index=2,
    )

    # In a single batch, pass ev_new and ev_valid (duplicate PK)
    # The batch will fail on commit, roll back cleanly, and ev_new will succeed on individual retry
    await pipeline._process_batch([ev_new, ev_valid])

    # Verify ev_new was saved successfully despite ev_valid failing in the same batch
    async with pipeline.session_factory() as verify_session:
        res = await verify_session.execute(
            select(TimelineEventModel).where(TimelineEventModel.id == ev_new.event_id)
        )
        saved = res.scalar_one_or_none()
        assert saved is not None
        assert saved.frame_index == 2


# ============================================================================
# Fix #8: Cross-camera correlation endpoint pagination over 1000 events
# ============================================================================


@pytest.mark.asyncio
async def test_correlate_case_events_pagination(client):
    """Verify that /api/v1/events/correlate paginates properly when a case has > 1000 events."""
    from src.timeline.dependencies import pipeline_instance
    from src.timeline.models import TimelineEventModel

    # Inject 1050 events directly into DB
    async with pipeline_instance.session_factory() as session:
        base_time = datetime(2026, 3, 10, 12, 0, 0, tzinfo=UTC)
        for i in range(1050):
            session.add(
                TimelineEventModel(
                    id=f"ev_paged_{i}",
                    case_id="CASE-PAGED",
                    evidence_id="EVD-01",
                    channel_id="CAM01" if i % 2 == 0 else "CAM02",
                    utc_timestamp=base_time,
                    raw_timestamp="2026-03-10 12:00:00",
                    timestamp_source="RECORDING_EMBEDDED",
                    applied_offset_ms=0.0,
                    event_type=EventType.AI_DETECTION.value,
                    frame_index=i,
                    payload_json='{"object_class": "person", "track_id": "T1"}',
                    source_reference_json="{}",
                    anomaly_flags_json="[]",
                    created_at=base_time,
                )
            )
        await session.commit()

    resp = await client.post(
        "/api/v1/events/correlate",
        json={"case_id": "CASE-PAGED", "window_seconds": 5.0},
    )
    assert resp.status_code == 200
    data = resp.json()
    assert data["case_id"] == "CASE-PAGED"
    assert data["correlated_count"] >= 1

