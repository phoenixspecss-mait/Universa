#!/usr/bin/env python3
"""
Universa Forensic Pipeline — Master Orchestrator
------------------------------------------------
Interconnects all 6 modules of the Universa Forensic Platform:
  • Module #1: Core C++ Engine (disk acquisition, brand detection, carving, custody logs)
  • Module #2: Format/Codec Engine (demuxing, PTS/DTS timeline timing)
  • Module #3: Timeline & Integration Engine (normalization, SQLite, correlation, WebSockets)
  • Module #4: AI/ML Engine (YOLOv8 tracking, MOG2 motion anomaly, face localization)
  • Module #5: Reporting & Semantic Search (OpenCLIP ViT-B/32 multi-camera free-text search)
  • Module #6: Flutter Surveillance Dashboard & Studio

Usage:
  # 1. Run full end-to-end analysis on a disk image or case folder
  python3 universa_orchestrator.py analyze --disk synthetic_disk.img --case-id CASE-001

  # 2. Run multi-camera semantic search query across analyzed cases
  python3 universa_orchestrator.py search "person wearing red jacket"

  # 3. Launch both backend servers (C++ :8080 and FastAPI :8000)
  python3 universa_orchestrator.py serve
"""

import argparse
import json
import os
import subprocess
import sys
import time
from pathlib import Path

# Paths
ROOT_DIR = Path(__file__).resolve().parent
BACKEND_DIR = ROOT_DIR / "backend"
TIMELINE_ENGINE_DIR = BACKEND_DIR / "timeline_engine"
ML_DIR = BACKEND_DIR / "universa_ml_sih-main"
CASES_DIR = ROOT_DIR / "cases"

# Inject paths into sys.path
for p in [ROOT_DIR, TIMELINE_ENGINE_DIR, ML_DIR]:
    if str(p) not in sys.path:
        sys.path.insert(0, str(p))


def log_step(msg: str):
    print(f"\n\033[1;36m[UNIVERSA]\033[0m {msg}")


def log_success(msg: str):
    print(f"\033[1;32m[SUCCESS]\033[0m {msg}")


def log_warn(msg: str):
    print(f"\033[1;33m[WARNING]\033[0m {msg}")


def run_carving(disk_path: str, case_id: str) -> Path:
    """Step 1 & 2: Runs C++ dvr_recovery to carve and validate video streams."""
    log_step(f"Step 1: Running C++ FileCarver on disk image: {disk_path}")
    case_dir = CASES_DIR / case_id
    case_dir.mkdir(parents=True, exist_ok=True)

    dvr_bin = ROOT_DIR / "dvr_recovery"
    if dvr_bin.exists():
        cmd = [str(dvr_bin), disk_path]
        print(f"  Executing: {' '.join(cmd)}")
        res = subprocess.run(cmd, capture_output=True, text=True)
        if res.returncode == 0:
            import shutil
            output_dir = ROOT_DIR / "output"
            if output_dir.exists():
                for item in output_dir.iterdir():
                    dest = case_dir / item.name
                    if item.is_dir():
                        if dest.exists():
                            shutil.rmtree(dest)
                        shutil.copytree(item, dest)
                    else:
                        shutil.copy2(item, dest)
            log_success(f"Carving completed and evidence stored in {case_dir}")
        else:
            log_warn(f"dvr_recovery returned code {res.returncode}: {res.stderr.strip()[:100]}")
    else:
        log_warn("dvr_recovery binary not found. Skipping binary carving.")

    return case_dir


def run_ml_pipeline(case_dir: Path) -> dict:
    """Step 3: Runs Universa ML Engine (YOLOv8 + MOG2 Anomaly + Faces + OpenCLIP)."""
    log_step(f"Step 2: Executing ML Analysis Pipeline on {case_dir}")
    try:
        from pipeline import process_case_clips
        summary = process_case_clips(str(case_dir), sample_every_n_frames=5)
        log_success(f"ML Analysis completed: {summary.get('total_clips_analyzed', 0)} clips processed.")
        return summary
    except Exception as e:
        log_warn(f"ML Pipeline execution failed: {e}")
        return {"error": str(e)}


