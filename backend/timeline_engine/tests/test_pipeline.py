"""Unit and integration tests for PipelineOrchestrator."""

import asyncio

import pytest

from src.timeline.constants import TimestampFormat, TimestampSource, VendorType
from src.timeline.exceptions import DuplicateEventError, PipelineQueueFullError
from src.timeline.pipeline import PipelineOrchestrator
from src.timeline.schemas import AIDetectionPayload, RawFrameMeta


@pytest.mark.asyncio
async def test_pipeline_ingestion_and_processing():
    pipeline = PipelineOrchestrator(queue_max_size=50)
    await pipeline.start()

    frame = RawFrameMeta(
        case_id="TEST-CASE",
        evidence_id="EVD-01",
        channel_id="CAM01",
        vendor_type=VendorType.HIKVISION,
        raw_timestamp_str="20260310T120000Z",
        timestamp_format=TimestampFormat.VENDOR_HIKVISION,
        timestamp_source=TimestampSource.RECORDING_EMBEDDED,
        frame_index=1,
    )

    dedup_id = await pipeline.submit_raw_frame(frame)
    assert f"frame:{frame.case_id}:{frame.evidence_id}:{frame.channel_id}:{frame.frame_index}" in dedup_id

    # Wait for worker loop to process
    await asyncio.sleep(0.3)
    await pipeline.stop()

    status = pipeline.get_status()
    assert status.processed_events_count >= 1


@pytest.mark.asyncio
async def test_pipeline_queue_full_backpressure():
    """Correction #1: Pipeline raises domain-specific PipelineQueueFullError (decoupled from HTTP)."""
    # Create tiny pipeline with maxsize=2
    pipeline = PipelineOrchestrator(queue_max_size=2)
    # Do NOT start the worker so queue fills up

    frame1 = RawFrameMeta(
        case_id="C1",
        evidence_id="E1",
        channel_id="CAM01",
        raw_timestamp_str="2026-03-10 12:00:01",
        frame_index=1,
    )
    frame2 = RawFrameMeta(
        case_id="C1",
        evidence_id="E1",
        channel_id="CAM01",
        raw_timestamp_str="2026-03-10 12:00:02",
        frame_index=2,
    )
    frame3 = RawFrameMeta(
        case_id="C1",
        evidence_id="E1",
        channel_id="CAM01",
        raw_timestamp_str="2026-03-10 12:00:03",
        frame_index=3,
    )

    await pipeline.submit_raw_frame(frame1)
    await pipeline.submit_raw_frame(frame2)

    # 3rd submission must trigger domain PipelineQueueFullError
    with pytest.raises(PipelineQueueFullError) as exc_info:
        await pipeline.submit_raw_frame(frame3)

    assert "capacity reached" in str(exc_info.value)
    assert exc_info.value.details["max_size"] == 2


@pytest.mark.asyncio
async def test_pipeline_duplicate_rejection():
    pipeline = PipelineOrchestrator()

    ai_item = AIDetectionPayload(
        case_id="C1",
        evidence_id="E1",
        channel_id="CAM01",
        frame_index=10,
        object_class="person",
        confidence=0.9,
        track_id="T1",
    )

    await pipeline.submit_ai_detection(ai_item)

    # Ingesting identical item must raise DuplicateEventError
    with pytest.raises(DuplicateEventError):
        await pipeline.submit_ai_detection(ai_item)


def test_pipeline_propagates_media_time_base_from_raw_frame_meta():
    """Regression test: Ensure media time base is propagated from RawFrameMeta to normalization.

    Catches the bug where 51200 / 15360 was wrongly calculated as 51200 / 1000 = 51.2s
    instead of 3.333333s.
    """
    from datetime import UTC, datetime

    pipeline = PipelineOrchestrator()
    frame = RawFrameMeta(
        case_id="REGRESSION-CASE",
        evidence_id="mot17_test_mp4",
        channel_id="CAM-01",
        vendor_type=VendorType.GENERIC,
        raw_timestamp_str="2026-09-10T12:00:00+00:00",
        timestamp_format=TimestampFormat.MEDIA_RELATIVE_PTS,
        timestamp_source=TimestampSource.DERIVED_PTS,
        timezone="UTC",
        frame_index=100,
        pts=51200,
        dts=51200,
        time_base_num=1,
        time_base_den=15360,
    )

    event = pipeline._convert_raw_frame_to_event(frame)
    assert event is not None

    # Expected: 2026-09-10T12:00:03.333333+00:00
    expected_utc = datetime(2026, 9, 10, 12, 0, 3, 333333, tzinfo=UTC)
    delta_micros = abs((event.utc_timestamp - expected_utc).total_seconds())
    assert delta_micros < 0.000002

    # Bug check: Ensure it is NOT 51.2 seconds later!
    buggy_utc = datetime(2026, 9, 10, 12, 0, 51, 200000, tzinfo=UTC)
    assert abs((event.utc_timestamp - buggy_utc).total_seconds()) > 40.0

    # Ensure time base survives into payload and source_reference
    assert event.payload["time_base_num"] == 1
    assert event.payload["time_base_den"] == 15360
    assert event.source_reference["time_base_num"] == 1
    assert event.source_reference["time_base_den"] == 15360


def test_pipeline_default_time_base_backwards_compatibility():
    """Ensure older payloads without explicit time base fields default safely to 1/1000."""
    from datetime import UTC, datetime

    pipeline = PipelineOrchestrator()
    frame = RawFrameMeta(
        case_id="BACKWARDS-COMPAT-CASE",
        evidence_id="legacy_mp4",
        channel_id="CAM-01",
        raw_timestamp_str="2026-09-10T12:00:00+00:00",
        timestamp_format=TimestampFormat.MEDIA_RELATIVE_PTS,
        timestamp_source=TimestampSource.DERIVED_PTS,
        frame_index=1,
        pts=5000,
    )

    event = pipeline._convert_raw_frame_to_event(frame)
    assert event is not None

    # 5000 / 1000 = 5.0 seconds
    assert event.utc_timestamp == datetime(2026, 9, 10, 12, 0, 5, 0, tzinfo=UTC)
    assert event.payload["time_base_num"] == 1
    assert event.payload["time_base_den"] == 1000
