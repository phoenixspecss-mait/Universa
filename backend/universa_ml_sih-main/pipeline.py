"""
pipeline.py
-----------
Orchestrates the AI Analysis stage (block 5) of the OmniSight forensic
pipeline: runs object/person/vehicle detection, face detection, and
motion/anomaly detection over a recovered video, and (optionally) adds it
to a cross-camera semantic search index.

Deliberately EXCLUDES deepfake/tamper analysis of video content per
current team scope - that's separate from the "Tamper-Evident Audit
Trail & Chain of Custody" hashing step (stage 3), which is a different,
already-covered concern (file integrity, not content authenticity).

Output: a single JSON per video that's ready to feed into stage 6
(Chain of Custody logging) and stage 7 (Standardized Report export).

Usage:
    python pipeline.py path/to/video.mp4 --out output/report_cam1.json
    python pipeline.py cam1.mp4 cam2.mp4 --search-query "person carrying bag"
"""

import argparse
import json
import os
import sys
import time
from pathlib import Path
from typing import List, Optional, Dict, Any

try:
    from models.object_detector import ObjectDetector
    from models.face_detector import FaceDetector
    from models.motion_anomaly import process_video as process_motion_video
    from models.semantic_search import SemanticSearchIndex
except ImportError:
    try:
        from .models.object_detector import ObjectDetector
        from .models.face_detector import FaceDetector
        from .models.motion_anomaly import process_video as process_motion_video
        from .models.semantic_search import SemanticSearchIndex
    except (ImportError, ValueError):
        _ml_root = str(Path(__file__).resolve().parent)
        if _ml_root not in sys.path:
            sys.path.insert(0, _ml_root)
        from models.object_detector import ObjectDetector
        from models.face_detector import FaceDetector
        from models.motion_anomaly import process_video as process_motion_video
        from models.semantic_search import SemanticSearchIndex


def analyze_video(video_path: str, sample_every_n_frames: int = 5,
                   run_faces: bool = True) -> dict:
    """Runs the full (non-deepfake) AI analysis stack on one video and
    returns a standardized, JSON-serializable report dict."""

    print(f"\n=== Analyzing {video_path} ===")
    report = {
        "video_source": video_path,
        "sample_every_n_frames": sample_every_n_frames,
        "stages": {},
    }

    # --- Object / person / vehicle detection + tracking ---
    t0 = time.time()
    detector = ObjectDetector()
    object_frames = []
    for frame_result in detector.detect_and_track_video(video_path, sample_every_n_frames=sample_every_n_frames):
        object_frames.append(frame_result.to_dict())
    report["stages"]["object_detection"] = {
        "frames_analyzed": len(object_frames),
        "elapsed_sec": round(time.time() - t0, 2),
        "frames": object_frames,
    }
    print(f"  object detection: {len(object_frames)} frames in {time.time() - t0:.1f}s")

    # --- Face detection (localization only - no recognition/deepfake) ---
    if run_faces:
        t0 = time.time()
        face_detector = FaceDetector()
        face_frames = [r.to_dict() for r in face_detector.detect_video(video_path, sample_every_n_frames=sample_every_n_frames)]
        report["stages"]["face_detection"] = {
            "backend": face_detector.backend,
            "frames_analyzed": len(face_frames),
            "elapsed_sec": round(time.time() - t0, 2),
            "frames": face_frames,
        }
        print(f"  face detection ({face_detector.backend}): {len(face_frames)} frames in {time.time() - t0:.1f}s")

    # --- Motion + anomaly detection ---
    t0 = time.time()
    motion_frames = [r.to_dict() for r in process_motion_video(video_path, sample_every_n_frames=sample_every_n_frames)]
    anomaly_count = sum(1 for r in motion_frames if r["is_anomaly"])
    report["stages"]["motion_anomaly"] = {
        "frames_analyzed": len(motion_frames),
        "anomalies_flagged": anomaly_count,
        "elapsed_sec": round(time.time() - t0, 2),
        "frames": motion_frames,
    }
    print(f"  motion/anomaly: {len(motion_frames)} frames, {anomaly_count} anomalies in {time.time() - t0:.1f}s")

    # --- Summary block (goes straight into stage 7's report) ---
    report["summary"] = summarize(report)
    return report


def summarize(report: dict) -> dict:
    """Produces the human-readable rollup that goes into the final
    'Standardized Compliance & Export' PDF/CSV/JSON."""
    obj_frames = report["stages"].get("object_detection", {}).get("frames", [])
    label_counts = {}
    unique_track_ids = {}
    for f in obj_frames:
        for d in f["detections"]:
            label_counts[d["label"]] = label_counts.get(d["label"], 0) + 1
            if d["track_id"] is not None:
                unique_track_ids.setdefault(d["label"], set()).add(d["track_id"])

    face_frames = report["stages"].get("face_detection", {}).get("frames", [])
    total_faces = sum(f["face_count"] for f in face_frames)

    motion_frames = report["stages"].get("motion_anomaly", {}).get("frames", [])
    anomaly_timestamps = [f["timestamp_sec"] for f in motion_frames if f["is_anomaly"]]

    return {
        "detection_counts_by_label": label_counts,
        "unique_tracked_objects_by_label": {k: len(v) for k, v in unique_track_ids.items()},
        "total_face_detections": total_faces,
        "anomaly_timestamps_sec": anomaly_timestamps,
        "anomaly_count": len(anomaly_timestamps),
    }


