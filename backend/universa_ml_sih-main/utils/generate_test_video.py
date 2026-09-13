"""
generate_test_video.py
-----------------------
Generates a short synthetic surveillance-style test video (moving
rectangles simulating people/vehicles, plus a sudden-motion "anomaly"
burst) so the pipeline can be demoed/tested without needing real DVR
footage on hand. Also handy for judges/mentors who want to see it run
live during evaluation.
"""

import argparse
import cv2
import numpy as np


def generate(path: str, width: int = 640, height: int = 480, fps: int = 25, seconds: int = 10):
    fourcc = cv2.VideoWriter_fourcc(*"mp4v")
    writer = cv2.VideoWriter(path, fourcc, fps, (width, height))

    total_frames = fps * seconds
    for i in range(total_frames):
        frame = np.full((height, width, 3), 40, dtype=np.uint8)  # dark background

        # A "person" (small moving rectangle) walking across the frame.
        px = int((i / total_frames) * (width - 40))
        cv2.rectangle(frame, (px, 300), (px + 30, 400), (60, 180, 220), -1)

        # A "car" (wider rectangle) moving the other direction.
        cx = int(width - (i / total_frames) * (width - 80))
        cv2.rectangle(frame, (cx, 150), (cx + 80, 210), (200, 200, 60), -1)

        # Sudden anomaly burst: lots of extra motion blobs mid-video.
        if int(seconds * 0.55 * fps) < i < int(seconds * 0.65 * fps):
            for _ in range(15):
                bx, by = np.random.randint(0, width - 20), np.random.randint(0, height - 20)
                cv2.rectangle(frame, (bx, by), (bx + 20, 20 + by),
                               tuple(int(v) for v in np.random.randint(80, 255, 3)), -1)

        writer.write(frame)

    writer.release()
    print(f"Wrote {total_frames} frames ({seconds}s @ {fps}fps) -> {path}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--out", default="sample_data/synthetic_test.mp4")
    parser.add_argument("--seconds", type=int, default=10)
    args = parser.parse_args()
    generate(args.out, seconds=args.seconds)
