"""
object_detector.py
-------------------
Detects persons, vehicles, and general objects in DVR/NVR footage frames.

Uses YOLOv8 (Ultralytics), pretrained on COCO. This is the "AI Object & Face
Detection" block of the OmniSight pipeline (stage 5 in the technical
approach diagram) MINUS deepfake detection, per current scope.

Design notes for the team:
- Model is loaded once and reused across frames/streams (cheap inference).
- Output is a standardized JSON-serializable schema so it plugs directly
  into the "Standardized Compliance & Export (PDF/CSV/JSON)" stage later.
- COCO class ids we care about most for forensic surveillance work:
    0: person, 1: bicycle, 2: car, 3: motorcycle, 5: bus, 7: truck
  Everything else from COCO is still returned but flagged as "other".
"""

from dataclasses import dataclass, field
from typing import List, Dict, Optional
import time

import cv2
import numpy as np

try:
    from ultralytics import YOLO
    _HAS_ULTRALYTICS = True
except ImportError:
    YOLO = None
    _HAS_ULTRALYTICS = False

# Classes we specifically care about for surveillance/forensic review.
# (COCO class id -> normalized label used in reports)
PRIORITY_CLASSES = {
    0: "person",
    1: "bicycle",
    2: "car",
    3: "motorcycle",
    5: "bus",
    7: "truck",
}


@dataclass
class Detection:
    label: str
    confidence: float
    bbox_xyxy: List[float]           # [x1, y1, x2, y2] in pixel coords
    class_id: int
    is_priority: bool = True
    track_id: Optional[int] = None    # populated when tracking is enabled


@dataclass
class FrameResult:
    frame_index: int
    timestamp_sec: float
    detections: List[Detection] = field(default_factory=list)

    def to_dict(self) -> Dict:
        return {
            "frame_index": self.frame_index,
            "timestamp_sec": round(self.timestamp_sec, 3),
            "detections": [
                {
                    "label": d.label,
                    "confidence": round(d.confidence, 4),
                    "bbox_xyxy": [round(v, 1) for v in d.bbox_xyxy],
                    "class_id": d.class_id,
                    "track_id": d.track_id,
                }
                for d in self.detections
            ],
        }


class ObjectDetector:
    """Wraps a YOLOv8 model for person/vehicle/object detection with
    optional multi-object tracking (for 'connects footage across cameras
    and events' style continuity within a single stream)."""

    def __init__(self, model_path: str = "yolov8n.pt", conf_threshold: float = 0.35,
                 device: str = "cpu"):
        """
        model_path: any Ultralytics-compatible weights file. 'yolov8n.pt'
            (nano) is the right default for a hackathon prototype - fast on
            CPU. Swap to 'yolov8m.pt' / 'yolov8l.pt' for higher accuracy
            once you have GPU access.
        conf_threshold: minimum confidence to keep a detection.
        device: 'cpu' or 'cuda:0'
        """
        self.conf_threshold = conf_threshold
        self.device = device
        self.model = None

        if _HAS_ULTRALYTICS:
            try:
                self.model = YOLO(model_path)
            except Exception as e:
                print(f"Notice: Could not load YOLO model '{model_path}': {e}. Running in fallback mode.")
        else:
            print("Notice: Ultralytics not installed. Running ObjectDetector in fallback mode.")

    def detect_frame(self, frame: np.ndarray, frame_index: int, timestamp_sec: float) -> FrameResult:
        """Run detection on a single BGR frame (as read by cv2.VideoCapture)."""
        frame_result = FrameResult(frame_index=frame_index, timestamp_sec=timestamp_sec)
        if self.model is None:
            return frame_result

        results = self.model.predict(
            frame, conf=self.conf_threshold, device=self.device, verbose=False
        )[0]

        for box in results.boxes:
            cls_id = int(box.cls[0])
            conf = float(box.conf[0])
            xyxy = box.xyxy[0].tolist()
            label = PRIORITY_CLASSES.get(cls_id, self.model.names.get(cls_id, "object"))
            frame_result.detections.append(
                Detection(
                    label=label,
                    confidence=conf,
                    bbox_xyxy=xyxy,
                    class_id=cls_id,
                    is_priority=cls_id in PRIORITY_CLASSES,
                )
            )
        return frame_result

    def detect_and_track_video(self, video_path: str, sample_every_n_frames: int = 1,
                                persist_tracks: bool = True):
        """
        Runs detection + tracking (ByteTrack, bundled with Ultralytics)
        across an entire recovered video file.
        """
        cap = cv2.VideoCapture(video_path)
        if not cap.isOpened():
            raise FileNotFoundError(f"Could not open video: {video_path}")

        fps = cap.get(cv2.CAP_PROP_FPS) or 25.0
        total_frames = int(cap.get(cv2.CAP_PROP_FRAME_COUNT) or 0)

        if self.model is None:
            # Fallback: yield empty frame results for sampled frames
            frame_index = 0
            while True:
                ok, _ = cap.read()
                if not ok:
                    break
                if frame_index % sample_every_n_frames == 0:
                    yield FrameResult(frame_index=frame_index, timestamp_sec=frame_index / fps)
                frame_index += 1
            cap.release()
            return

        frame_index = 0
        track_stream = self.model.track(
            source=video_path,
            conf=self.conf_threshold,
            device=self.device,
            persist=persist_tracks,
            stream=True,
            verbose=False,
        )

        for result in track_stream:
            if frame_index % sample_every_n_frames == 0:
                timestamp_sec = frame_index / fps
                frame_result = FrameResult(frame_index=frame_index, timestamp_sec=timestamp_sec)
                if result.boxes is not None:
                    for box in result.boxes:
                        cls_id = int(box.cls[0])
                        conf = float(box.conf[0])
                        xyxy = box.xyxy[0].tolist()
                        track_id = int(box.id[0]) if box.id is not None else None
                        label = PRIORITY_CLASSES.get(cls_id, self.model.names.get(cls_id, "object"))
                        frame_result.detections.append(
                            Detection(
                                label=label,
                                confidence=conf,
                                bbox_xyxy=xyxy,
                                class_id=cls_id,
                                is_priority=cls_id in PRIORITY_CLASSES,
                                track_id=track_id,
                            )
                        )
                yield frame_result
            frame_index += 1

        cap.release()


if __name__ == "__main__":
    # Quick smoke test / usage example.
    import argparse
    import json

    parser = argparse.ArgumentParser(description="Run object/person/vehicle detection on a video.")
    parser.add_argument("video", help="Path to recovered/decoded video file")
    parser.add_argument("--out", default="output/detections.json", help="Output JSON path")
    parser.add_argument("--every", type=int, default=5, help="Analyze every Nth frame")
    args = parser.parse_args()

    detector = ObjectDetector()
    all_results = []
    start = time.time()
    for frame_result in detector.detect_and_track_video(args.video, sample_every_n_frames=args.every):
        all_results.append(frame_result.to_dict())
    elapsed = time.time() - start

    with open(args.out, "w") as f:
        json.dump({"video": args.video, "frames_analyzed": len(all_results), "results": all_results}, f, indent=2)

    print(f"Analyzed {len(all_results)} frames in {elapsed:.1f}s -> {args.out}")
