import hashlib
import json
import subprocess
from pathlib import Path

import requests

VIDEO = Path(r"C:\Users\Jayesh\Downloads\gettyimages-1499035459-640_adpp.mp4")
API = "http://127.0.0.1:8000/api/v1/ingest/frame-metadata"

CASE_ID = "GETTY-CCTV-PTS-TEST-FIXED"
EVIDENCE_ID = "getty_cctv_mp4"
CHANNEL_ID = "CAM-01"

REFERENCE_START = "2026-09-10T12:00:00+00:00"


def sha256_file(path):
    h = hashlib.sha256()

    with path.open("rb") as f:
        while chunk := f.read(1024 * 1024):
            h.update(chunk)

    return h.hexdigest()


def get_frames():
    command = [
        "ffprobe",
        "-v",
        "error",
        "-select_streams",
        "v:0",
        "-show_entries",
        "frame=pts,pts_time,dts,dts_time,best_effort_timestamp_time",
        "-of",
        "json",
        str(VIDEO),
    ]

    result = subprocess.run(
        command,
        capture_output=True,
        text=True,
        check=True,
    )

    return json.loads(result.stdout)["frames"]


def main():
    if not VIDEO.exists():
        raise FileNotFoundError(VIDEO)

    print("Video:", VIDEO)
    print("SHA256:", sha256_file(VIDEO))

    frames = get_frames()

    print("Frames found:", len(frames))
    print()

    success = 0
    failed = 0

    for frame_index, frame in enumerate(frames):
        pts = frame.get("pts")
        dts = frame.get("dts")

        payload = {
            "case_id": CASE_ID,
            "evidence_id": EVIDENCE_ID,
            "channel_id": CHANNEL_ID,
            "vendor_type": "GENERIC",
            "raw_timestamp_str": REFERENCE_START,
            "timestamp_format": "MEDIA_RELATIVE_PTS",
            "timestamp_source": "DERIVED_PTS",
            "timezone": "UTC",
            "frame_index": frame_index,
            "file_offset_bytes": None,
            "pts": pts,
            "dts": dts,
            "time_base_num": 1,
            "time_base_den": 30000,
            "file_path": str(VIDEO),
            "frame_hash_sha256": None,
        }

        try:
            response = requests.post(API, json=payload, timeout=10)

            if response.status_code in (200, 201, 202):
                success += 1
            else:
                failed += 1

                if failed <= 5:
                    print(
                        "FAILED",
                        frame_index,
                        response.status_code,
                        response.text,
                    )

        except requests.RequestException as exc:
            failed += 1

            if failed <= 5:
                print("REQUEST ERROR:", frame_index, exc)

        if (frame_index + 1) % 100 == 0:
            print(f"Processed {frame_index + 1}/{len(frames)} | success={success} failed={failed}")

    print()
    print("=" * 60)
    print("RESULT")
    print("=" * 60)
    print("Total frames:", len(frames))
    print("Successful:", success)
    print("Failed:", failed)


if __name__ == "__main__":
    main()
