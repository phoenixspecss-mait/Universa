"""End-to-End Synthetic Demonstration Runner for Module #3.

Demonstrates:
1. Multi-vendor raw metadata ingestion (Hikvision, Dahua, UNV, CP Plus, FAT DVR)
2. Forensic timestamp normalization to UTC with clock offset calibration
3. Unified chronological timeline storage in SQLite
4. AI detection ingestion with camera-local track preservation
5. Multi-camera sliding-window event correlation without false identity assertions
6. REST API query, filtering, and court-ready export bundle verification
7. Live WebSocket event bus simulation
"""

import asyncio
import json
import sys
from pathlib import Path

from httpx import ASGITransport, AsyncClient

# Add project root to sys.path
sys.path.insert(0, str(Path(__file__).parent.parent))

from src.database import SessionFactory, init_db
from src.integrations.reporting import MockReportingEngine
from src.main import app
from src.timeline.normalizer import TimelineNormalizer
from src.timeline.pipeline import PipelineOrchestrator
from src.timeline.schemas import (
    AIDetectionPayload,
    RawFrameMeta,
)
from src.timeline.service import TimelineService


def load_synthetic_dataset() -> dict:
    """Helper to load synthetic dataset synchronously."""
    json_path = Path(__file__).parent / "synthetic_data.json"
    return json.loads(json_path.read_text(encoding="utf-8"))


