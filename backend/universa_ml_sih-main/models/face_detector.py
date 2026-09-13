"""
face_detector.py
-----------------
Face detection (NOT recognition, NOT deepfake analysis - out of scope for
now, per team decision). This only localizes faces in a frame so they can
be logged, blurred/redacted, or handed off to a later identification stage
if the team decides to add one.

Uses OpenCV's DNN face detector (res10 SSD, Caffe model) - lightweight,
no GPU required, ships with opencv-python's data or can be downloaded
once and cached locally. Falls back to Haar cascade (built into OpenCV,
zero extra downloads) if the DNN weights aren't available, so the
pipeline never hard-fails in an offline demo environment.
"""

from dataclasses import dataclass, field
from typing import List, Dict, Optional
import os
import urllib.request

import cv2
import numpy as np

# Cached model file locations
_MODEL_DIR = os.path.join(os.path.dirname(__file__), "weights")
_PROTOTXT_PATH = os.path.join(_MODEL_DIR, "deploy.prototxt")
_CAFFEMODEL_PATH = os.path.join(_MODEL_DIR, "res10_300x300_ssd_iter_140000.caffemodel")

_PROTOTXT_URL = (
    "https://raw.githubusercontent.com/opencv/opencv/master/samples/dnn/face_detector/deploy.prototxt"
)
_CAFFEMODEL_URL = (
    "https://raw.githubusercontent.com/opencv/opencv_3rdparty/dnn_samples_face_detector_20170830/"
    "res10_300x300_ssd_iter_140000.caffemodel"
)


@dataclass
class FaceDetection:
    confidence: float
    bbox_xyxy: List[float]


@dataclass
class FaceFrameResult:
    frame_index: int
    timestamp_sec: float
    faces: List[FaceDetection] = field(default_factory=list)

    def to_dict(self) -> Dict:
        return {
            "frame_index": self.frame_index,
            "timestamp_sec": round(self.timestamp_sec, 3),
            "face_count": len(self.faces),
            "faces": [
                {"confidence": round(f.confidence, 4), "bbox_xyxy": [round(v, 1) for v in f.bbox_xyxy]}
                for f in self.faces
            ],
        }


def _ensure_dnn_weights() -> bool:
    """Best-effort download of the DNN face model. Returns True if the
    model is available locally after this call, False if it should fall
    back to Haar cascade (e.g. no internet in an air-gapped forensic lab
    environment - a realistic constraint for this tool)."""
    os.makedirs(_MODEL_DIR, exist_ok=True)
    if os.path.exists(_PROTOTXT_PATH) and os.path.exists(_CAFFEMODEL_PATH):
        return True
    try:
        if not os.path.exists(_PROTOTXT_PATH):
            urllib.request.urlretrieve(_PROTOTXT_URL, _PROTOTXT_PATH)
        if not os.path.exists(_CAFFEMODEL_PATH):
            urllib.request.urlretrieve(_CAFFEMODEL_URL, _CAFFEMODEL_PATH)
        return True
    except Exception:
        return False


class FaceDetector:
    def __init__(self, conf_threshold: float = 0.5, prefer_dnn: bool = True):
        self.conf_threshold = conf_threshold
        self.backend = None
        self.net = None
        self.haar = None

        if prefer_dnn and _ensure_dnn_weights():
            self.net = cv2.dnn.readNetFromCaffe(_PROTOTXT_PATH, _CAFFEMODEL_PATH)
            self.backend = "dnn"
        else:
            # Zero-download fallback bundled with opencv-python if available.
            if hasattr(cv2, "CascadeClassifier") and hasattr(cv2, "data") and hasattr(cv2.data, "haarcascades"):
                cascade_path = cv2.data.haarcascades + "haarcascade_frontalface_default.xml"
                self.haar = cv2.CascadeClassifier(cascade_path)
                self.backend = "haar"
            else:
                self.backend = "fallback"

    def detect_frame(self, frame: np.ndarray, frame_index: int, timestamp_sec: float) -> FaceFrameResult:
        result = FaceFrameResult(frame_index=frame_index, timestamp_sec=timestamp_sec)
        h, w = frame.shape[:2]

        if self.backend == "dnn":
            blob = cv2.dnn.blobFromImage(cv2.resize(frame, (300, 300)), 1.0,
                                          (300, 300), (104.0, 177.0, 123.0))
            self.net.setInput(blob)
            detections = self.net.forward()
            for i in range(detections.shape[2]):
                confidence = float(detections[0, 0, i, 2])
                if confidence < self.conf_threshold:
                    continue
                box = detections[0, 0, i, 3:7] * np.array([w, h, w, h])
                x1, y1, x2, y2 = box.astype(float)
                result.faces.append(FaceDetection(confidence=confidence, bbox_xyxy=[x1, y1, x2, y2]))
        elif self.haar is not None:
            gray = cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY)
            faces = self.haar.detectMultiScale(gray, scaleFactor=1.1, minNeighbors=5, minSize=(30, 30))
            for (x, y, fw, fh) in faces:
                # Haar gives no confidence score - report a fixed nominal value.
                result.faces.append(
                    FaceDetection(confidence=1.0, bbox_xyxy=[float(x), float(y), float(x + fw), float(y + fh)])
                )

        return result

    def detect_video(self, video_path: str, sample_every_n_frames: int = 5):
        cap = cv2.VideoCapture(video_path)
        if not cap.isOpened():
            raise FileNotFoundError(f"Could not open video: {video_path}")
        fps = cap.get(cv2.CAP_PROP_FPS) or 25.0
        frame_index = 0
        while True:
            ok, frame = cap.read()
            if not ok:
                break
            if frame_index % sample_every_n_frames == 0:
                timestamp_sec = frame_index / fps
                yield self.detect_frame(frame, frame_index, timestamp_sec)
            frame_index += 1
        cap.release()


if __name__ == "__main__":
    import argparse
    import json

    parser = argparse.ArgumentParser(description="Run face detection on a video.")
    parser.add_argument("video")
    parser.add_argument("--out", default="output/faces.json")
    parser.add_argument("--every", type=int, default=5)
    args = parser.parse_args()

    detector = FaceDetector()
    print(f"Using backend: {detector.backend}")
    all_results = [r.to_dict() for r in detector.detect_video(args.video, sample_every_n_frames=args.every)]

    with open(args.out, "w") as f:
        json.dump({"video": args.video, "backend": detector.backend, "results": all_results}, f, indent=2)
    print(f"Analyzed {len(all_results)} frames -> {args.out}")
