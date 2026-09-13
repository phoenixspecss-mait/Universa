"""Multi-Camera Event Correlation Engine.

Implements temporal sliding window correlation across independent camera feeds.
Adheres strictly to forensic evidentiary standards: temporal correlation does NOT
automatically establish personal identity.
"""

import asyncio
import math
from collections import OrderedDict
from datetime import datetime
from uuid import uuid4

from src.config import settings
from src.timeline.constants import CorrelationType, EventType
from src.timeline.schemas import CorrelatedEvent, TimelineEvent


class EventCorrelator:
    """Multi-camera temporal and semantic event correlation engine."""

    def __init__(
        self,
        window_seconds: float | None = None,
        max_buffer_size: int | None = None,
        allowed_lateness_seconds: float | None = None,
        cosine_threshold: float | None = None,
    ) -> None:
        self.window_seconds = window_seconds or settings.CORRELATION_WINDOW_SECONDS
        self.max_buffer_size = max_buffer_size or settings.CORRELATION_BUFFER_MAX_SIZE
        self.allowed_lateness_seconds = (
            allowed_lateness_seconds
            if allowed_lateness_seconds is not None
            else settings.ALLOWED_LATENESS_SECONDS
        )
        self.cosine_threshold = cosine_threshold or settings.COSINE_SIMILARITY_THRESHOLD

        # In-memory sliding window buffer sorted by utc_timestamp
        self._buffer: list[TimelineEvent] = []
        self._processed_event_ids: OrderedDict[str, None] = OrderedDict()
        self._lock = asyncio.Lock()

    @staticmethod
    def _is_correlatable_event(ev: TimelineEvent) -> bool:
        """Determine whether an event carries semantic significance for cross-camera correlation.

        Forensic Rule: Raw video FRAME_INDEX events without AI detections, motion,
        or forensic anomalies must not produce cross-camera correlation explosion.
        """
        if ev.event_type != EventType.FRAME_INDEX:
            return True
        payload = ev.payload or {}
        if (
            payload.get("object_class")
            or payload.get("motion")
            or payload.get("track_id")
            or payload.get("embedding")
            or ev.anomaly_flags
        ):
            return True
        return False

    async def add_event(self, event: TimelineEvent) -> list[CorrelatedEvent]:
        """Ingest event, correlate against current window, and prune old buffer items."""
        # Non-correlatable raw frame events skip correlation completely (Fix #1)
        if not self._is_correlatable_event(event):
            return []

        async with self._lock:
            # Deterministic LRU deduplication (Fix #7)
            if event.event_id in self._processed_event_ids:
                return []

            self._processed_event_ids[event.event_id] = None
            if len(self._processed_event_ids) > settings.DEDUPLICATION_CACHE_SIZE:
                self._processed_event_ids.popitem(last=False)

            # Insert sorted by utc_timestamp to handle out-of-order arrival
            idx = self._find_insertion_index(event.utc_timestamp)
            self._buffer.insert(idx, event)

            # Correlate this event against buffered events
            correlations = self._evaluate_correlations(event)

            # Evict events older than window + allowed_lateness
            self._prune_buffer(latest_time=event.utc_timestamp)

            return correlations

    def correlate_batch(
        self,
        events: list[TimelineEvent],
        custom_window_seconds: float | None = None,
    ) -> list[CorrelatedEvent]:
        """Correlate a batch of events synchronously (e.g. for historical queries)."""
        if not events:
            return []

        window = custom_window_seconds or self.window_seconds
        # Filter for correlatable events and sort chronologically by UTC timestamp
        sorted_events = sorted(
            [e for e in events if self._is_correlatable_event(e)],
            key=lambda e: e.utc_timestamp,
        )
        correlations: list[CorrelatedEvent] = []
        seen_pairs: set[tuple[str, str]] = set()

        for i, ev1 in enumerate(sorted_events):
            for j in range(i + 1, len(sorted_events)):
                ev2 = sorted_events[j]
                dt = (ev2.utc_timestamp - ev1.utc_timestamp).total_seconds()
                if dt > window:
                    break  # Beyond sliding window

                # Skip same channel unless multi-object on same frame
                if ev1.channel_id == ev2.channel_id:
                    continue

                pair_key = tuple(sorted([ev1.event_id, ev2.event_id]))
                if pair_key in seen_pairs:
                    continue
                seen_pairs.add(pair_key)

                corr = self._compute_pair_correlation(ev1, ev2, dt, window)
                if corr is not None:
                    correlations.append(corr)

        return correlations

    def _evaluate_correlations(self, target_event: TimelineEvent) -> list[CorrelatedEvent]:
        """Evaluate target event against active buffer within +/- window_seconds."""
        if not self._is_correlatable_event(target_event):
            return []

        correlations: list[CorrelatedEvent] = []
        target_time = target_event.utc_timestamp

        for ev in self._buffer:
            if ev.event_id == target_event.event_id:
                continue
            if ev.channel_id == target_event.channel_id:
                continue  # Cross-camera focus
            if not self._is_correlatable_event(ev):
                continue

            dt = abs((target_time - ev.utc_timestamp).total_seconds())
            if dt <= self.window_seconds:
                corr = self._compute_pair_correlation(target_event, ev, dt, self.window_seconds)
                if corr is not None:
                    correlations.append(corr)

        return correlations

    def _compute_pair_correlation(
        self,
        ev1: TimelineEvent,
        ev2: TimelineEvent,
        dt_seconds: float,
        window: float,
    ) -> CorrelatedEvent | None:
        """Compute forensic correlation between two cross-camera events.

        CRITICAL FORENSIC RULES:
        1. Temporal correlation DOES NOT assert identity.
        2. track_id is strictly camera-local unless is_global_track_id is explicitly True.
        3. Feature embedding similarity increases confidence only when validated mathematically.
        """
        # Temporal base score: 1.0 at dt=0, down to 0.5 at dt=window
        temporal_score = max(0.5, 1.0 - (dt_seconds / (window * 2.0)))

        # Extract AI payloads if present
        payload1 = ev1.payload or {}
        payload2 = ev2.payload or {}

        class1 = payload1.get("object_class")
        class2 = payload2.get("object_class")

        track1 = payload1.get("track_id")
        track2 = payload2.get("track_id")
        is_global1 = payload1.get("is_global_track_id", False)
        is_global2 = payload2.get("is_global_track_id", False)

        embed1 = payload1.get("embedding")
        embed2 = payload2.get("embedding")

        correlation_type = CorrelationType.TEMPORAL_COINCIDENCE
        confidence = temporal_score * 0.7  # Temporal coincidence alone caps at ~0.7
        explanation = (
            f"Temporal coincidence within +/-{window:.1f}s window "
            f"(elapsed: {dt_seconds:.2f}s) between {ev1.channel_id} and {ev2.channel_id}."
        )

        # 1. Check verified global track ID (Correction #2)
        if is_global1 and is_global2 and track1 is not None and track1 == track2:
            correlation_type = CorrelationType.TRACK_CONTINUITY
            confidence = min(0.98, 0.90 + (temporal_score * 0.08))
            explanation = (
                f"Global multi-camera tracking continuity confirmed (Track ID '{track1}') "
                f"across {ev1.channel_id} and {ev2.channel_id} (elapsed: {dt_seconds:.2f}s)."
            )

        # 2. Check ReID Feature Embedding Cosine Similarity
        elif embed1 and embed2 and len(embed1) == len(embed2):
            sim = self._cosine_similarity(embed1, embed2)
            if sim >= self.cosine_threshold:
                correlation_type = CorrelationType.EMBEDDING_MATCH
                confidence = min(0.92, (temporal_score * 0.4) + (sim * 0.6))
                explanation = (
                    f"Visual feature embedding similarity match (Cosine: {sim:.3f} >= {self.cosine_threshold}) "
                    f"between {ev1.channel_id} and {ev2.channel_id} (elapsed: {dt_seconds:.2f}s). "
                    f"Forensic note: Indicates visual similarity, not definitive biometric identity."
                )

        # 3. Check Object Class match
        elif class1 and class2 and class1.lower() == class2.lower():
            correlation_type = CorrelationType.CROSS_CAMERA_CLASS_MATCH
            confidence = min(0.80, temporal_score * 0.8)
            explanation = (
                f"Cross-camera class match ('{class1}') detected on {ev1.channel_id} and {ev2.channel_id} "
                f"within temporal window (elapsed: {dt_seconds:.2f}s). Possible transition."
            )

        # If both are motion events
        elif (
            ev1.event_type == EventType.MOTION_DETECTED
            and ev2.event_type == EventType.MOTION_DETECTED
        ):
            correlation_type = CorrelationType.POSSIBLE_TRANSITION
            confidence = temporal_score * 0.65
            explanation = (
                f"Motion detected sequentially on {ev1.channel_id} and {ev2.channel_id} "
                f"(elapsed: {dt_seconds:.2f}s). Potential perimeter/zone transit."
            )

        start_time = min(ev1.utc_timestamp, ev2.utc_timestamp)
        end_time = max(ev1.utc_timestamp, ev2.utc_timestamp)

        return CorrelatedEvent(
            correlation_id=str(uuid4()),
            case_id=ev1.case_id,
            primary_channel=ev1.channel_id,
            secondary_channels=[ev2.channel_id],
            source_event_ids=[ev1.event_id, ev2.event_id],
            start_time_utc=start_time,
            end_time_utc=end_time,
            event_type=class1 or ev1.event_type.value,
            correlation_type=correlation_type,
            confidence=round(confidence, 3),
            explanation=explanation,
            metadata={
                "delta_time_seconds": round(dt_seconds, 3),
                "channel_pair": [ev1.channel_id, ev2.channel_id],
                "ev1_raw_timestamp": ev1.raw_timestamp,
                "ev2_raw_timestamp": ev2.raw_timestamp,
            },
        )

    def _find_insertion_index(self, target_time: datetime) -> int:
        """Binary search insertion index for chronological ordering."""
        low = 0
        high = len(self._buffer)
        while low < high:
            mid = (low + high) // 2
            if self._buffer[mid].utc_timestamp < target_time:
                low = mid + 1
            else:
                high = mid
        return low

    def _prune_buffer(self, latest_time: datetime) -> None:
        """Prune events older than window + allowed_lateness or if buffer exceeds max."""
        cutoff = latest_time.timestamp() - (self.window_seconds + self.allowed_lateness_seconds)
        self._buffer = [ev for ev in self._buffer if ev.utc_timestamp.timestamp() >= cutoff]

        # Enforce hard capacity ceiling
        if len(self._buffer) > self.max_buffer_size:
            # Drop oldest events to stay within bounded memory
            self._buffer = self._buffer[-self.max_buffer_size :]

    @staticmethod
    def _cosine_similarity(vec_a: list[float], vec_b: list[float]) -> float:
        """Compute cosine similarity between two feature vectors."""
        dot = sum(a * b for a, b in zip(vec_a, vec_b, strict=False))
        norm_a = math.sqrt(sum(a * a for a in vec_a))
        norm_b = math.sqrt(sum(b * b for b in vec_b))
        if norm_a <= 1e-9 or norm_b <= 1e-9:
            return 0.0
        return max(0.0, min(1.0, dot / (norm_a * norm_b)))