def process_case_clips(case_dir: str, sample_every_n_frames: int = 5,
                       search_index: Optional[Any] = None, run_faces: bool = True) -> Dict[str, Any]:
    """Scans a forensic case directory (and carved/ subdirectory) for recovered
    video clips, executes the full AI analysis pipeline on each, optionally indexes
    them into OpenCLIP semantic search, and writes out reports into the case folder."""
    case_path = Path(case_dir)
    video_extensions = {".mp4", ".dav", ".avi", ".mkv", ".mov"}
    
    # Collect candidate clips: check carved/ first, then case root
    candidate_files: List[Path] = []
    carved_dir = case_path / "carved"
    if carved_dir.exists() and carved_dir.is_dir():
        for p in carved_dir.iterdir():
            if p.is_file() and p.suffix.lower() in video_extensions and "fragment" not in p.name.lower():
                # Ignore zero-byte or tiny corrupt clips
                if p.stat().st_size > 1024:
                    candidate_files.append(p)
    
    if not candidate_files:
        for p in case_path.iterdir():
            if p.is_file() and p.suffix.lower() in video_extensions:
                if p.stat().st_size > 1024:
                    candidate_files.append(p)

    candidate_files = sorted(candidate_files, key=lambda p: p.name)
    reports: List[Dict[str, Any]] = []

    for vid in candidate_files:
        try:
            rep = analyze_video(str(vid), sample_every_n_frames=sample_every_n_frames, run_faces=run_faces)
            reports.append(rep)
            if search_index is not None:
                try:
                    search_index.add_video(str(vid), sample_every_n_frames=max(sample_every_n_frames * 2, 10))
                except Exception as e:
                    print(f"Warning: Failed to index {vid} for semantic search: {e}")
        except Exception as e:
            print(f"Warning: Failed to analyze {vid}: {e}")

    summary = {
        "case_id": case_path.name,
        "case_dir": str(case_path),
        "total_clips_analyzed": len(reports),
        "clips": [r["video_source"] for r in reports],
        "per_clip_reports": reports,
        "combined_summary": {
            r["video_source"]: r.get("summary", {}) for r in reports
        },
    }

    # Save summary directly in case dir for cross-module consumption
    summary_path = case_path / "universa_ml_summary.json"
    try:
        with open(summary_path, "w") as f:
            json.dump(summary, f, indent=2)
    except Exception as e:
        print(f"Warning: Could not save summary to {summary_path}: {e}")

    return summary


def main():
    parser = argparse.ArgumentParser(description="OmniSight AI Analysis pipeline (object/face/motion, no deepfake).")
    parser.add_argument("videos", nargs="+", help="One or more recovered/decoded video files (one per DVR channel)")
    parser.add_argument("--every", type=int, default=5, help="Analyze every Nth frame")
    parser.add_argument("--no-faces", action="store_true", help="Skip face detection stage")
    parser.add_argument("--out-dir", default="output", help="Directory to write per-video JSON reports")
    parser.add_argument("--search-query", default=None, help="If set, also build a semantic search index across all videos and run this query")
    args = parser.parse_args()

    os.makedirs(args.out_dir, exist_ok=True)
    all_reports: List[dict] = []

    for video in args.videos:
        report = analyze_video(video, sample_every_n_frames=args.every, run_faces=not args.no_faces)
        out_path = os.path.join(args.out_dir, f"report_{os.path.splitext(os.path.basename(video))[0]}.json")
        with open(out_path, "w") as f:
            json.dump(report, f, indent=2)
        print(f"  -> wrote {out_path}")
        all_reports.append(report)

    # Combined summary across all channels (for the "unified dashboard" feature)
    combined_summary = {
        "channels_analyzed": [r["video_source"] for r in all_reports],
        "per_channel_summary": {r["video_source"]: r["summary"] for r in all_reports},
    }
    combined_path = os.path.join(args.out_dir, "combined_summary.json")
    with open(combined_path, "w") as f:
        json.dump(combined_summary, f, indent=2)
    print(f"\nCombined summary -> {combined_path}")

    # Optional: cross-camera semantic search
    if args.search_query:
        print(f"\nBuilding semantic search index for query: '{args.search_query}'")
        index = SemanticSearchIndex()
        for video in args.videos:
            index.add_video(video, sample_every_n_frames=max(args.every * 3, 15))
        results = index.search(args.search_query, top_k=10)
        search_out = {
            "query": args.search_query,
            "results": [{**f.to_meta_dict(), "similarity": round(s, 4)} for f, s in results],
        }
        search_path = os.path.join(args.out_dir, "search_results.json")
        with open(search_path, "w") as f:
            json.dump(search_out, f, indent=2)
        print(f"Search results -> {search_path}")


if __name__ == "__main__":
    main()
