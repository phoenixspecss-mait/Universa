"""Timeline Service business logic layer.

Interacts with SQLAlchemy 2.0 models to query, filter, and export normalized
forensic timelines.
"""

import json
try:
    from datetime import UTC, datetime
except ImportError:
    from datetime import datetime, timezone
    UTC = timezone.utc

from uuid import uuid4

from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from src.timeline.constants import (
    CorrectionMethod,
    CorrelationType,
    EventType,
    TimestampSource,
)
from src.timeline.exceptions import EntityNotFoundError
from src.timeline.models import (
    CameraModel,
    CaseModel,
    CorrelatedEventModel,
    TimelineEventModel,
    TimestampCorrectionModel,
)
from src.timeline.schemas import (
    CorrelatedEvent,
    TimelineEvent,
    TimelineExportResponse,
    TimelineQuery,
    TimelineResponse,
    TimestampCorrection,
)


class TimelineService:
    """Forensic business logic service for cases, events, and correlations."""

    def __init__(self, session: AsyncSession) -> None:
        self.session = session

    async def get_or_create_case(
        self, case_id: str, case_number: str, title: str, description: str | None = None
    ) -> CaseModel:
        """Retrieve existing case or initialize a new forensic case."""
        stmt = select(CaseModel).where(CaseModel.id == case_id)
        result = await self.session.execute(stmt)
        case_obj = result.scalar_one_or_none()
        if case_obj:
            return case_obj

        new_case = CaseModel(
            id=case_id,
            case_number=case_number,
            title=title,
            description=description,
            created_at=datetime.now(UTC),
        )
        self.session.add(new_case)
        await self.session.flush()
        return new_case

    async def register_camera(
        self,
        case_id: str,
        channel_id: str,
        name: str,
        vendor_type: str,
        location: str | None = None,
        clock_offset_ms: float = 0.0,
        drift_rate_ppm: float = 0.0,
        tz_name: str = "UTC",
    ) -> CameraModel:
        """Register or update camera clock configuration."""
        stmt = select(CameraModel).where(
            CameraModel.case_id == case_id, CameraModel.channel_id == channel_id
        )
        result = await self.session.execute(stmt)
        camera = result.scalar_one_or_none()

        if camera:
            camera.name = name
            camera.vendor_type = vendor_type
            camera.location_description = location
            camera.clock_offset_ms = clock_offset_ms
            camera.drift_rate_ppm = drift_rate_ppm
            camera.timezone = tz_name
        else:
            camera = CameraModel(
                id=str(uuid4()),
                case_id=case_id,
                channel_id=channel_id,
                name=name,
                vendor_type=vendor_type,
                location_description=location,
                clock_offset_ms=clock_offset_ms,
                drift_rate_ppm=drift_rate_ppm,
                timezone=tz_name,
                created_at=datetime.now(UTC),
            )
            self.session.add(camera)

        await self.session.flush()

        # Update pipeline calibration cache (Fix #3)
        from src.timeline.pipeline import pipeline_instance

        pipeline_instance.set_camera_calibration(
            case_id=case_id,
            channel_id=channel_id,
            clock_offset_ms=clock_offset_ms,
            drift_rate_ppm=drift_rate_ppm,
            timezone=tz_name,
        )
        return camera

    async def query_timeline(self, query: TimelineQuery) -> TimelineResponse:
        """Retrieve ordered forensic timeline events matching query filters."""
        stmt = select(TimelineEventModel).where(TimelineEventModel.case_id == query.case_id)

        if query.channel_id:
            stmt = stmt.where(TimelineEventModel.channel_id == query.channel_id)

        if query.event_types:
            type_vals = [t.value for t in query.event_types]
            stmt = stmt.where(TimelineEventModel.event_type.in_(type_vals))

        if query.start_time:
            stmt = stmt.where(TimelineEventModel.utc_timestamp >= query.start_time)

        if query.end_time:
            stmt = stmt.where(TimelineEventModel.utc_timestamp <= query.end_time)

        # Count total matching
        count_stmt = select(func.count()).select_from(stmt.subquery())
        total = (await self.session.execute(count_stmt)).scalar() or 0

        # Order chronologically by normalized UTC timestamp
        stmt = (
            stmt.order_by(TimelineEventModel.utc_timestamp.asc())
            .limit(query.limit)
            .offset(query.offset)
        )
        result = await self.session.execute(stmt)
        db_events = result.scalars().all()

        events = [self._to_timeline_event(db_ev) for db_ev in db_events]

        return TimelineResponse(
            case_id=query.case_id,
            total_events=total,
            limit=query.limit,
            offset=query.offset,
            events=events,
        )

    async def get_event_by_id(self, event_id: str) -> TimelineEvent:
        """Fetch a specific timeline event by its UUID."""
        stmt = select(TimelineEventModel).where(TimelineEventModel.id == event_id)
        result = await self.session.execute(stmt)
        db_ev = result.scalar_one_or_none()
        if not db_ev:
            raise EntityNotFoundError(f"Timeline event '{event_id}' not found.")
        return self._to_timeline_event(db_ev)

    async def get_correlations_by_case(self, case_id: str) -> list[CorrelatedEvent]:
        """Fetch all cross-camera correlated events for a case."""
        stmt = (
            select(CorrelatedEventModel)
            .where(CorrelatedEventModel.case_id == case_id)
            .order_by(CorrelatedEventModel.start_time_utc.asc())
        )
        result = await self.session.execute(stmt)
        db_corrs = result.scalars().all()
        return [self._to_correlated_event(c) for c in db_corrs]

    async def record_timestamp_correction(
        self,
        case_id: str,
        channel_id: str,
        offset_ms: float,
        reason: str,
        source: str,
        method: CorrectionMethod = CorrectionMethod.FIXED_OFFSET,
        drift_rate_ppm: float = 0.0,
        reference_time: datetime | None = None,
    ) -> TimestampCorrection:
        """Create an audit record of camera clock correction."""
        correction = TimestampCorrectionModel(
            id=str(uuid4()),
            case_id=case_id,
            channel_id=channel_id,
            applied_offset_ms=offset_ms,
            correction_method=method.value,
            drift_rate_ppm=drift_rate_ppm,
            reference_timestamp=reference_time,
            reason=reason,
            source=source,
            created_at=datetime.now(UTC),
        )
        self.session.add(correction)
        await self.session.flush()

        # Update pipeline calibration cache (Fix #3)
        from src.timeline.pipeline import pipeline_instance

        pipeline_instance.set_camera_calibration(
            case_id=case_id,
            channel_id=channel_id,
            clock_offset_ms=offset_ms,
            drift_rate_ppm=drift_rate_ppm,
            reference_time_utc=reference_time,
        )

        return TimestampCorrection(
            id=correction.id,
            case_id=case_id,
            channel_id=channel_id,
            applied_offset_ms=offset_ms,
            correction_method=method,
            drift_rate_ppm=drift_rate_ppm,
            reference_timestamp=reference_time,
            reason=reason,
            source=source,
            created_at=correction.created_at,
        )

    async def get_timestamp_corrections(self, case_id: str) -> list[TimestampCorrection]:
        """Retrieve audit trail of all timestamp corrections for a case."""
        stmt = (
            select(TimestampCorrectionModel)
            .where(TimestampCorrectionModel.case_id == case_id)
            .order_by(TimestampCorrectionModel.created_at.asc())
        )
        result = await self.session.execute(stmt)
        records = result.scalars().all()

        return [
            TimestampCorrection(
                id=r.id,
                case_id=r.case_id,
                channel_id=r.channel_id,
                applied_offset_ms=r.applied_offset_ms,
                correction_method=CorrectionMethod(r.correction_method),
                drift_rate_ppm=r.drift_rate_ppm,
                reference_timestamp=r.reference_timestamp,
                reason=r.reason,
                source=r.source,
                created_at=r.created_at,
            )
            for r in records
        ]

    async def export_timeline(self, case_id: str) -> TimelineExportResponse:
        """Produce a complete forensic timeline export package for reporting."""
        # Query all events
        ev_stmt = (
            select(TimelineEventModel)
            .where(TimelineEventModel.case_id == case_id)
            .order_by(TimelineEventModel.utc_timestamp.asc())
        )
        events = [
            self._to_timeline_event(e)
            for e in (await self.session.execute(ev_stmt)).scalars().all()
        ]

        # Query all correlations
        correlations = await self.get_correlations_by_case(case_id)

        # Query corrections
        corrections = await self.get_timestamp_corrections(case_id)

        return TimelineExportResponse(
            case_id=case_id,
            total_events=len(events),
            total_correlations=len(correlations),
            total_corrections=len(corrections),
            events=events,
            correlations=correlations,
            timestamp_corrections=corrections,
        )

    @staticmethod
    def _to_timeline_event(db_ev: TimelineEventModel) -> TimelineEvent:
        """Convert ORM model to Pydantic domain schema."""
        return TimelineEvent(
            event_id=db_ev.id,
            case_id=db_ev.case_id,
            evidence_id=db_ev.evidence_id,
            channel_id=db_ev.channel_id,
            utc_timestamp=db_ev.utc_timestamp,
            raw_timestamp=db_ev.raw_timestamp,
            timestamp_source=TimestampSource(db_ev.timestamp_source),
            applied_offset_ms=db_ev.applied_offset_ms,
            event_type=EventType(db_ev.event_type),
            frame_index=db_ev.frame_index,
            file_offset_bytes=db_ev.file_offset_bytes,
            pts=db_ev.pts,
            dts=db_ev.dts,
            time_base_num=getattr(db_ev, "time_base_num", 1) or 1,
            time_base_den=getattr(db_ev, "time_base_den", 1000) or 1000,
            payload=json.loads(db_ev.payload_json) if db_ev.payload_json else {},
            source_reference=(
                json.loads(db_ev.source_reference_json) if db_ev.source_reference_json else {}
            ),
            anomaly_flags=(
                json.loads(db_ev.anomaly_flags_json) if db_ev.anomaly_flags_json else []
            ),
        )

    @staticmethod
    def _to_correlated_event(db_corr: CorrelatedEventModel) -> CorrelatedEvent:
        """Convert ORM model to Pydantic domain schema."""
        return CorrelatedEvent(
            correlation_id=db_corr.correlation_id,
            case_id=db_corr.case_id,
            primary_channel=db_corr.primary_channel,
            secondary_channels=(
                json.loads(db_corr.secondary_channels_json)
                if db_corr.secondary_channels_json
                else []
            ),
            source_event_ids=(
                json.loads(db_corr.source_event_ids_json) if db_corr.source_event_ids_json else []
            ),
            start_time_utc=db_corr.start_time_utc,
            end_time_utc=db_corr.end_time_utc,
            event_type=db_corr.event_type,
            correlation_type=CorrelationType(db_corr.correlation_type),
            confidence=db_corr.confidence,
            explanation=db_corr.explanation,
            metadata=json.loads(db_corr.metadata_json) if db_corr.metadata_json else {},
        )
