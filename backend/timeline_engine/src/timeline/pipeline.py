"""Async Pipeline Orchestrator.

Manages bounded asynchronous ingestion queues, normalization, deduplication,
persistence, cross-camera correlation, and event broadcasting.
Decoupled completely from HTTP transport semantics.
"""

import asyncio
import json
import logging
from collections import OrderedDict
from collections.abc import Callable
try:
    from datetime import UTC, datetime
except ImportError:
    from datetime import datetime, timezone
    UTC = timezone.utc

from typing import Any
from uuid import uuid4

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker

from src.config import settings
from src.database import SessionFactory
from src.timeline.constants import (
    EventType,
    TimestampSource,
)
from src.timeline.correlator import EventCorrelator
from src.timeline.exceptions import DuplicateEventError, PipelineQueueFullError
from src.timeline.models import CorrelatedEventModel, TimelineEventModel
from src.timeline.normalizer import TimelineNormalizer
from src.timeline.schemas import (
    AIDetectionPayload,
    CorrelatedEvent,
    PipelineStatus,
    RawFrameMeta,
    TimelineEvent,
)

_default_session_factory: async_sessionmaker[AsyncSession] | None = None


def set_default_pipeline_session_factory(factory: async_sessionmaker[AsyncSession] | None) -> None:
    """Set global default session factory for all pipeline orchestrators (Fix #5)."""
    global _default_session_factory
    _default_session_factory = factory


logger = logging.getLogger(__name__)