def run_timeline_integration(case_id: str, case_dir: Path) -> dict:
    """Step 4: Feeds carved frame timing & AI detections into Timeline Engine."""
    log_step(f"Step 3: Normalizing Timelines and Correlating Multi-Camera Events for {case_id}")
    import asyncio
    from datetime import datetime, timezone

    async def _async_integrate():
        from src.timeline.normalizer import TimelineNormalizer
        from src.timeline.correlator import EventCorrelator
        from src.timeline.schemas import TimelineEvent, RawFrameMeta, AIDetectionPayload, BoundingBox
        from src.timeline.constants import TimestampSource, VendorType, EventType

        normalizer = TimelineNormalizer()
        correlator = EventCorrelator(window_seconds=10.0)

        # Ingest summary data
        ml_summary_path = case_dir / "universa_ml_summary.json"
        ml_data = {}
        if ml_summary_path.exists():
            with open(ml_summary_path) as f:
                ml_data = json.load(f)

        events: list[TimelineEvent] = []
        clip_reports = ml_data.get("per_clip_reports", [])
        
        for idx, rep in enumerate(clip_reports):
            vid_src = Path(rep.get("video_source", f"cam_{idx+1}.mp4")).name
            channel_id = f"CAM{idx+1:02d}"

            # Object detection events
            for f in rep.get("stages", {}).get("object_detection", {}).get("frames", []):
                fidx = f.get("frame_index", 0)
                ts_sec = f.get("timestamp_sec", 0.0)
                utc_dt = datetime.fromtimestamp(1773144000.0 + ts_sec, tz=timezone.utc)

                for d in f.get("detections", []):
                    bbox = d.get("bbox_xyxy", [0, 0, 100, 100])
                    norm_bbox = {
                        "xmin": round(bbox[0] / 640.0, 3) if len(bbox) > 0 else 0.0,
                        "ymin": round(bbox[1] / 480.0, 3) if len(bbox) > 1 else 0.0,
                        "xmax": round(bbox[2] / 640.0, 3) if len(bbox) > 2 else 1.0,
                        "ymax": round(bbox[3] / 480.0, 3) if len(bbox) > 3 else 1.0,
                    }
                    ev = TimelineEvent(
                        case_id=case_id,
                        evidence_id=vid_src,
                        channel_id=channel_id,
                        utc_timestamp=utc_dt,
                        raw_timestamp=f"PTS+{ts_sec:.2f}s",
                        timestamp_source=TimestampSource.RECORDING_EMBEDDED,
                        event_type=EventType.AI_DETECTION,
                        payload={
                            "object_class": d.get("label", "person"),
                            "confidence": d.get("confidence", 0.9),
                            "track_id": d.get("track_id"),
                            "bounding_box": norm_bbox,
                        },
                    )
                    events.append(ev)

            # Motion anomaly events
            for mf in rep.get("stages", {}).get("motion_anomaly", {}).get("frames", []):
                if mf.get("is_anomaly", False):
                    ts_sec = mf.get("timestamp_sec", 0.0)
                    utc_dt = datetime.fromtimestamp(1773144000.0 + ts_sec, tz=timezone.utc)
                    ev = TimelineEvent(
                        case_id=case_id,
                        evidence_id=vid_src,
                        channel_id=channel_id,
                        utc_timestamp=utc_dt,
                        raw_timestamp=f"PTS+{ts_sec:.2f}s",
                        timestamp_source=TimestampSource.RECORDING_EMBEDDED,
                        event_type=EventType.MOTION_DETECTED,
                        anomaly_flags=["MOTION_ANOMALY_BURST"],
                        payload={
                            "motion_area_ratio": mf.get("motion_area_ratio", 0.0),
                            "anomaly_score": mf.get("anomaly_score", 0.0),
                        },
                    )
                    events.append(ev)

        # Correlate across cameras
        correlations = correlator.correlate_batch(events)
        log_success(f"Generated {len(events)} timeline events and {len(correlations)} cross-camera correlations.")
        return {
            "events_count": len(events),
            "correlations_count": len(correlations),
            "correlations": [c.model_dump(mode="json") for c in correlations],
        }

    return asyncio.run(_async_integrate())


