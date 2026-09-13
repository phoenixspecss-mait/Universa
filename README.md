# DVR/NVR Forensic Recovery Pipeline

Forensic carving, chain of custody verification, timeline normalization, AI video analytics (OpenCV DNN + YOLOv4-tiny), report generation, and API server for CCTV/DVR/NVR disk images and raw video streams (C++17, OpenSSL, FFmpeg `libavcodec`/`libavformat`/`libavutil`, OpenCV `dnn`/`videoio`/`imgproc`, `cpp-httplib`).

## Architecture & Components

1. **AIPreprocessor (`backend/detect.c++`)**:
   - Detects vendor brand from binary signatures (`DHAV` for Dahua/Godrej, `ftypisom` for Hikvision, `DVR-MOCK` for synthetic test formats).
   - Strips proprietary wrappers to extract standard MP4 streams.
   - Generates SHA-256 cryptographic seal of extracted video data.

2. **FileCarver (`backend/file_carver.h`, `backend/file_carver.cpp`)**:
   - Performs buffered byte-by-byte disk image scanning (64KB sliding window with overlap margin).
   - Detects MP4/MOV ISO containers, raw H.264 Annex B stream headers (SPS/AUD start codes), and `DVR-MOCK` markers.
   - Carves candidate video chunks sequentially (`carved_0001.mp4`, etc.).
   - Routes corrupted/truncated fragments smaller than 4KB to `carved/fragments/`.

3. **ClipValidator (`backend/clip_validator.h`, `backend/clip_validator.cpp`)**:
   - Probes carved video files with FFmpeg (`avformat_open_input`, `avformat_find_stream_info`).
   - Decodes video frames to verify stream integrity without crashing on corrupted or garbage inputs.
   - Reports codec, resolution, and duration.

4. **AIDetector (`backend/ai_detector.h`, `backend/ai_detector.cpp`)**:
   - Uses OpenCV DNN with Darknet YOLOv4-tiny architecture.
   - Samples frames at configurable intervals (default: 2.0s) for rapid inference.
   - Detects persons, vehicles, animals, and objects with confidence filtering and Non-Maximum Suppression (NMS).
   - Produces per-frame timestamps, confidence scores, and bounding boxes.
   - Graceful fallback: if models are missing or OpenCV is disabled, logs a one-line warning and completes forensic carving without interruption.

5. **CustodyLog (`backend/custody_log.h`, `backend/custody_log.cpp`)**:
   - Cryptographic append-only chain of custody logger.
   - Computes SHA-256 hash chains linking each pipeline action (including carving, validation, and AI analysis) to the previous entry.
   - Flushes each entry to disk immediately in JSONL format to survive power loss or crashes.
   - Provides `verifyChain()` to detect tampering, missing entries, or sequencing violations.

6. **TimelineNormalizer (`backend/timeline_normalizer.h`, `backend/timeline_normalizer.cpp`)**:
   - Derives estimated chronological capture timestamps using sector offsets, base UTC timestamps, and cumulative clip durations.
   - Supports cross-image timeline merging and correlation for multi-camera/multi-DVR forensic analysis.

7. **ReportGenerator (`backend/report_generator.h`, `backend/report_generator.cpp`)**:
   - Generates forensic investigation reports in three independent formats:
     - `report.json`: Structured JSON containing case metadata, custody logs, evidence tables, timelines, and full AI detection frames.
     - `report.csv`: Tabular spreadsheet of carved video streams, validation statuses, and summary AI detection counts.
     - `report.pdf`: Standalone forensic PDF document with Case Summary, Custody Verification, Carved Evidence Table, Timeline, and AI Analysis Summary.

8. **API Server (`backend/api/api_server.cpp`)**:
   - Lightweight REST HTTP server using `cpp-httplib` with CORS enabled for Flutter frontend integration.
   - Endpoints for single/batch multipart uploads, case querying, AI detection summaries, and report retrieval.

9. **Synthetic Image Builder (`backend/synthetic_image_builder.cpp`)**:
   - CLI utility that constructs synthetic DVR disk images for testing.
   - Embeds intact MP4 clips, interleaved truncated fragments (< 4KB), and proprietary test markers.

