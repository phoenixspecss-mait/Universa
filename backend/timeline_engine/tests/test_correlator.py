"""Comprehensive unit tests for EventCorrelator."""

from datetime import UTC, datetime

import pytest

from src.timeline.constants import CorrelationType, EventType
from src.timeline.correlator import EventCorrelator
from src.timeline.schemas import TimelineEvent


def make_event(
    event_id: str,
    channel_id: str,
    utc_timestamp: datetime,
    object_class: str = "person",
    track_id: str | None = None,
    is_global_track_id: bool = False,
    embedding: list[float] | None = None,
) -> TimelineEvent:
    return TimelineEvent(
        event_id=event_id,
        case_id="TEST-CASE",
        evidence_id="TEST-EVD",
        channel_id=channel_id,
        utc_timestamp=utc_timestamp,
        raw_timestamp=utc_timestamp.isoformat(),
        event_type=EventType.AI_DETECTION,
        payload={
            "object_class": object_class,
            "track_id": track_id,
            "is_global_track_id": is_global_track_id,
            "embedding": embedding,
        },
    )


@pytest.mark.asyncio
async def test_events_inside_temporal_window():
    correlator = EventCorrelator(window_seconds=5.0)
    t1 = datetime(2026, 3, 10, 12, 0, 0, tzinfo=UTC)
    t2 = datetime(2026, 3, 10, 12, 0, 3, tzinfo=UTC)  # dt = 3s <= 5s

    ev1 = make_event("e1", "CAM01", t1, object_class="person")
    ev2 = make_event("e2", "CAM02", t2, object_class="person")

    await correlator.add_event(ev1)
    corrs = await correlator.add_event(ev2)

    assert len(corrs) == 1
    corr = corrs[0]
    assert corr.correlation_type == CorrelationType.CROSS_CAMERA_CLASS_MATCH
    assert "CAM01" in [corr.primary_channel] + corr.secondary_channels
    assert "CAM02" in [corr.primary_channel] + corr.secondary_channels


@pytest.mark.asyncio
async def test_events_outside_temporal_window():
    correlator = EventCorrelator(window_seconds=5.0)
    t1 = datetime(2026, 3, 10, 12, 0, 0, tzinfo=UTC)
    t2 = datetime(2026, 3, 10, 12, 0, 15, tzinfo=UTC)  # dt = 15s > 5s

    ev1 = make_event("e1", "CAM01", t1)
    ev2 = make_event("e2", "CAM02", t2)

    await correlator.add_event(ev1)
    corrs = await correlator.add_event(ev2)
    assert len(corrs) == 0


@pytest.mark.asyncio
async def test_track_id_camera_local_by_default():
    """Correction #2: Treat track_id as camera-local by default.

    Never increase identity confidence merely because two cameras have the same track_id.
    """
    correlator = EventCorrelator(window_seconds=5.0)
    t1 = datetime(2026, 3, 10, 12, 0, 0, tzinfo=UTC)
    t2 = datetime(2026, 3, 10, 12, 0, 2, tzinfo=UTC)

    # Both have track_id="10", but is_global_track_id=False
    ev1 = make_event(
        "e1", "CAM01", t1, object_class="person", track_id="10", is_global_track_id=False
    )
    ev2 = make_event(
        "e2", "CAM02", t2, object_class="person", track_id="10", is_global_track_id=False
    )

    await correlator.add_event(ev1)
    corrs = await correlator.add_event(ev2)

    assert len(corrs) == 1
    # Must NOT be TRACK_CONTINUITY
    assert corrs[0].correlation_type != CorrelationType.TRACK_CONTINUITY
    assert corrs[0].confidence < 0.90


@pytest.mark.asyncio
async def test_global_track_id_continuity():
    """When is_global_track_id=True on both, track continuity is recognized."""
    correlator = EventCorrelator(window_seconds=5.0)
    t1 = datetime(2026, 3, 10, 12, 0, 0, tzinfo=UTC)
    t2 = datetime(2026, 3, 10, 12, 0, 2, tzinfo=UTC)

    ev1 = make_event(
        "e1", "CAM01", t1, object_class="person", track_id="GLOBAL_99", is_global_track_id=True
    )
    ev2 = make_event(
        "e2", "CAM02", t2, object_class="person", track_id="GLOBAL_99", is_global_track_id=True
    )

    await correlator.add_event(ev1)
    corrs = await correlator.add_event(ev2)

    assert len(corrs) == 1
    assert corrs[0].correlation_type == CorrelationType.TRACK_CONTINUITY
    assert corrs[0].confidence >= 0.90


@pytest.mark.asyncio
async def test_feature_embedding_cosine_similarity():
    correlator = EventCorrelator(window_seconds=5.0, cosine_threshold=0.80)
    t1 = datetime(2026, 3, 10, 12, 0, 0, tzinfo=UTC)
    t2 = datetime(2026, 3, 10, 12, 0, 2, tzinfo=UTC)

    vec_a = [0.5, 0.5, 0.5, 0.5]
    vec_b = [0.51, 0.49, 0.50, 0.50]  # Very high cosine similarity (> 0.99)

    ev1 = make_event("e1", "CAM01", t1, object_class="person", embedding=vec_a)
    ev2 = make_event("e2", "CAM02", t2, object_class="person", embedding=vec_b)

    await correlator.add_event(ev1)
    corrs = await correlator.add_event(ev2)

    assert len(corrs) == 1
    assert corrs[0].correlation_type == CorrelationType.EMBEDDING_MATCH
    assert corrs[0].confidence >= 0.85


@pytest.mark.asyncio
async def test_identity_safeguard_explanation():
    """Ensure correlation explanations explicitly state potential transition rather than asserting identity certainty."""
    correlator = EventCorrelator(window_seconds=5.0)
    t1 = datetime(2026, 3, 10, 12, 0, 0, tzinfo=UTC)
    t2 = datetime(2026, 3, 10, 12, 0, 3, tzinfo=UTC)

    ev1 = make_event("e1", "CAM01", t1, object_class="person")
    ev2 = make_event("e2", "CAM02", t2, object_class="person")

    await correlator.add_event(ev1)
    corrs = await correlator.add_event(ev2)

    assert len(corrs) == 1
    # Must not claim "the same person" with certainty
    assert "The same person moved" not in corrs[0].explanation


@pytest.mark.asyncio
async def test_out_of_order_events_handling():
    correlator = EventCorrelator(window_seconds=5.0)
    t_later = datetime(2026, 3, 10, 12, 0, 5, tzinfo=UTC)
    t_earlier = datetime(2026, 3, 10, 12, 0, 2, tzinfo=UTC)

    ev_later = make_event("e_later", "CAM01", t_later, object_class="person")
    ev_earlier = make_event("e_earlier", "CAM02", t_earlier, object_class="person")

    # Ingest later event first, then earlier
    await correlator.add_event(ev_later)
    corrs = await correlator.add_event(ev_earlier)

    assert len(corrs) == 1
    assert corrs[0].start_time_utc == t_earlier
    assert corrs[0].end_time_utc == t_later


def test_correlate_batch_empty():
    correlator = EventCorrelator()
    res = correlator.correlate_batch([])
    assert res == []