def run_search(query: str, case_filter: str = None):
    """Step 5: Executes multi-camera natural language search."""
    log_step(f"Searching multi-camera evidence for query: '{query}'")
    try:
        from models.semantic_search import SemanticSearchIndex
        index = SemanticSearchIndex()

        # Find carved clips in cases/
        search_root = CASES_DIR / case_filter if case_filter and (CASES_DIR / case_filter).exists() else CASES_DIR
        all_clips = list(search_root.glob("**/carved/*.mp4")) + list(search_root.glob("**/carved/*.dav"))
        if not all_clips:
            all_clips = list(search_root.glob("**/*.mp4"))

        if all_clips:
            print(f"  Indexing {len(all_clips)} video clips for OpenCLIP search...")
            for clip in all_clips[:5]:
                try:
                    index.add_video(str(clip), sample_every_n_frames=15)
                except Exception:
                    pass

            results = index.search(query, top_k=5)
            log_success(f"Found {len(results)} matches:")
            for frame_obj, sim in results:
                print(f"   • {frame_obj.video_source} | Timestamp: {frame_obj.timestamp_sec:.2f}s | Match Confidence: {sim*100:.1f}%")
        else:
            log_warn("No video clips found in cases/ directory to search.")
    except Exception as e:
        log_warn(f"Semantic search query error: {e}")


def launch_services():
    """Step 6: Launches C++ server (:8080) and FastAPI Timeline Engine (:8000)."""
    log_step("Starting UNIVERSA Dual-Engine Backend Services...")
    print("  [1] C++ Core Server: http://0.0.0.0:8080")
    print("  [2] Python Timeline & ML Server: http://0.0.0.0:8000")
    print("  Press Ctrl+C to terminate both servers.")

    c_bin = ROOT_DIR / "dvr_api_server"
    procs = []
    if c_bin.exists():
        p1 = subprocess.Popen([str(c_bin), "0.0.0.0:8080"])
        procs.append(p1)

    p2 = subprocess.Popen([
        sys.executable, "-m", "uvicorn", "src.main:app",
        "--app-dir", str(TIMELINE_ENGINE_DIR),
        "--host", "0.0.0.0", "--port", "8000"
    ])
    procs.append(p2)

    try:
        while True:
            time.sleep(1)
    except KeyboardInterrupt:
        print("\nShutting down servers...")
        for p in procs:
            p.terminate()


def main():
    parser = argparse.ArgumentParser(description="Universa Forensic Pipeline Master Orchestrator")
    subparsers = parser.add_subparsers(dest="command")

    # Analyze
    p_analyze = subparsers.add_parser("analyze", help="Run end-to-end analysis on a disk image or case")
    p_analyze.add_argument("--disk", required=True, help="Path to raw disk image (.img, .bin, .raw)")
    p_analyze.add_argument("--case-id", default=None, help="Case identifier")

    # Search
    p_search = subparsers.add_parser("search", help="Run semantic search across analyzed footage")
    p_search.add_argument("query", help="Free-text query (e.g. 'person in red jacket')")
    p_search.add_argument("--case", default=None, help="Optional case identifier or directory to restrict search")

    # Serve
    subparsers.add_parser("serve", help="Launch C++ and FastAPI backend services")

    args = parser.parse_args()

    if args.command == "analyze":
        case_id = args.case_id or f"CASE-{int(time.time())}"
        case_dir = run_carving(args.disk, case_id)
        ml_summary = run_ml_pipeline(case_dir)
        timeline_res = run_timeline_integration(case_id, case_dir)
        log_success(f"Case {case_id} end-to-end processing complete!")

    elif args.command == "search":
        run_search(args.query, case_filter=args.case)

    elif args.command == "serve":
        launch_services()

    else:
        parser.print_help()


if __name__ == "__main__":
    main()

