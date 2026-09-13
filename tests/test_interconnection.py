"""
test_interconnection.py
-----------------------
Automated integration test suite verifying the interconnection of:
  1. C++ Core Engine & Carving outputs
  2. universa_ml_sih-main / universa_ml_main (YOLOv8 tracking, MOG2 motion anomaly, face localization, OpenCLIP search)
  3. something-main (Module #3 Timeline Normalizer, Event Correlator, SQLite Async, and REST/WS APIs)
  4. Frontend API client data contracts (SearchResultModel, Timeline schemas)
"""

import asyncio
import os
import sys
import unittest
from datetime import datetime, timezone
from pathlib import Path

# Add directories to sys.path
ROOT_DIR = Path(__file__).resolve().parents[1]
BACKEND_DIR = ROOT_DIR / "backend"
TIMELINE_ENGINE_DIR = BACKEND_DIR / "timeline_engine"
ML_DIR = BACKEND_DIR / "universa_ml_sih-main"

for p in [str(ROOT_DIR), str(TIMELINE_ENGINE_DIR), str(ML_DIR)]:
    if p not in sys.path:
        sys.path.insert(0, p)


class TestUniversaInterconnection(unittest.TestCase):

    def test_01_universa_ml_main_symlink_and_imports(self):
        """Verify that backend/universa_ml_main resolves and imports cleanly."""
        symlink_path = BACKEND_DIR / "universa_ml_main"
        self.assertTrue(symlink_path.exists(), "backend/universa_ml_main symlink or folder must exist")

        from models.motion_anomaly import MotionDetector, MotionFrameResult
        self.assertIsNotNone(MotionDetector)

        from models.face_detector import FaceDetector
        self.assertIsNotNone(FaceDetector)

        from pipeline import analyze_video, process_case_clips, summarize
        self.assertTrue(callable(analyze_video))
        self.assertTrue(callable(process_case_clips))

    def test_02_mog2_motion_anomaly_detector(self):
        """Verify explainable MOG2 motion and anomaly detection algorithm."""
        import numpy as np
        from models.motion_anomaly import MotionDetector

        detector = MotionDetector(min_area_px=100, var_threshold=25)
        h, w = 240, 320

        # Feed 10 static background frames
        for idx in range(10):
            frame = np.full((h, w, 3), 50, dtype=np.uint8)
            res = detector.process_frame(frame, frame_index=idx, timestamp_sec=idx * 0.1)
            self.assertEqual(res.frame_index, idx)

        # Feed 1 frame with sudden moving rectangle (simulated anomaly/motion burst)
        motion_frame = np.full((h, w, 3), 50, dtype=np.uint8)
        motion_frame[50:150, 50:150] = 220 # Bright white moving rectangle
        res_motion = detector.process_frame(motion_frame, frame_index=11, timestamp_sec=1.1)

        self.assertGreater(res_motion.motion_area_ratio, 0.01, "Motion area ratio should detect the moving block")
        self.assertGreater(len(res_motion.regions), 0, "Motion regions should be localized")

    def test_03_universa_ml_ai_engine_adapter(self):
        """Verify that something-main can instantiate UniversaMLAIEngine."""
        from src.integrations.ai_engine import UniversaMLAIEngine
        from src.timeline.schemas import AIDetectionPayload

        engine = UniversaMLAIEngine(ml_dir=str(ML_DIR))
        self.assertIsNotNone(engine.motion_detector, "Motion detector should be loaded in engine")

        # Test frame processing with fallback
        async def _test():
            payloads = await engine.process_frame(
                case_id="TEST-CASE",
                evidence_id="EVID-01",
                channel_id="CAM01",
                frame_index=1,
                utc_timestamp=datetime.now(timezone.utc),
            )
            self.assertIsInstance(payloads, list)
            self.assertGreater(len(payloads), 0)
            self.assertIsInstance(payloads[0], AIDetectionPayload)
            self.assertEqual(payloads[0].channel_id, "CAM01")

        asyncio.run(_test())

    def test_04_universa_core_engine_case_discovery(self):
        """Verify that UniversaCoreEngine reads C++ cases and carved clips."""
        from src.integrations.core_engine import UniversaCoreEngine

        cases_dir = ROOT_DIR / "cases"
        core = UniversaCoreEngine(cases_dir=str(cases_dir))

        # Check existing case
        existing_cases = [c for c in cases_dir.iterdir() if c.is_dir()]
        if existing_cases:
            case_id = existing_cases[0].name
            async def _stream():
                frames = []
                async for f in core.stream_frames(case_id, "EVID", "CAM01", count=3):
                    frames.append(f)
                return frames

            frames = asyncio.run(_stream())
            self.assertGreater(len(frames), 0)
            self.assertEqual(frames[0].case_id, case_id)

    def test_05_timeline_normalization_and_cross_camera_correlation(self):
        """Verify that timeline normalizer and event correlator link multi-camera events with embeddings."""
        from src.timeline.normalizer import TimelineNormalizer
        from src.timeline.correlator import EventCorrelator
        from src.timeline.schemas import TimelineEvent
        from src.timeline.constants import TimestampSource, EventType

        normalizer = TimelineNormalizer()
        correlator = EventCorrelator(window_seconds=10.0, cosine_threshold=0.80)

        # Create 2 synchronized events on 2 different cameras
        t_base = datetime(2026, 3, 10, 12, 0, 0, tzinfo=timezone.utc)
        emb_shared = [0.1 * i for i in range(10)]
        norm = sum(x*x for x in emb_shared) ** 0.5
        norm_emb = [round(x / norm, 4) for x in emb_shared]

        ev_cam1 = TimelineEvent(
            case_id="CASE-CORR",
            evidence_id="clip1.mp4",
            channel_id="CAM01",
            utc_timestamp=t_base,
            raw_timestamp="2026-03-10 12:00:00",
            timestamp_source=TimestampSource.RECORDING_EMBEDDED,
            event_type=EventType.AI_DETECTION,
            payload={
                "object_class": "person",
                "confidence": 0.95,
                "embedding": norm_emb,
            },
        )

        ev_cam2 = TimelineEvent(
            case_id="CASE-CORR",
            evidence_id="clip2.mp4",
            channel_id="CAM02",
            utc_timestamp=datetime(2026, 3, 10, 12, 0, 2, tzinfo=timezone.utc), # 2 seconds later
            raw_timestamp="2026-03-10 12:00:02",
            timestamp_source=TimestampSource.RECORDING_EMBEDDED,
            event_type=EventType.AI_DETECTION,
            payload={
                "object_class": "person",
                "confidence": 0.92,
                "embedding": norm_emb,
            },
        )

        correlations = correlator.correlate_batch([ev_cam1, ev_cam2])
        self.assertEqual(len(correlations), 1, "Cross-camera correlation must detect the 2 matching events")
        self.assertEqual(correlations[0].primary_channel, "CAM01")
        self.assertIn("CAM02", correlations[0].secondary_channels)

    def test_06_cpp_binaries_present(self):
        """Verify that C++ dvr_recovery and dvr_api_server binaries are compiled."""
        recovery_bin = ROOT_DIR / "dvr_recovery"
        server_bin = ROOT_DIR / "dvr_api_server"
        self.assertTrue(recovery_bin.exists(), "dvr_recovery binary must exist")
        self.assertTrue(server_bin.exists(), "dvr_api_server binary must exist")
        self.assertTrue(os.access(recovery_bin, os.X_OK), "dvr_recovery must be executable")
        self.assertTrue(os.access(server_bin, os.X_OK), "dvr_api_server must be executable")


if __name__ == "__main__":
    unittest.main()

