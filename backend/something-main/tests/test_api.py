"""FastAPI REST API integration tests using httpx.AsyncClient + ASGITransport."""

import json
from datetime import UTC, datetime
from unittest.mock import patch
from uuid import uuid4

import pytest
from httpx import AsyncClient

from src.timeline.constants import EventType, TimestampSource
from src.timeline.exceptions import DuplicateEventError, PipelineQueueFullError
from src.timeline.models import TimelineEventModel
from src.timeline.pipeline import pipeline_instance


@pytest.mark.asyncio
async def test_health_check_endpoint(client: AsyncClient):
    resp = await client.get("/health")
    assert resp.status_code == 200
    data = resp.json()
    assert data["status"] == "healthy"
    assert "pipeline" in data


@pytest.mark.asyncio
async def test_ingest_frame_metadata_endpoint(client: AsyncClient):
    payload = {
        "case_id": "CASE-API-01",
        "evidence_id": "EVD-01",
        "channel_id": "CAM01",
        "vendor_type": "HIKVISION",
        "raw_timestamp_str": "20260310T120000Z",
        "timestamp_format": "VENDOR_HIKVISION",
        "timestamp_source": "RECORDING_EMBEDDED",
        "frame_index": 1,
        "file_offset_bytes": 1024,
    }
    resp = await client.post("/api/v1/ingest/frame-metadata", json=payload)
    assert resp.status_code == 201
    assert resp.json()["status"] == "queued"


@pytest.mark.asyncio
async def test_ingest_ai_detection_endpoint(client: AsyncClient):
    payload = {
        "case_id": "CASE-API-01",
        "evidence_id": "EVD-01",
        "channel_id": "CAM01",
        "frame_index": 1,
        "object_class": "person",
        "confidence": 0.95,
        "track_id": "trk_101",
        "is_global_track_id": False,
        "bounding_box": {"xmin": 0.1, "ymin": 0.2, "xmax": 0.5, "ymax": 0.8},
    }
    resp = await client.post("/api/v1/ingest/ai-detection", json=payload)
    assert resp.status_code == 201
    assert resp.json()["status"] == "queued"


@pytest.mark.asyncio
async def test_normalize_timestamp_endpoint(client: AsyncClient):
    payload = {
        "raw_timestamp_str": "2026-03-10 17:30:00",
        "timezone": "Asia/Kolkata",
        "channel_offset_ms": 1000.0,
    }
    resp = await client.post("/api/v1/timestamps/normalize", json=payload)
    assert resp.status_code == 200
    data = resp.json()
    assert data["success"] is True
    assert "2026-03-10T12:00:01" in data["utc_timestamp"]


@pytest.mark.asyncio
async def test_normalize_timestamp_endpoint_with_pts_and_time_base(client: AsyncClient):
    """Test standalone normalization API endpoint with media-relative PTS and custom time base."""
    payload = {
        "raw_timestamp_str": "2026-09-10T12:00:00+00:00",
        "timestamp_format": "MEDIA_RELATIVE_PTS",
        "timestamp_source": "DERIVED_PTS",
        "pts": 51200,
        "time_base_num": 1,
        "time_base_den": 15360,
    }
    resp = await client.post("/api/v1/timestamps/normalize", json=payload)
    assert resp.status_code == 200
    data = resp.json()
    assert data["success"] is True
    assert "2026-09-10T12:00:03.333333" in data["utc_timestamp"]


@pytest.mark.asyncio
async def test_timeline_retrieval_and_filtering(client: AsyncClient, db_session):
    case_id = f"CASE-{uuid4()}"
    ev_time = datetime(2026, 3, 10, 12, 0, 0, tzinfo=UTC)

    # Insert test events directly in DB
    ev1 = TimelineEventModel(
        id=str(uuid4()),
        case_id=case_id,
        evidence_id="E1",
        channel_id="CAM01",
        utc_timestamp=ev_time,
        raw_timestamp="2026-03-10 12:00:00",
        timestamp_source=TimestampSource.RECORDING_EMBEDDED.value,
        applied_offset_ms=0.0,
        event_type=EventType.FRAME_INDEX.value,
        frame_index=1,
        payload_json=json.dumps({"test": 1}),
        source_reference_json=json.dumps({"evidence_id": "E1"}),
        anomaly_flags_json=json.dumps([]),
        created_at=ev_time,
    )
    ev2 = TimelineEventModel(
        id=str(uuid4()),
        case_id=case_id,
        evidence_id="E2",
        channel_id="CAM02",
        utc_timestamp=ev_time,
        raw_timestamp="2026-03-10 12:00:00",
        timestamp_source=TimestampSource.RECORDING_EMBEDDED.value,
        applied_offset_ms=0.0,
        event_type=EventType.AI_DETECTION.value,
        frame_index=1,
        payload_json=json.dumps({"object_class": "car"}),
        source_reference_json=json.dumps({"evidence_id": "E2"}),
        anomaly_flags_json=json.dumps([]),
        created_at=ev_time,
    )
    db_session.add_all([ev1, ev2])
    await db_session.commit()

    # Query unified timeline
    resp = await client.get(f"/api/v1/timeline/{case_id}")
    assert resp.status_code == 200
    assert resp.json()["total_events"] == 2

    # Query channel-specific timeline
    resp_cam01 = await client.get(f"/api/v1/timeline/{case_id}/CAM01")
    assert resp_cam01.status_code == 200
    assert resp_cam01.json()["total_events"] == 1

    # Query single event
    resp_ev = await client.get(f"/api/v1/events/{ev1.id}")
    assert resp_ev.status_code == 200
    assert resp_ev.json()["event_id"] == ev1.id

    # Query non-existent event
    resp_404 = await client.get("/api/v1/events/non-existent-id")
    assert resp_404.status_code == 404


@pytest.mark.asyncio
async def test_timeline_export_endpoint(client: AsyncClient, db_session):
    case_id = f"CASE-{uuid4()}"
    resp = await client.get(f"/api/v1/timeline/{case_id}/export")
    assert resp.status_code == 200
    data = resp.json()
    assert "integrity_statement" in data
    assert "forensic_tool" in data


@pytest.mark.asyncio
async def test_api_pipeline_queue_full_translates_to_429(client: AsyncClient):
    """Correction #1: FastAPI handles PipelineQueueFullError by returning HTTP 429."""
    with patch.object(
        pipeline_instance, "submit_raw_frame", side_effect=PipelineQueueFullError(2000, 2000)
    ):
        payload = {
            "case_id": "C1",
            "evidence_id": "E1",
            "channel_id": "CAM01",
            "raw_timestamp_str": "2026-03-10 12:00:00",
            "frame_index": 1,
        }
        resp = await client.post("/api/v1/ingest/frame-metadata", json=payload)
        assert resp.status_code == 429
        assert "capacity reached" in resp.json()["detail"]


@pytest.mark.asyncio
async def test_api_duplicate_event_translates_to_409(client: AsyncClient):
    """FastAPI handles DuplicateEventError by returning HTTP 409."""
    with patch.object(
        pipeline_instance, "submit_raw_frame", side_effect=DuplicateEventError("Duplicate")
    ):
        payload = {
            "case_id": "C1",
            "evidence_id": "E1",
            "channel_id": "CAM01",
            "raw_timestamp_str": "2026-03-10 12:00:00",
            "frame_index": 1,
        }
        resp = await client.post("/api/v1/ingest/frame-metadata", json=payload)
        assert resp.status_code == 409
