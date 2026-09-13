# Module #3 — Timeline & Integration Engineer
## NTRO Problem Statement 26150: Multi-Vendor DVR/NVR Forensic Analysis Tool
### Standardized Acquisition, Recovery, and Analysis of Surveillance Evidence

---

## 1. Executive Summary & Module Purpose

**Module #3 (Timeline & Integration)** is the central analytical and architectural backbone of the NTRO forensic surveillance analysis system. In multi-vendor DVR/NVR investigations, physical video feeds originate from heterogeneous hardware architectures (Hikvision, Dahua, CP Plus, Uniview, proprietary FAT/DOS DVRs) with drifting real-time clocks (RTC), missing timezones, proprietary container timestamps, and out-of-order segment recovery.

Module #3 solves this by:
1. **Normalizing Multi-Vendor Timestamps** into canonical, timezone-aware UTC without mutating source bitstreams or cryptographic hashes.
2. **Applying Auditable Clock Offsets & Linear Drift Corrections** strictly as derived layers with full forensic chain-of-custody logging.
3. **Constructing Unified Chronological Timelines** across multiple camera streams.
4. **Correlating Multi-Camera Events** using configurable sliding temporal windows, object class matching, and ReID feature vector cosine similarities—**while strictly enforcing forensic identity safeguards** (temporal proximity never asserts biometric identity certainty).
5. **Orchestrating Asynchronous Ingestion** with bounded queues, backpressure handling, deduplication, and graceful shutdown.
6. **Streaming Live Events** via WebSocket to frontend dashboards and providing court-ready forensic exports.

---

## 2. High-Level Architecture

```
                    ┌─────────────────────────────┐
                    │   #1 Core Engine (C++)      │ (Device Acquisition, Hashing)
                    └──────────────┬──────────────┘
                                   │ Frame Metadata & Hashes
                                   ▼
                    ┌─────────────────────────────┐
                    │ #2 Format Engine (Rust/FF)  │ (Codec Parsing, Frame Extraction)
                    └──────────────┬──────────────┘
                                   │ RawFrameMeta & PTS/DTS
                                   ▼
      ═══════════════════════════════════════════════════════════════════
      ║                  MODULE #3 (TIMELINE ENGINE)                    ║
      ║                                                                 ║
      ║  ┌───────────────────────────────────────────────────────────┐  ║
      ║  │              Async Ingestion Pipeline                     │  ║
      ║  │  Bounded asyncio.Queue + De-duplication + Backpressure    │  ║
      ║  └─────────────────────────────┬─────────────────────────────┘  ║
      ║                                │                                ║
      ║                                ▼                                ║
      ║  ┌───────────────────────────────────────────────────────────┐  ║
      ║  │               TimelineNormalizer                          │  ║
      ║  │  • Multi-Vendor Formats (Dahua, Hikvision, Epoch, FAT)    │  ║
      ║  │  • Timezone Conversion (Naive + Aware) → UTC              │  ║
      ║  │  • Fixed Offset & Extensible Drift Correction             │  ║
      ║  │  • Time Anomaly Detection (Time Jumps / Timeline Gaps)    │  ║
      ║  └─────────────────────────────┬─────────────────────────────┘  ║
      ║                                │ NormalizedFrameMeta / Event    ║
      ║                                ▼                                ║
      ║  ┌───────────────────────────────────────────────────────────┐  ║
      ║  │               Timeline Service & Storage                  │  ║
      ║  │  SQLite + SQLAlchemy 2.0 Async (Chronological Indices)    │  ║
      ║  └──────────────┬─────────────────────────────┬──────────────┘  ║
      ║                 │                             │                 ║
      ║                 ▼                             ▼                 ║
      ║  ┌───────────────────────────┐   ┌───────────────────────────┐  ║
      ║  │      EventCorrelator      │   │     Live WebSocket Bus    │  ║
      ║  │ • Sliding Temporal Window │   │ Broadcasts timeline and   │  ║
      ║  │ • Cross-Camera Tracking   │   │ correlated events to      │  ║
      ║  │ • Class/Embedding Match   │   │ connected clients         │  ║
      ║  │ • Identity-Safe Labels    │   │                           │  ║
      ║  └──────────────┬────────────┘   └───────────────────────────┘  ║
      ║                 │ CorrelatedEvent                               ║
      ║                 ▼                                               ║
      ║  ┌───────────────────────────────────────────────────────────┐  ║
      ║  │        FastAPI REST API & Integration Contracts          │  ║
      ║  └───────────────────────────────────────────────────────────┘  ║
      ═══════════════════════════════════════════════════════════════════
                        │                             │
        AIDetection     │                             │ Timeline Query & Export
        Payload         ▼                             ▼
      ┌────────────────────────┐      ┌────────────────────────────────┐
      │   #4 AI/ML Engine      │      │ #5 Reporting / #6 Flutter UI   │
      │ (Detections, Embeds)   │      │ (Forensic Reports, Dashboard)  │
      └────────────────────────┘      └────────────────────────────────┘
```