class PipelineOrchestrator:
    """Orchestrates asynchronous timeline processing, normalization, and correlation.

    Decoupled from HTTP transport, uses bounded queues for backpressure,
    persists in batches with clean rollback, and isolates database sessions.
    """

    def __init__(
        self,
        normalizer: TimelineNormalizer | None = None,
        correlator: EventCorrelator | None = None,
        queue_max_size: int | None = None,
        session_factory: async_sessionmaker[AsyncSession] | None = None,
    ) -> None:
        self.normalizer = normalizer or TimelineNormalizer()
        self.correlator = correlator or EventCorrelator()
        self.queue_max_size = queue_max_size or settings.PIPELINE_QUEUE_MAX_SIZE
        self.session_factory: async_sessionmaker[AsyncSession] = (
            session_factory or _default_session_factory or SessionFactory
        )

        # Bounded asynchronous ingestion queue (lazily bound to current running event loop)
        self._queue: asyncio.Queue[RawFrameMeta | AIDetectionPayload | TimelineEvent] | None = None
        self._bound_loop: asyncio.AbstractEventLoop | None = None

        # Worker lifecycle
        self._worker_task: asyncio.Task | None = None
        self._is_running = False

        # Metrics & Deduplication (OrderedDict for deterministic LRU eviction - Fix #7)
        self._processed_count = 0
        self._dropped_count = 0
        self._anomalies_count = 0
        self._dedup_cache: OrderedDict[str, None] = OrderedDict()

        # Camera calibration cache: (case_id, channel_id) -> calibration dict (Fix #3)
        self._camera_calibrations: dict[tuple[str, str], dict[str, Any]] = {}

        # Recent frame timestamp cache for O(1) AI frame_index lookup (Fix #2)
        # (case_id, evidence_id, channel_id, frame_index) -> (utc_timestamp, raw_timestamp, applied_offset_ms)
        self._recent_frames: OrderedDict[tuple[str, str, str, int], tuple[datetime, str, float]] = (
            OrderedDict()
        )

        # Track latest known timestamp & frame index per channel for anomaly detection (Fix #9)
        self._channel_state: dict[str, tuple[datetime, int]] = {}

        # Broadcast listener callbacks (e.g. WebSocket connection manager)
        self._broadcast_listeners: list[Callable[[dict[str, Any]], Any]] = []

    @property
    def queue(self) -> asyncio.Queue[RawFrameMeta | AIDetectionPayload | TimelineEvent]:
        try:
            current_loop = asyncio.get_running_loop()
        except RuntimeError:
            current_loop = None

        if self._queue is None or (
            current_loop is not None
            and self._bound_loop is not None
            and self._bound_loop is not current_loop
        ):
            old_items: list[RawFrameMeta | AIDetectionPayload | TimelineEvent] = []
            if self._queue is not None:
                while not self._queue.empty():
                    try:
                        old_items.append(self._queue.get_nowait())
                    except asyncio.QueueEmpty:
                        break
            self._queue = asyncio.Queue(maxsize=self.queue_max_size)
            self._bound_loop = current_loop
            for it in old_items:
                self._queue.put_nowait(it)
        elif self._bound_loop is None and current_loop is not None:
            self._bound_loop = current_loop

        return self._queue

    def set_session_factory(self, session_factory: async_sessionmaker[AsyncSession]) -> None:
        """Override database session factory (used for test isolation - Fix #5)."""
        self.session_factory = session_factory

    def set_camera_calibration(
        self,
        case_id: str,
        channel_id: str,
        clock_offset_ms: float = 0.0,
        drift_rate_ppm: float = 0.0,
        timezone: str = "UTC",
        reference_time_utc: datetime | None = None,
    ) -> None:
        """Register or update camera clock offset/drift calibrations for pipeline normalization (Fix #3)."""
        self._camera_calibrations[(case_id, channel_id)] = {
            "clock_offset_ms": clock_offset_ms,
            "drift_rate_ppm": drift_rate_ppm,
            "timezone": timezone,
            "reference_time_utc": reference_time_utc,
        }

    def register_broadcast_listener(self, listener: Callable[[dict[str, Any]], Any]) -> None:
        """Register a callback to receive live pipeline events (WebSocket bus)."""
        self._broadcast_listeners.append(listener)

    async def submit_raw_frame(self, frame_meta: RawFrameMeta) -> str:
        """Ingest raw frame metadata into the async queue.

        Raises DuplicateEventError on duplicate, or PipelineQueueFullError if queue capacity is exceeded.
        (Fix #6: evidence_id included in dedup key).
        """
        dedup_key = (
            f"frame:{frame_meta.case_id}:{frame_meta.evidence_id}:"
            f"{frame_meta.channel_id}:{frame_meta.frame_index}:{frame_meta.raw_timestamp_str}"
        )
        if dedup_key in self._dedup_cache:
            raise DuplicateEventError(
                f"Duplicate frame index {frame_meta.frame_index} for evidence {frame_meta.evidence_id} on channel {frame_meta.channel_id}"
            )

        self._record_dedup_key(dedup_key)

        try:
            self.queue.put_nowait(frame_meta)
            return dedup_key
        except asyncio.QueueFull as exc:
            self._dropped_count += 1
            raise PipelineQueueFullError(
                queue_size=self.queue.qsize(), max_size=self.queue_max_size
            ) from exc

    async def submit_ai_detection(self, ai_payload: AIDetectionPayload) -> str:
        """Ingest AI detection payload into the async queue.

        Raises DuplicateEventError on duplicate, or PipelineQueueFullError if queue capacity is exceeded.
        (Fix #6: evidence_id included in dedup key).
        """
        dedup_key = (
            f"ai:{ai_payload.case_id}:{ai_payload.evidence_id}:"
            f"{ai_payload.channel_id}:{ai_payload.frame_index}:"
            f"{ai_payload.object_class}:{ai_payload.track_id}"
        )
        if dedup_key in self._dedup_cache:
            raise DuplicateEventError(
                f"Duplicate AI detection for evidence {ai_payload.evidence_id} on channel {ai_payload.channel_id}"
            )

        self._record_dedup_key(dedup_key)

        try:
            self.queue.put_nowait(ai_payload)
            return dedup_key
        except asyncio.QueueFull as exc:
            self._dropped_count += 1
            raise PipelineQueueFullError(
                queue_size=self.queue.qsize(), max_size=self.queue_max_size
            ) from exc

    def _record_dedup_key(self, key: str) -> None:
        """Maintain bounded deterministic LRU deduplication cache (Fix #7)."""
        self._dedup_cache[key] = None
        if len(self._dedup_cache) > settings.DEDUPLICATION_CACHE_SIZE:
            self._dedup_cache.popitem(last=False)

    async def start(self) -> None:
        """Start the background ingestion pipeline worker."""
        if self._is_running:
            return
        # Ensure queue is bound to current running event loop
        _ = self.queue
        self._is_running = True
        self._worker_task = asyncio.create_task(self._worker_loop())
        logger.info("PipelineOrchestrator worker started (queue capacity: %d)", self.queue_max_size)

    async def stop(self) -> None:
        """Gracefully stop worker and drain pending queue items."""
        if not self._is_running:
            return
        self._is_running = False
        logger.info("Stopping PipelineOrchestrator worker. Draining pending items...")

        try:
            await asyncio.wait_for(
                self.queue.join(), timeout=settings.PIPELINE_DRAIN_TIMEOUT_SECONDS
            )
        except TimeoutError:
            logger.warning("Pipeline drain timed out; proceeding with shutdown.")

        if self._worker_task and not self._worker_task.done():
            self._worker_task.cancel()
            try:
                await self._worker_task
            except asyncio.CancelledError:
                pass
        logger.info("PipelineOrchestrator worker stopped cleanly.")

    async def _worker_loop(self) -> None:
        """Continuously process incoming items from the queue in bounded batches (Fix #11)."""
        while self._is_running:
            try:
                item = await self.queue.get()
                items = [item]

                # Drain up to PIPELINE_WORKER_BATCH_SIZE - 1 additional items without blocking
                while len(items) < settings.PIPELINE_WORKER_BATCH_SIZE and not self.queue.empty():
                    try:
                        items.append(self.queue.get_nowait())
                    except asyncio.QueueEmpty:
                        break

                await self._process_batch(items)

                for _ in items:
                    self.queue.task_done()
            except asyncio.CancelledError:
                break
            except Exception as exc:
                logger.error("Error in pipeline worker batch: %s", exc, exc_info=True)
                await asyncio.sleep(0.05)

    async def _process_batch(
        self, items: list[RawFrameMeta | AIDetectionPayload | TimelineEvent]
    ) -> None:
        """Process and persist a batch of items with clean rollback fallback (Fix #11)."""
        processed_pairs: list[tuple[TimelineEvent, list[CorrelatedEvent]]] = []

        # Step A: Convert items into TimelineEvents
        async with self.session_factory() as read_session:
            for item in items:
                event: TimelineEvent | None = None

                if isinstance(item, RawFrameMeta):
                    event = self._convert_raw_frame_to_event(item)
                elif isinstance(item, AIDetectionPayload):
                    event = await self._convert_ai_payload_to_event(item, session=read_session)
                elif isinstance(item, TimelineEvent):
                    event = item

                if event is None:
                    self._dropped_count += 1
                    continue

                # Check continuity anomalies (Fix #9: do not corrupt state on out-of-order frames)
                ch_state = self._channel_state.get(event.channel_id)
                curr_idx = event.frame_index if event.frame_index is not None else 0

                if ch_state:
                    last_time, last_idx = ch_state
                    anomalies = TimelineNormalizer.check_temporal_continuity(
                        channel_id=event.channel_id,
                        current_utc=event.utc_timestamp,
                        current_frame_index=curr_idx,
                        last_utc=last_time,
                        last_frame_index=last_idx,
                    )
                    if anomalies:
                        event.anomaly_flags.extend(anomalies)
                        self._anomalies_count += len(anomalies)
                        await self._broadcast(
                            {
                                "type": "timeline_anomaly",
                                "case_id": event.case_id,
                                "data": {
                                    "channel_id": event.channel_id,
                                    "anomalies": anomalies,
                                    "event_id": event.event_id,
                                    "utc_timestamp": event.utc_timestamp.isoformat(),
                                },
                            }
                        )

                    # Only advance channel state if frame index is >= last seen frame index (Fix #9)
                    if curr_idx >= last_idx:
                        self._channel_state[event.channel_id] = (event.utc_timestamp, curr_idx)
                else:
                    self._channel_state[event.channel_id] = (event.utc_timestamp, curr_idx)

                # Correlate across cameras
                correlations = await self.correlator.add_event(event)
                processed_pairs.append((event, correlations))

        if not processed_pairs:
            return

        # Step B: Batch persistence in a single transaction (Fix #11)
        batch_persisted = False
        async with self.session_factory() as write_session:
            try:
                for event, corrs in processed_pairs:
                    await self._persist_event(write_session, event)
                    for c in corrs:
                        await self._persist_correlation(write_session, c)
                await write_session.commit()
                batch_persisted = True
                self._processed_count += len(processed_pairs)
            except Exception as batch_err:
                # User Requirement: fully rollback failed transaction before individual retries!
                await write_session.rollback()
                logger.warning(
                    "Batch persistence transaction failed (%s); rolled back cleanly. Retrying records individually...",
                    batch_err,
                )

        # Step C: Fallback retry item by item in isolated sessions if batch transaction failed
        if not batch_persisted:
            for event, corrs in processed_pairs:
                async with self.session_factory() as single_session:
                    try:
                        await self._persist_event(single_session, event)
                        for c in corrs:
                            await self._persist_correlation(single_session, c)
                        await single_session.commit()
                        self._processed_count += 1
                    except Exception as single_err:
                        await single_session.rollback()
                        self._dropped_count += 1
                        logger.error(
                            "Failed to persist event %s individually: %s", event.event_id, single_err
                        )

        # Step D: Broadcast live events to WebSocket listeners (with case_id tagging - Fix #15)
        for event, corrs in processed_pairs:
            await self._broadcast(
                {
                    "type": "timeline_event",
                    "case_id": event.case_id,
                    "data": event.model_dump(mode="json"),
                }
            )
            for c in corrs:
                await self._broadcast(
                    {
                        "type": "correlated_event",
                        "case_id": c.case_id,
                        "data": c.model_dump(mode="json"),
                    }
                )

    def _convert_raw_frame_to_event(self, raw: RawFrameMeta) -> TimelineEvent | None:
        """Normalize raw frame metadata applying camera calibration (Fix #3)."""
        cal = self._camera_calibrations.get((raw.case_id, raw.channel_id), {})
        offset_ms = cal.get("clock_offset_ms", 0.0)
        drift_rate_ppm = cal.get("drift_rate_ppm", 0.0)
        tz = raw.timezone or cal.get("timezone")
        ref_time = cal.get("reference_time_utc")

        norm = self.normalizer.normalize(
            raw_timestamp_str=raw.raw_timestamp_str,
            timestamp_format=raw.timestamp_format,
            timestamp_source=raw.timestamp_source,
            supplied_timezone=tz,
            offset_ms=offset_ms,
            drift_rate_ppm=drift_rate_ppm,
            reference_time_utc=ref_time,
            pts=raw.pts,
            time_base_num=raw.time_base_num,
            time_base_den=raw.time_base_den,
        )

        if not norm.success or norm.utc_timestamp is None:
            logger.warning(
                "Failed to normalize raw frame: %s (Errors: %s)", raw.raw_timestamp_str, norm.errors
            )
            self._anomalies_count += 1
            return None

        event = TimelineEvent(
            event_id=str(uuid4()),
            case_id=raw.case_id,
            evidence_id=raw.evidence_id,
            channel_id=raw.channel_id,
            utc_timestamp=norm.utc_timestamp,
            raw_timestamp=raw.raw_timestamp_str,
            timestamp_source=norm.timestamp_source,
            applied_offset_ms=norm.applied_offset_ms,
            event_type=EventType.FRAME_INDEX,
            frame_index=raw.frame_index,
            file_offset_bytes=raw.file_offset_bytes,
            pts=raw.pts,
            dts=raw.dts,
            time_base_num=raw.time_base_num,
            time_base_den=raw.time_base_den,
            payload={
                "vendor_type": raw.vendor_type.value,
                "frame_hash_sha256": raw.frame_hash_sha256,
                "file_path": raw.file_path,
                "time_base_num": raw.time_base_num,
                "time_base_den": raw.time_base_den,
            },
            source_reference={
                "evidence_id": raw.evidence_id,
                "file_offset_bytes": raw.file_offset_bytes,
                "frame_index": raw.frame_index,
                "pts": raw.pts,
                "time_base_num": raw.time_base_num,
                "time_base_den": raw.time_base_den,
            },
            anomaly_flags=norm.anomaly_flags,
        )

        # Cache frame timestamp for O(1) AI frame_index lookup (Fix #2)
        frame_key = (raw.case_id, raw.evidence_id, raw.channel_id, raw.frame_index)
        self._recent_frames[frame_key] = (norm.utc_timestamp, raw.raw_timestamp_str, norm.applied_offset_ms)
        if len(self._recent_frames) > 10000:
            self._recent_frames.popitem(last=False)

        return event

    async def _convert_ai_payload_to_event(
        self, ai: AIDetectionPayload, session: AsyncSession | None = None
    ) -> TimelineEvent | None:
        """Convert AI detection payload to canonical TimelineEvent, resolving frame_index if needed (Fix #2)."""
        utc_time = ai.utc_timestamp
        raw_str = ai.raw_timestamp_str or (utc_time.isoformat() if utc_time else "")
        applied_offset = 0.0
        anomalies: list[str] = []

        # If timestamp is missing, resolve via frame_index lookup (Fix #2)
        if utc_time is None and (not raw_str or raw_str.strip() == ""):
            frame_key = (ai.case_id, ai.evidence_id, ai.channel_id, ai.frame_index)
            cached_frame = self._recent_frames.get(frame_key)
            if cached_frame:
                utc_time, raw_str, applied_offset = cached_frame
            elif session is not None:
                # Query database for the matching frame
                stmt = (
                    select(TimelineEventModel)
                    .where(
                        TimelineEventModel.case_id == ai.case_id,
                        TimelineEventModel.evidence_id == ai.evidence_id,
                        TimelineEventModel.channel_id == ai.channel_id,
                        TimelineEventModel.frame_index == ai.frame_index,
                        TimelineEventModel.event_type == EventType.FRAME_INDEX.value,
                    )
                    .limit(1)
                )
                result = await session.execute(stmt)
                db_frame = result.scalar_one_or_none()
                if db_frame:
                    utc_time = db_frame.utc_timestamp
                    raw_str = db_frame.raw_timestamp
                    applied_offset = db_frame.applied_offset_ms
                else:
                    logger.warning(
                        "AI detection references unknown frame index %d on channel %s (evidence %s). Flagging anomaly.",
                        ai.frame_index,
                        ai.channel_id,
                        ai.evidence_id,
                    )
                    anomalies.append("UNRESOLVED_FRAME_REFERENCE")
                    utc_time = datetime.now(UTC)
                    raw_str = f"UNRESOLVED_FRAME_INDEX_{ai.frame_index}"
            else:
                anomalies.append("UNRESOLVED_FRAME_REFERENCE")
                utc_time = datetime.now(UTC)
                raw_str = f"UNRESOLVED_FRAME_INDEX_{ai.frame_index}"

        elif utc_time is None:
            norm = self.normalizer.normalize(
                raw_timestamp_str=raw_str,
                timestamp_source=TimestampSource.RECORDING_EMBEDDED,
            )
            if not norm.success or norm.utc_timestamp is None:
                logger.warning("Failed to normalize AI timestamp: %s", raw_str)
                return None
            utc_time = norm.utc_timestamp
            applied_offset = norm.applied_offset_ms
            anomalies.extend(norm.anomaly_flags)

        return TimelineEvent(
            event_id=str(uuid4()),
            case_id=ai.case_id,
            evidence_id=ai.evidence_id,
            channel_id=ai.channel_id,
            utc_timestamp=utc_time,
            raw_timestamp=raw_str,
            timestamp_source=TimestampSource.RECORDING_EMBEDDED,
            applied_offset_ms=applied_offset,
            event_type=EventType.AI_DETECTION,
            frame_index=ai.frame_index,
            payload={
                "object_class": ai.object_class,
                "confidence": ai.confidence,
                "bounding_box": ai.bounding_box.model_dump() if ai.bounding_box else None,
                "track_id": str(ai.track_id) if ai.track_id is not None else None,
                "is_global_track_id": ai.is_global_track_id,
                "embedding": ai.embedding,
                "detection_metadata": ai.detection_metadata,
            },
            source_reference={
                "evidence_id": ai.evidence_id,
                "frame_index": ai.frame_index,
            },
            anomaly_flags=anomalies,
        )

    async def _persist_event(self, session: AsyncSession, event: TimelineEvent) -> None:
        """Save TimelineEventModel to database (Fix #14: time_base columns persisted)."""
        db_event = TimelineEventModel(
            id=event.event_id,
            case_id=event.case_id,
            evidence_id=event.evidence_id,
            channel_id=event.channel_id,
            utc_timestamp=event.utc_timestamp,
            raw_timestamp=event.raw_timestamp,
            timestamp_source=event.timestamp_source.value,
            applied_offset_ms=event.applied_offset_ms,
            event_type=event.event_type.value,
            frame_index=event.frame_index,
            file_offset_bytes=event.file_offset_bytes,
            pts=event.pts,
            dts=event.dts,
            time_base_num=event.time_base_num,
            time_base_den=event.time_base_den,
            payload_json=json.dumps(event.payload),
            source_reference_json=json.dumps(event.source_reference),
            anomaly_flags_json=json.dumps(event.anomaly_flags),
            created_at=datetime.now(UTC),
        )
        session.add(db_event)

    async def _persist_correlation(self, session: AsyncSession, corr: CorrelatedEvent) -> None:
        """Save CorrelatedEventModel to database."""
        db_corr = CorrelatedEventModel(
            id=str(uuid4()),
            correlation_id=corr.correlation_id,
            case_id=corr.case_id,
            primary_channel=corr.primary_channel,
            secondary_channels_json=json.dumps(corr.secondary_channels),
            source_event_ids_json=json.dumps(corr.source_event_ids),
            start_time_utc=corr.start_time_utc,
            end_time_utc=corr.end_time_utc,
            event_type=corr.event_type,
            correlation_type=corr.correlation_type.value,
            confidence=corr.confidence,
            explanation=corr.explanation,
            metadata_json=json.dumps(corr.metadata),
            created_at=datetime.now(UTC),
        )
        session.add(db_corr)

    async def _broadcast(self, message: dict[str, Any]) -> None:
        """Dispatch message to registered WebSocket listeners."""
        for listener in self._broadcast_listeners:
            try:
                res = listener(message)
                if asyncio.iscoroutine(res):
                    await res
            except Exception as exc:
                logger.error("Error broadcasting message: %s", exc)

    def get_status(self) -> PipelineStatus:
        """Query current pipeline operational metrics."""
        return PipelineStatus(
            queue_size=self.queue.qsize(),
            queue_max_size=self.queue_max_size,
            is_healthy=self._is_running,
            processed_events_count=self._processed_count,
            dropped_events_count=self._dropped_count,
            detected_anomalies_count=self._anomalies_count,
        )


# Global singleton instance for application lifecycle
pipeline_instance = PipelineOrchestrator()