---

## Build Instructions

### Prerequisites

#### Linux (Ubuntu / Debian)
```bash
sudo apt-get update
sudo apt-get install -y build-essential cmake pkg-config \
    libavformat-dev libavcodec-dev libavutil-dev libssl-dev ffmpeg libopencv-dev
```

#### Linux (Fedora / RHEL)
```bash
sudo dnf install -y gcc-c++ cmake pkgconfig \
    ffmpeg-free-devel openssl-devel ffmpeg opencv-devel
```

#### macOS (Homebrew)
```bash
brew install ffmpeg openssl@3 pkg-config cmake opencv
```

### AI Model Setup
Download the pretrained YOLOv4-tiny models (one-time setup):
```bash
./backend/models/download_models.sh
```
This downloads `yolov4-tiny.weights` (~24 MB), `yolov4-tiny.cfg`, and `coco.names` into `models/`.
If models are not downloaded, the pipeline gracefully skips AI detection without failing.

### Compilation

#### Using CMake:
```bash
mkdir -p build && cd build
cmake ..
cmake --build . -j$(nproc 2>/dev/null || sysctl -n hw.ncpu)
```
*Note: AI detection can be explicitly toggled using `-DENABLE_AI_DETECTION=OFF`.*

#### Using Makefile:
```bash
make -j4
```
This produces three binaries:
- `dvr_recovery` (Forensic recovery CLI)
- `dvr_api_server` (REST API server)
- `synthetic_image_builder` (Test disk generator)

---

## CLI Usage & Batch Processing

### 1. Generate Test Disk Images
```bash
# Generate a 20MB test disk image
./synthetic_image_builder synthetic_disk.img 20
```

### 2. Single Image Recovery
```bash
./dvr_recovery synthetic_disk.img
```
Output directory: `output/` containing `report.json`, `report.csv`, `report.pdf`, `custody_log.jsonl`, and `carved/`.

### 3. Multi-File Batch Recovery
Process multiple disk images in sequence:
```bash
./dvr_recovery disk1.img disk2.img disk3.img
```
Outputs are isolated into `output/disk1.img/`, `output/disk2.img/`, etc., followed by an aggregate batch summary table.

### 4. Directory Batch Recovery
Process all files inside a directory:
```bash
./dvr_recovery /path/to/evidence_folder
```
Corrupted or unreadable files in the batch are logged as `FAILED` without halting processing of valid files.

---

## API Server & Frontend Integration

### Starting the Server
```bash
# Default: binds to 0.0.0.0:8080
./dvr_api_server

# Custom port/host:
./dvr_api_server 9000 127.0.0.1
```

### REST API Endpoints

#### 1. Upload & Analyze Disk Image(s)
```bash
curl -X POST http://localhost:8080/api/analyze \
  -F "file=@synthetic_disk.img"
```
Returns HTTP 200 with the full JSON report and `case_id`.

For multi-file batch uploads:
```bash
curl -X POST http://localhost:8080/api/analyze \
  -F "file1=@disk1.img" \
  -F "file2=@disk2.img"
```
Returns a JSON array of per-file case reports.

#### 2. Query Case Status
```bash
curl http://localhost:8080/api/cases/{case_id}/status
```

#### 3. List All Processed Cases
```bash
curl http://localhost:8080/api/cases
```

#### 4. AI Detection Summary
```bash
curl http://localhost:8080/api/cases/{case_id}/ai_summary
```
Returns lightweight clip summary:
```json
[
  {
    "clip_path": "cases/UUID/carved/clip_001.mp4",
    "total_detections": 12,
    "distinct_classes": ["person", "car"]
  }
]
```

#### 5. Download Reports
```bash
# JSON report
curl http://localhost:8080/api/cases/{case_id}/report.json -o case_report.json

# CSV spreadsheet
curl http://localhost:8080/api/cases/{case_id}/report.csv -o case_report.csv

# Forensic PDF document
curl http://localhost:8080/api/cases/{case_id}/report.pdf -o case_report.pdf
```