---

## 3. Data Flow

1. **Ingest**: Upstream modules (#1 Core Engine, #2 Codec Engine, or #4 AI/ML) POST metadata payloads to `/api/v1/ingest/...` or enqueue into `PipelineOrchestrator`.
2. **Deduplicate & Backpressure**: Incoming items pass through a bounded LRU cache (`DEDUPLICATION_CACHE_SIZE`). If queue fills (`PIPELINE_QUEUE_MAX_SIZE`), domain `PipelineQueueFullError` is raised (mapped to HTTP 429).
3. **Normalize**: `TimelineNormalizer` parses vendor string, applies channel timezone, converts to canonical UTC, and applies fixed offset/drift calibrations.
4. **Detect Anomalies**:
   - **Non-Monotonic Jump**: If timestamp drops backwards while frame index increases, flags `NON_MONOTONIC_TIME_JUMP`.
   - **Timeline Gap**: If interval between frames exceeds threshold (default 30s), flags `TIMELINE_GAP_DETECTED` (segregated from proven `RECORDING_GAP`).
   - **Filesystem Approximation**: FAT/DOS direntry timestamps are explicitly flagged as approximations unless verified by bitstream.
5. **Persist**: `TimelineEventModel` is written to SQLite via SQLAlchemy 2.0 async.
6. **Correlate**: `EventCorrelator` evaluates cross-camera detections within sliding window ($\pm \Delta W$, default 5s).
7. **Broadcast & Export**: Dispatches to active WebSocket subscribers and saves `CorrelatedEventModel` for court export.

---

## 4. Timestamp & Forensic Evidence Model

Forensic integrity requires maintaining three distinct layers:
```
[ RAW TIMESTAMP ]            [ NORMALIZED UTC ]              [ DERIVED CORRECTED UTC ]
Original string as-is   -->  Timezone resolved UTC  -->  T_final = T_utc + Offset + Drift
(NEVER MUTATED)              (Standardized baseline)         (Auditable correction)
```

- **Filesystem vs. Bitstream Segregation**: File modification times (`FILESYSTEM_MTIME`, `FILESYSTEM_CTIME`, `FAT_DIRENTRY`) are never silently assumed to represent video recording time. They are marked with `FILESYSTEM_TIMESTAMP_APPROXIMATION`.
- **Supported Formats**:
  - Unix Epoch (seconds & milliseconds)
  - ISO-8601 (UTC `Z` and explicit offsets `+HH:MM`)
  - Dahua: `YYYY-MM-DD HH:mm:ss`
  - Hikvision: `YYYYMMDDTHHmmssZ`
  - CCTV General: `DD/MM/YYYY HH:mm:ss`, `MM/DD/YYYY HH:mm:ss`
  - FAT 32-bit DOS Timestamps: High 16-bit date, low 16-bit time
  - Media-Relative Timing: Base segment timestamp + PTS ticks

---

## 5. Event Correlation & Forensic Safeguards

### Sliding Window Algorithm
For any target event at $t_{target}$ on Camera A, all events on Camera B within $[t_{target} - \Delta W, t_{target} + \Delta W]$ are evaluated.

### Evidentiary Safeguards
- **Identity Certainty is NEVER Asserted**: Temporal proximity alone only produces `TEMPORAL_COINCIDENCE` or `POSSIBLE_TRANSITION`.
- **Local `track_id` Handling**: By default, `track_id` assigned by single-camera object trackers is camera-local. Cameras sharing `track_id=1` will **never** increase identity confidence.
- **Global Track ID**: Only when upstream AI explicitly declares `is_global_track_id=True` is `TRACK_CONTINUITY` asserted ($\text{confidence} \ge 0.90$).
- **ReID Feature Embeddings**: When 128/512-dimensional visual embeddings are supplied, cosine similarity is computed:
  $$\text{CosSim}(\vec{u}, \vec{v}) = \frac{\vec{u} \cdot \vec{v}}{\|\vec{u}\| \|\vec{v}\|}$$
  If $\text{CosSim} \ge \text{threshold}$ (default 0.82), classification is `EMBEDDING_MATCH` with note: *"Indicates visual similarity, not definitive biometric identity."*

---

## 6. REST API Reference

All endpoints are prefixed with `/api/v1` (except `/health` and `/ws/live-timeline`).

| Method | Path | Summary | Expected Status |
|---|---|---|---|
| `POST` | `/api/v1/ingest/frame-metadata` | Ingest raw frame metadata from Core/Codec | 201 Created / 409 / 429 |
| `POST` | `/api/v1/ingest/ai-detection` | Ingest AI detections from Module #4 | 201 Created / 409 / 429 |
| `POST` | `/api/v1/timestamps/normalize` | Standalone timestamp normalization | 200 OK |
| `POST` | `/api/v1/events/correlate` | Trigger cross-camera correlation | 200 OK |
| `GET`  | `/api/v1/timeline/{case_id}` | Retrieve unified case timeline | 200 OK |
| `GET`  | `/api/v1/timeline/{case_id}/export` | Export court-ready forensic bundle | 200 OK |
| `GET`  | `/api/v1/timeline/{case_id}/{channel_id}` | Retrieve camera-specific timeline | 200 OK |
| `GET`  | `/api/v1/events/{event_id}` | Retrieve full forensic event details | 200 OK / 404 |
| `GET`  | `/api/v1/correlations/{case_id}` | Retrieve case cross-camera correlations | 200 OK |
| `GET`  | `/api/v1/pipeline/status` | Ingestion throughput & queue metrics | 200 OK |
| `GET`  | `/health` | Application health check probe | 200 OK |
| `WS`   | `/ws/live-timeline` | WebSocket live stream of events | 101 Switching Protocols |

---

## 7. How My Teammates Should Integrate Their Modules

Tomorrow when you connect your modules, use these integration contracts:

### Module #1: Core Engine (C++)
**Responsibility**: Device acquisition, disk reading, hardware identification, raw frame extraction, SHA-256 hashing.
- **Integration Options**:
  1. **HTTP Ingestion**: POST JSON to `/api/v1/ingest/frame-metadata`.
  2. **Python Adapter**: Subclass `CoreEngineInterface` in `src/integrations/core_engine.py`.
- **Payload You Must Provide**:
  ```json
  {
    "case_id": "CASE-2026-09-NTRO",
    "evidence_id": "EVD-HIK-01",
    "channel_id": "CAM01",
    "vendor_type": "HIKVISION",
    "raw_timestamp_str": "20260310T120005Z",
    "timestamp_format": "VENDOR_HIKVISION",
    "timestamp_source": "RECORDING_EMBEDDED",
    "timezone": "UTC",
    "frame_index": 101,
    "file_offset_bytes": 1048576,
    "file_path": "/evidence/cam01/stream.hik",
    "frame_hash_sha256": "4a5e1e5823a04e5fbc089851613b5e4f451f28b2de5d8e780c85c2c776fb0821"
  }
  ```

### Module #2: Codec / Format Engine (Rust / FFmpeg)
**Responsibility**: Parsing proprietary video containers (DHAV, HIK, DAV), stream decoding, PTS/DTS extraction, carved frame recovery.
- **Integration Options**:
  1. **HTTP Ingestion**: POST JSON to `/api/v1/ingest/frame-metadata`.
  2. **Python Adapter**: Subclass `CodecEngineInterface` in `src/integrations/codec_engine.py`.
- **Fields You Must Provide**:
  - `pts` & `dts`: Presentation/Decode timestamp ticks.
  - `timestamp_format`: Set to `"MEDIA_RELATIVE_PTS"` if providing PTS-derived timing.
  - `timestamp_source`: Set to `"DERIVED_PTS"`.

### Module #4: AI / ML Engine (Python / PyTorch / TensorRT)
**Responsibility**: Object detection (YOLO/RT-DETR), tracking (ByteTrack), ReID feature embeddings (OSNet).
- **Integration Options**:
  1. **HTTP Ingestion**: POST JSON to `/api/v1/ingest/ai-detection`.
  2. **Python Adapter**: Subclass `AIEngineInterface` in `src/integrations/ai_engine.py`.
- **Payload You Must Provide**:
  ```json
  {
    "case_id": "CASE-2026-09-NTRO",
    "evidence_id": "EVD-HIK-01",
    "channel_id": "CAM01",
    "utc_timestamp": "2026-03-10T12:00:00Z",
    "frame_index": 101,
    "object_class": "person",
    "confidence": 0.945,
    "bounding_box": { "xmin": 0.22, "ymin": 0.15, "xmax": 0.45, "ymax": 0.88 },
    "track_id": "trk_101",
    "is_global_track_id": false,
    "embedding": [0.088, -0.124, 0.452, 0.219, -0.055, 0.312, -0.188, 0.274]
  }
  ```
- **Crucial Rule**: Leave `is_global_track_id: false` for single-camera tracking. Only set `is_global_track_id: true` if your model has validated multi-camera ReID across camera streams.

### Module #5: Chain of Custody & Reporting
**Responsibility**: Audit trail verification, forensic reporting, Section 65B BSA certificate compilation.
- **Integration Options**:
  1. **HTTP Retrieval**: Call `GET /api/v1/timeline/{case_id}/export`.
  2. **Python Adapter**: Subclass `ReportingEngineInterface` in `src/integrations/reporting.py`.
- **Payload Module #3 Provides You**:
  - `total_events`, `total_correlations`, `total_corrections`.
  - Full list of events with raw timestamps, applied offsets, source hashes, and byte offsets.
  - `integrity_statement`: Cryptographic non-mutation declaration.

### Module #6: Flutter Frontend
**Responsibility**: Timeline visualizer, interactive multi-camera player, search, alert dashboard.
- **Integration Options**:
  1. **REST APIs**: `GET /api/v1/timeline/{case_id}`, `GET /api/v1/timeline/{case_id}/{channel_id}` with start/end time and limit/offset pagination.
  2. **Live Updates**: Connect WebSocket client to `ws://<host>:8000/ws/live-timeline?case_id={case_id}` (case isolation is strictly enforced; subscriptions require `case_id`).
- **WebSocket Messages Received**:
  ```json
  { "type": "timeline_event", "case_id": "CASE-1", "data": { ... } }
  { "type": "cross_camera_correlation", "case_id": "CASE-1", "correlation": { ... } }
  { "type": "timeline_anomaly", "case_id": "CASE-1", "data": { "channel_id": "CAM04", "anomalies": ["NON_MONOTONIC_TIME_JUMP"] } }
  ```

---

## 8. Setup & Running Instructions

### Prerequisites
- Python 3.11+
- Virtual environment recommended

### Installation
```bash
python -m pip install -r requirements.txt
```

### Running the End-to-End Demonstration
Execute the full standalone 5-camera demonstration in one command:
```bash
python demo/run_demo.py
```

### Running the Development Server
```bash
uvicorn src.main:app --host 0.0.0.0 --port 8000 --reload
```
API Documentation will be accessible at: `http://localhost:8000/docs`

### Running the Test Suite
Run all 54 comprehensive unit and regression tests with pytest:
```bash
python -m pytest tests/ -v
```

### Code Formatting & Linting
```bash
python -m ruff check src tests demo
python -m ruff format src tests demo
```