async def run_end_to_end_demo() -> None:
    print("=" * 80)
    print(" NTRO PS-26150 — MULTI-VENDOR DVR/NVR FORENSIC ANALYSIS TOOL")
    print(" MODULE #3: TIMELINE & INTEGRATION ENGINEER — STANDALONE DEMO")
    print("=" * 80)

    # 1. Initialize Database
    print("\n[*] Initializing SQLite database schema (SQLAlchemy 2.0 async)...")
    await init_db()
    print("    [OK] Database initialized successfully.")

    # 2. Load Synthetic Dataset
    print("[*] Loading 5-camera deterministic synthetic dataset from synthetic_data.json...")
    data = load_synthetic_dataset()
    print(
        f"    [OK] Loaded case '{data['case']['case_number']}' with {len(data['cameras'])} cameras."
    )

    # 3. Register Case and Cameras
    async with SessionFactory() as session:
        service = TimelineService(session)
        case_info = data["case"]
        await service.get_or_create_case(
            case_id=case_info["case_id"],
            case_number=case_info["case_number"],
            title=case_info["title"],
            description=case_info["description"],
        )

        for cam in data["cameras"]:
            await service.register_camera(
                case_id=case_info["case_id"],
                channel_id=cam["channel_id"],
                name=cam["name"],
                vendor_type=cam["vendor_type"],
                location=cam["location"],
                clock_offset_ms=cam["clock_offset_ms"],
                drift_rate_ppm=cam["drift_rate_ppm"],
                tz_name=cam["timezone"],
            )

        for corr in data["corrections"]:
            await service.record_timestamp_correction(
                case_id=corr["case_id"],
                channel_id=corr["channel_id"],
                offset_ms=corr["applied_offset_ms"],
                reason=corr["reason"],
                source=corr["source"],
            )
        await session.commit()
    print("    [OK] Registered case, camera topologies, and clock offset calibrations.")

    # 4. Demonstrate Forensic Timestamp Normalization
    print("\n" + "-" * 80)
    print(" PART 1: FORENSIC TIMESTAMP NORMALIZATION ENGINE")
    print("-" * 80)
    normalizer = TimelineNormalizer()

    for cam in data["cameras"]:
        ch = cam["channel_id"]
        # Find frame for this camera
        sample_frame = next(f for f in data["raw_frames"] if f["channel_id"] == ch)
        res = normalizer.normalize(
            raw_timestamp_str=sample_frame["raw_timestamp_str"],
            timestamp_format=sample_frame["timestamp_format"],
            timestamp_source=sample_frame["timestamp_source"],
            supplied_timezone=sample_frame["timezone"],
            offset_ms=cam["clock_offset_ms"],
        )

        print(f"  Camera {ch:5s} ({cam['vendor_type']:9s} | {cam['location']}):")
        print(f"    Raw Timestamp       : {res.raw_timestamp}")
        print(f"    Timestamp Source    : {res.timestamp_source.value}")
        print(f"    Applied Offset      : {res.applied_offset_ms:+.1f} ms")
        print(
            f"    Normalized UTC Time : {res.utc_timestamp.isoformat() if res.utc_timestamp else 'FAILED'}"
        )
        if res.anomaly_flags:
            print(f"    Forensic Anomalies  : {res.anomaly_flags}")
        print()

    # 5. Ingest Raw Frames and AI Detections through Pipeline
    print("-" * 80)
    print(" PART 2: ASYNC PIPELINE ORCHESTRATION & INGESTION")
    print("-" * 80)
    pipeline = PipelineOrchestrator()
    await pipeline.start()

    # Collect broadcast events for verification
    broadcasted_events: list[dict] = []
    pipeline.register_broadcast_listener(lambda msg: broadcasted_events.append(msg))

    print("[*] Streaming raw frame metadata from 5 cameras into bounded async queue...")
    for frame_dict in data["raw_frames"]:
        frame_obj = RawFrameMeta(**frame_dict)
        await pipeline.submit_raw_frame(frame_obj)

    print("[*] Streaming AI object detections (persons, vehicles) into pipeline...")
    for ai_dict in data["ai_detections"]:
        ai_obj = AIDetectionPayload(**ai_dict)
        await pipeline.submit_ai_detection(ai_obj)

    # Allow background worker to process queue
    print("[*] Awaiting background worker processing and correlation...")
    await asyncio.sleep(1.5)
    await pipeline.stop()

    status_metrics = pipeline.get_status()
    print(
        f"    [OK] Ingestion complete. Processed: {status_metrics.processed_events_count}, "
        f"Dropped: {status_metrics.dropped_events_count}, Anomalies: {status_metrics.detected_anomalies_count}"
    )

    # 6. Multi-Camera Event Correlation Verification
    print("\n" + "-" * 80)
    print(" PART 3: MULTI-CAMERA EVENT CORRELATION (IDENTITY SAFEGUARD)")
    print("-" * 80)
    async with SessionFactory() as session:
        service = TimelineService(session)
        correlations = await service.get_correlations_by_case(data["case"]["case_id"])

    print(f"[*] Discovered {len(correlations)} cross-camera event correlations:\n")
    for idx, corr in enumerate(correlations, start=1):
        print(f"  Correlation #{idx}: [{corr.correlation_type.value}]")
        print(f"    Channels    : {corr.primary_channel} <--> {', '.join(corr.secondary_channels)}")
        print(
            f"    Time Range  : {corr.start_time_utc.isoformat()} to {corr.end_time_utc.isoformat()}"
        )
        print(f"    Confidence  : {corr.confidence:.3f}")
        print(f"    Explanation : {corr.explanation}")
        print("    Forensic Integrity Guardrail: Identity certainty is NOT asserted.")
        print()

    # 7. FastAPI REST API Verification
    print("-" * 80)
    print(" PART 4: FASTAPI REST API VERIFICATION (via ASGITransport)")
    print("-" * 80)
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://testserver") as client:
        # Health check
        resp = await client.get("/health")
        print(f"  GET /health -> Status {resp.status_code} | {resp.json()['status']}")

        # Query unified timeline
        case_id = data["case"]["case_id"]
        resp = await client.get(f"/api/v1/timeline/{case_id}?limit=10")
        t_data = resp.json()
        print(
            f"  GET /api/v1/timeline/{case_id} -> Status {resp.status_code} | Total Events: {t_data['total_events']}"
        )

        # Query camera CAM01
        resp = await client.get(f"/api/v1/timeline/{case_id}/CAM01")
        c_data = resp.json()
        print(
            f"  GET /api/v1/timeline/{case_id}/CAM01 -> Status {resp.status_code} | Camera Events: {c_data['total_events']}"
        )

        # Query correlations
        resp = await client.get(f"/api/v1/correlations/{case_id}")
        corr_data = resp.json()
        print(
            f"  GET /api/v1/correlations/{case_id} -> Status {resp.status_code} | Total Correlations: {len(corr_data)}"
        )

        # Query forensic export
        resp = await client.get(f"/api/v1/timeline/{case_id}/export")
        export_data = resp.json()
        print(f"  GET /api/v1/timeline/{case_id}/export -> Status {resp.status_code}")
        print(f"    Integrity Statement: {export_data['integrity_statement'][:75]}...")

    # 8. Module #5 Forensic Report Consumption Verification
    print("\n" + "-" * 80)
    print(" PART 5: MODULE #5 (CHAIN OF CUSTODY & REPORTING) INTEGRATION CHECK")
    print("-" * 80)
    async with SessionFactory() as session:
        service = TimelineService(session)
        export_bundle = await service.export_timeline(case_id)
        mock_reporting = MockReportingEngine()
        report_summary = await mock_reporting.build_court_report(export_bundle)

    print("  MockReportingEngine parsed export bundle successfully:")
    print(f"    Report Title                : {report_summary['report_title']}")
    print(f"    Forensic Integrity Status   : {report_summary['forensic_integrity_status']}")
    print(f"    Section 65B Ready           : {report_summary['section_65b_certificate_ready']}")
    print(f"    Total Events Audited        : {report_summary['total_timeline_events']}")
    print(f"    Verified Bitstream Events   : {report_summary['verified_events_count']}")
    print(f"    Clock Calibrations Documented: {report_summary['clock_calibrations_count']}")

    print("\n" + "=" * 80)
    print(" [SUCCESS] COMPLETE MODULE #3 STANDALONE DEMONSTRATION EXECUTED SUCCESSFULLY")
    print("=" * 80)


if __name__ == "__main__":
    asyncio.run(run_end_to_end_demo())
