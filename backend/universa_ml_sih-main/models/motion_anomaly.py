"""
motion_anomaly.py
------------------
Motion detection + lightweight anomaly scoring for surveillance footage.

Two layers, both classical CV (fast, explainable, no training data needed -
important for forensic admissibility, since the method must be describable
in a report/testimony):

1. MotionDetector: background-subtraction based motion mask + bounding
   regions of activity per frame. This is the raw "something moved here"
   signal.

2. AnomalyScorer: turns a rolling window of motion statistics into a
   z-score based anomaly flag - e.g. a sudden spike in activity area,
   or activity during a time window that's normally quiet for that
   camera. This is intentionally simple/interpretable for a hackathon
   prototype; swap in an autoencoder or optical-flow model later if the
   judges want to see it evolve.
"""

from dataclasses import dataclass, field
from typing import List, Dict, Tuple
from collections import deque

import cv2
import numpy as np


@dataclass
class MotionRegion:
    bbox_xyxy: List[float]
    area_px: float


@dataclass
class MotionFrameResult:
    frame_index: int
    timestamp_sec: float
    motion_area_ratio: float             # fraction of frame with motion, 0-1
    regions: List[MotionRegion] = field(default_factory=list)
    anomaly_score: float = 0.0           # z-score vs recent history
    is_anomaly: bool = False

    def to_dict(self) -> Dict:
        return {
            "frame_index": self.frame_index,
            "timestamp_sec": round(self.timestamp_sec, 3),
            "motion_area_ratio": round(self.motion_area_ratio, 5),
            "regions": [
                {"bbox_xyxy": [round(v, 1) for v in r.bbox_xyxy], "area_px": round(r.area_px, 1)}
                for r in self.regions
            ],
            "anomaly_score": round(self.anomaly_score, 3),
            "is_anomaly": self.is_anomaly,
        }


class MotionDetector:
    def __init__(self, min_area_px: int = 500, var_threshold: int = 40):
        """
        min_area_px: ignore motion blobs smaller than this (sensor
            noise / compression artifacts, common in recovered/corrupted
            DVR footage per the feasibility slide's fragmentation notes).
        var_threshold: sensitivity of the MOG2 background subtractor.
        """
        self.subtractor = cv2.createBackgroundSubtractorMOG2(
            history=500, varThreshold=var_threshold, detectShadows=True
        )
        self.min_area_px = min_area_px

    def process_frame(self, frame: np.ndarray, frame_index: int, timestamp_sec: float) -> MotionFrameResult:
        fg_mask = self.subtractor.apply(frame)
        # Remove shadow pixels (MOG2 marks them as 127) and denoise.
        _, thresh = cv2.threshold(fg_mask, 200, 255, cv2.THRESH_BINARY)
        thresh = cv2.morphologyEx(thresh, cv2.MORPH_OPEN, np.ones((3, 3), np.uint8))
        thresh = cv2.dilate(thresh, np.ones((5, 5), np.uint8), iterations=2)

        contours, _ = cv2.findContours(thresh, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
        h, w = frame.shape[:2]
        total_area = h * w

        regions = []
        motion_px = 0
        for c in contours:
            area = cv2.contourArea(c)
            if area < self.min_area_px:
                continue
            x, y, cw, ch = cv2.boundingRect(c)
            regions.append(MotionRegion(bbox_xyxy=[float(x), float(y), float(x + cw), float(y + ch)], area_px=area))
            motion_px += area

        result = MotionFrameResult(
            frame_index=frame_index,
            timestamp_sec=timestamp_sec,
            motion_area_ratio=motion_px / total_area if total_area else 0.0,
            regions=regions,
        )
        return result


class AnomalyScorer:
    """Rolling z-score anomaly detector over motion_area_ratio history.
    Stateful per camera stream - instantiate one per DVR channel."""

    def __init__(self, window_size: int = 150, z_threshold: float = 3.0, min_history: int = 30):
        self.window: deque = deque(maxlen=window_size)
        self.z_threshold = z_threshold
        self.min_history = min_history

    def score(self, motion_area_ratio: float) -> Tuple[float, bool]:
        if len(self.window) < self.min_history:
            self.window.append(motion_area_ratio)
            return 0.0, False

        arr = np.array(self.window)
        mean, std = arr.mean(), arr.std() + 1e-6
        z = (motion_area_ratio - mean) / std
        self.window.append(motion_area_ratio)
        return float(z), bool(z > self.z_threshold)


def process_video(video_path: str, sample_every_n_frames: int = 1):
    """Convenience generator combining motion detection + anomaly scoring
    for a single video/channel."""
    cap = cv2.VideoCapture(video_path)
    if not cap.isOpened():
        raise FileNotFoundError(f"Could not open video: {video_path}")
    fps = cap.get(cv2.CAP_PROP_FPS) or 25.0

    motion_detector = MotionDetector()
    anomaly_scorer = AnomalyScorer()

    frame_index = 0
    while True:
        ok, frame = cap.read()
        if not ok:
            break
        if frame_index % sample_every_n_frames == 0:
            timestamp_sec = frame_index / fps
            result = motion_detector.process_frame(frame, frame_index, timestamp_sec)
            z, is_anom = anomaly_scorer.score(result.motion_area_ratio)
            result.anomaly_score = z
            result.is_anomaly = is_anom
            yield result
        frame_index += 1
    cap.release()


if __name__ == "__main__":
    import argparse
    import json

    parser = argparse.ArgumentParser(description="Run motion + anomaly detection on a video.")
    parser.add_argument("video")
    parser.add_argument("--out", default="output/motion_anomaly.json")
    parser.add_argument("--every", type=int, default=1)
    args = parser.parse_args()

    all_results = [r.to_dict() for r in process_video(args.video, sample_every_n_frames=args.every)]
    anomaly_count = sum(1 for r in all_results if r["is_anomaly"])

    with open(args.out, "w") as f:
        json.dump(
            {"video": args.video, "frames_analyzed": len(all_results), "anomalies_flagged": anomaly_count,
             "results": all_results},
            f, indent=2,
        )
    print(f"Analyzed {len(all_results)} frames, flagged {anomaly_count} anomalies -> {args.out}")
