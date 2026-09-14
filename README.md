# UNIVERSA: CCTV/DVR/NVR Forensic Recovery & AI Surveillance Platform

[![C++17](https://img.shields.io/badge/C%2B%2B-17-blue.svg)](https://isocpp.org/)
[![Python 3.10+](https://img.shields.io/badge/Python-3.10%2B-green.svg)](https://www.python.org/)
[![Flutter](https://img.shields.io/badge/Flutter-3.x-02569B.svg)](https://flutter.dev/)
[![OpenCV](https://img.shields.io/badge/OpenCV-DNN%20%2B%20Darknet-orange.svg)](https://opencv.org/)
[![FFmpeg](https://img.shields.io/badge/FFmpeg-libavcodec%20%2F%20libavformat-red.svg)](https://ffmpeg.org/)
[![Compliance](https://img.shields.io/badge/Compliance-BSA%202023%20%C2%A763%20%7C%20ISO%2027037-purple.svg)]()

**UNIVERSA** is an enterprise-grade CCTV, DVR, and NVR forensic investigation system. It combines low-level bit-stream disk acquisition, byte-by-byte binary carving, proprietary wrapper stripping, cryptographic chain-of-custody tracking, multi-camera timeline synchronization, AI object detection, and natural language semantic video search into a unified command center.

---

## Architecture & System Modules

UNIVERSA integrates 6 specialized engines:

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                          UNIVERSA FORENSIC PLATFORM                             │
├──────────────────────────┬──────────────────────────┬───────────────────────────┤
│   MODULE 1: C++ CORE     │  MODULE 2: CODEC/TIMING  │  MODULE 3: TIMELINE & DB  │
│  • Bit-stream acquisition│  • FFmpeg probe & demux  │  • SQLite normalization   │
│  • Proprietary carving   │  • PTS/DTS timing engine │  • Multi-cam correlation  │
│  • SHA-256 custody chain │  • H.264 / HEVC / MP4    │  • FastAPI server (:8000) │
├──────────────────────────┼──────────────────────────┼───────────────────────────┤
│   MODULE 4: AI/ML VISION │  MODULE 5: SEMANTIC SRCH │  MODULE 6: FLUTTER STUDIO │
│  • YOLOv4-tiny / YOLOv8  │  • OpenCLIP ViT-B/32     │  • Surveillance dashboard │
│  • MOG2 motion anomaly   │  • Cross-camera queries  │  • Studio Pro & Timeline  │
│  • RetinaFace & FaceNet  │  • Visual embeddings     │  • Spatial Canvas graph   │
└──────────────────────────┴──────────────────────────┴───────────────────────────┘
```

1. **Module 1: Core C++ Forensic Engine (`backend/`)**
   - **Bit-Stream Imager (`disk_imager.cpp`)**: Forensically sound bit-stream acquisition adhering to ISO/IEC 27037:2012 and BSA 2023 §63.
   - **Brand Adapters (`adapters/`)**: Process-isolated adapters detecting vendor signatures (`DHAV` for Dahua/Godrej, `ftypisom` for Hikvision, `DVR-MOCK` for synthetic test formats) with automatic fail-safe recovery.
   - **File Carver (`file_carver.cpp`)**: High-performance buffered byte scanning identifying MP4/MOV ISO containers, raw H.264 Annex-B NAL units, and proprietary video containers. Automatically routes fragments < 4KB to isolated directories.
   - **Custody Logger (`custody_log.cpp`)**: Cryptographic SHA-256 and MD5 append-only audit trail logging every forensic operation with tamper verification (`verifyChain`).
   - **Report Generator (`report_generator.cpp`)**: Exports forensic investigation documentation in PDF, CSV, and JSON formats.

2. **Module 2: Format & Codec Engine (`src/`, `backend/clip_validator.cpp`)**
   - FFmpeg `libavformat` and `libavcodec` stream probing, corruption detection, resolution parsing, and frame decoding validation.
   - Preserves timestamps from embedded GOP headers and PTS/DTS offsets.

3. **Module 3: Timeline Normalization & SQLite Engine (`backend/timeline_engine/`)**
   - SQLite-backed timeline database normalizing fragmented capture times across non-synchronized multi-camera CCTV setups.
   - Cross-camera sliding-window event correlator detecting synchronous movements across channels.

4. **Module 4: AI / ML Vision Engine (`backend/universa_ml_sih-main/`)**
   - **C++ Native AI (`ai_detector.cpp`)**: Darknet YOLOv4-tiny via OpenCV DNN CPU acceleration with configurable sample rate and NMS threshold.
   - **Python Deep Analytics**: Ultralytics YOLOv8 object tracking, OpenCV MOG2 background-subtraction motion anomaly detector, and RetinaFace face localization.

5. **Module 5: Multi-Camera Semantic Search Engine**
   - OpenCLIP ViT-B/32 multimodal image-text embeddings allowing investigators to run natural language searches (*e.g. "person in red jacket", "white delivery van"*) across hours of carved footage without manual review.

6. **Module 6: Cyberpunk Surveillance Frontend (`frontend/`)**
   - Built with Flutter 3.x with dark forensic theme (`#080B10` background, electric cyan and emerald accents).
   - Features:
     - **Live Dashboard**: Active case metrics, verification badges, pipeline progress stepper.
     - **Studio Pro**: Synchronized multi-camera video playback grid with speed controls.
     - **Spatial Canvas**: Interactive 2D node graph visualizing physical camera placements and trajectory paths.
     - **Report Viewer**: Direct PDF preview and forensic metadata inspection.

---

## Proven Real-World Validation

The pipeline was benchmarked and validated against a **28.65 GB raw CCTV disk image** (`dvr_test_image.img`):

| Metric | Result |
| :--- | :--- |
| **Input Disk Size** | 28.65 GB (30,765,219,840 bytes) |
| **Input SHA-256 Seal** | `52825798b54411bae3c709b7efbb7b7d43f47477d138c9edbe95cec9d8c1dad7` |
| **Total Carved Candidate Streams** | **23,484 streams** |
| **Validated Playable Video Clips** | **97 video clips** (78 MP4 files + 19 H.264 streams) |
| **Video Resolutions Recovered** | 640×360, 480×368, 1280×720 (720p HD), **1920×1080 (1080p Full HD)** |
| **AI Detections (YOLO)** | 17 clips with confirmed objects (*person, car, truck, bus, bottle, clock, tie*) |
| **Chain of Custody Verification** | **PASSED** (101 verified SHA-256 chained entries) |
| **Reports Produced** | `report.pdf` (6.4 MB), `report.csv` (1.6 MB), `report.json` (14 MB) |

---

## Installation & Setup

### Prerequisites

#### macOS (Homebrew)
```bash
brew install ffmpeg openssl@3 pkg-config cmake opencv python@3.10
```

#### Ubuntu / Debian
```bash
sudo apt-get update
sudo apt-get install -y build-essential cmake pkg-config \
    libavformat-dev libavcodec-dev libavutil-dev libssl-dev ffmpeg libopencv-dev python3-venv
```

---

### 1. Download Pretrained AI Models
```bash
./backend/models/download_models.sh
```
Downloads `yolov4-tiny.weights` (~24 MB), `yolov4-tiny.cfg`, and `coco.names` into `models/`.

### 2. Compile C++ Binaries
```bash
make -j4
```
Builds three executable binaries:
* `dvr_recovery` — Standalone forensic recovery CLI
* `dvr_api_server` — C++ REST API server (:8080)
* `synthetic_image_builder` — Test disk image generator

### 3. Setup Python Virtual Environment
```bash
python3 -m venv .venv
source .venv/bin/activate
pip install -r backend/timeline_engine/requirements.txt
```

---

## Running the Platform

### Option A: Master Orchestrator (`universa_orchestrator.py`)

The master orchestrator provides a single unified CLI to run end-to-end analysis or launch services:

```bash
# 1. Run full end-to-end forensic analysis on a raw disk image
python3 universa_orchestrator.py analyze --disk /path/to/dvr_image.img --case-id CASE-001

# 2. Run multi-camera semantic search query
python3 universa_orchestrator.py search "person wearing red jacket"

# 3. Launch both backend servers concurrently (:8080 and :8000)
python3 universa_orchestrator.py serve
```

---

### Option B: Standalone CLI Recovery

Run the high-speed carver directly on any disk image or directory:

```bash
# Single image recovery
./dvr_recovery /path/to/evidence.img

# Multi-file or batch directory recovery
./dvr_recovery /path/to/evidence_folder/
```
Outputs are written to `output/` containing `report.json`, `report.csv`, `report.pdf`, `custody_log.jsonl`, and `carved/`.

---

### Option C: Dual Backend API Servers + Flutter GUI

#### 1. Start C++ Core Server (Port 8080)
```bash
./dvr_api_server 8080 0.0.0.0
```

#### 2. Start Python Timeline & ML Server (Port 8000)
```bash
.venv/bin/uvicorn src.main:app --app-dir backend/timeline_engine --host 0.0.0.0 --port 8000
```

#### 3. Launch the Flutter Surveillance App
```bash
cd frontend
flutter pub get
flutter run -d macos   # or: flutter run -d chrome
```

---

## REST API Reference

### C++ Core Server (`http://localhost:8080`)

| Method | Endpoint | Description |
| :--- | :--- | :--- |
| `POST` | `/api/analyze` | Multipart upload of raw disk images (`file=@image.img`). Returns full JSON case report. |
| `GET` | `/api/cases` | Returns metadata list of all processed cases (`case_meta.json`). |
| `GET` | `/api/cases/:id/status` | Queries case processing stage and progress percentage. |
| `GET` | `/api/cases/:id/ai_summary` | Returns lightweight summary of AI object detections per carved clip. |
| `GET` | `/api/cases/:id/report.json` | Downloads structured forensic JSON report. |
| `GET` | `/api/cases/:id/report.csv` | Downloads tabular CSV spreadsheet of carved evidence. |
| `GET` | `/api/cases/:id/report.pdf` | Streams standalone forensic PDF investigation report. |
| `POST` | `/api/acquire` | Bit-stream disk acquisition (`source` -> `destination`). |

### Python Timeline Engine (`http://localhost:8000`)

| Method | Endpoint | Description |
| :--- | :--- | :--- |
| `GET` | `/api/v1/timeline/:case_id` | Unified normalized timeline events across multi-camera feeds. |
| `GET` | `/api/v1/correlations/:case_id` | Cross-camera sliding window event correlations. |
| `POST` | `/api/v1/search/semantic` | Natural language semantic free-text search across video embeddings. |
| `GET` | `/api/v1/pipeline/status` | Real-time health, event queue throughput, and anomaly stats. |

---

## Forensic Integrity & Legal Compliance

* **Tamper-Evident SHA-256 Hashing**: Every raw input file, stripped stream, carved chunk, validation result, and AI detection is cryptographically sealed into an append-only hash chain. Any file alteration breaks the mathematical link and is immediately flagged by `verifyChain`.
* **ISO/IEC 27037:2012 Standard**: Ensures evidence handling, digital preservation, and verification workflows conform to international standards for digital evidence recovery.
* **BSA 2023 §63 Compliance**: Provides auditable, immutable verification logs admissible in forensic legal proceedings.

---

## License & Disclaimer

This software is developed for authorized forensic analysis, legal investigations, and data recovery on CCTV and surveillance systems. Users are responsible for complying with applicable local laws and evidentiary procedures.
