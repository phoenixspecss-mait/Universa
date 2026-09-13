# OmniSight — AI Analysis Module (Stage 5)

This is the **AI Analysis** block from the Technical Approach slide:
`Detect persons, vehicles, objects` · `Motion & anomaly detection` — implemented
as a standalone, runnable prototype. **Deepfake/content-authenticity analysis is
intentionally excluded** per current team scope (only the hashing-based chain-of-
custody / tamper-evidence stage, already covered elsewhere, remains).

## What's included

| File | What it does | Model |
|---|---|---|
| `models/object_detector.py` | Detects & tracks persons, vehicles, objects across a video | YOLOv8n (Ultralytics, pretrained on COCO) |
| `models/face_detector.py` | Localizes faces (no recognition, no deepfake check) | OpenCV DNN (res10 SSD); auto-falls back to Haar cascade if offline |
| `models/motion_anomaly.py` | Motion detection + rolling z-score anomaly flagging | Classical CV (MOG2 background subtraction) |
| `models/semantic_search.py` | Natural-language search across multiple camera feeds at once ("person in red jacket near entrance") | OpenCLIP ViT-B/32 |
| `pipeline.py` | Orchestrates all stages above into one standardized JSON report per video | — |
| `utils/generate_test_video.py` | Generates a synthetic test clip so you can demo without real DVR footage | — |

## Why these choices (for your viva / judges)

- **YOLOv8n**: fastest COCO-pretrained detector that still runs acceptably on CPU —
  realistic for a forensic lab laptop with no GPU (see your Feasibility slide:
  "Hardware-Agnostic... runs on existing forensic laptops").
- **Face detector has an offline fallback**: forensic labs are often air-gapped;
  the DNN model auto-downloads once, but if there's no network it silently uses
  the Haar cascade that ships with OpenCV — the pipeline never hard-fails.
- **Motion/anomaly uses classical CV, not a black-box model**: for evidentiary
  admissibility (BSA §63) you want a method you can describe in plain language
  in court, not "the neural net flagged it."
- **Semantic search uses CLIP embeddings**: this is what gives you free-text,
  cross-camera search ("AI-powered smart search for all your cameras at once")
  without training a custom classifier per object type.
- **Everything outputs standardized JSON** — this is designed to plug straight
  into your Stage 6 (chain of custody logging) and Stage 7 (PDF/CSV/JSON export).

## Setup

```bash
pip install -r requirements.txt
```

First run of `object_detector.py` will auto-download `yolov8n.pt` (~6MB) from
Ultralytics. First run of `face_detector.py` will try to auto-download the DNN
face model (~10MB); if that fails (no internet) it uses the built-in Haar
cascade instead — no action needed either way.

## Quick demo (no real footage needed)

```bash
# 1. Generate a synthetic test video (moving "person"/"car" boxes + an anomaly burst)
python utils/generate_test_video.py --out sample_data/synthetic_test.mp4 --seconds 10

# 2. Run the full pipeline on it
python pipeline.py sample_data/synthetic_test.mp4 --every 3 --out-dir output
```

This produces `output/report_synthetic_test.json` with object/face/motion
results, plus `output/combined_summary.json`.

## Running on real (recovered) footage

```bash
# Single channel
python pipeline.py path/to/recovered_cam1.mp4 --every 5

# Multiple channels at once + cross-camera semantic search
python pipeline.py cam1.mp4 cam2.mp4 cam3.mp4 \
    --every 5 \
    --search-query "person carrying a bag near the door"
```

`--every N` controls how many frames are skipped between analyses — raise it
for long DVR exports where you don't need every single frame checked.

## Individual module usage

Each module also runs standalone for isolated testing:

```bash
python models/object_detector.py video.mp4 --out output/detections.json --every 5
python models/face_detector.py video.mp4 --out output/faces.json --every 5
python models/motion_anomaly.py video.mp4 --out output/motion.json --every 1
python models/semantic_search.py cam1.mp4 cam2.mp4 --query "white car" --out output/search.json
```

## Output schema (example, object detection)

```json
{
  "frame_index": 75,
  "timestamp_sec": 3.0,
  "detections": [
    {
      "label": "person",
      "confidence": 0.91,
      "bbox_xyxy": [296.0, 295.0, 336.0, 406.0],
      "class_id": 0,
      "track_id": 4
    }
  ]
}
```

`track_id` stays stable across frames within one video, so you can answer
"did this same person/vehicle reappear later" — the basis for "Connects
footage across cameras and events" on your innovation slide.

## Tested in this environment

`motion_anomaly.py` and the Haar fallback path in `face_detector.py` were run
end-to-end here against a generated synthetic clip and correctly flagged the
injected motion anomaly burst. `object_detector.py` and `semantic_search.py`
need their pretrained weights downloaded on first run (requires internet) —
logic was verified by syntax/compile check and code review; run the quick
demo above on your machine to see them execute live.

## Next steps / roadmap (things NOT in this prototype)

- Deepfake/video-authenticity analysis — explicitly out of scope for now.
- Swap YOLOv8n → YOLOv8m/l once GPU is available, for higher accuracy.
- Persist the semantic search index to disk (`SemanticSearchIndex.save/load`
  already implemented) so you don't re-embed footage on every run.
- Wire `pipeline.py`'s JSON output into the Stage 6 chain-of-custody hasher
  and Stage 7 PDF/CSV exporter.
