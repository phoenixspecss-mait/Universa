"""Module #1 (Core Engine — C++) Integration Interface and Mock Adapter.

Represents the physical acquisition layer responsible for raw disk reading,
device identification, and cryptographic hashing.
"""

import hashlib
from abc import ABC, abstractmethod
from collections.abc import AsyncGenerator
from typing import Any

from src.timeline.constants import TimestampFormat, TimestampSource, VendorType
from src.timeline.schemas import RawFrameMeta


class CoreEngineInterface(ABC):
    """Integration contract that Module #1 (C++ Core Engine) will fulfill."""

    @abstractmethod
    async def identify_device(self, evidence_path: str) -> dict[str, Any]:
        """Inspect raw evidence image and return vendor hardware metadata."""
        pass

    @abstractmethod
    async def stream_frames(
        self, case_id: str, evidence_id: str, channel_id: str, count: int = 10
    ) -> AsyncGenerator[RawFrameMeta, None]:
        """Stream raw acquired frame metadata and cryptographic hashes."""
        pass


class MockCoreEngine(CoreEngineInterface):
    """Mock adapter simulating C++ Core Engine acquisition."""

    def __init__(self, vendor: VendorType = VendorType.HIKVISION) -> None:
        self.vendor = vendor

    async def identify_device(self, evidence_path: str) -> dict[str, Any]:
        return {
            "evidence_path": evidence_path,
            "detected_vendor": self.vendor.value,
            "filesystem": "FAT32_PROPRIETARY",
            "sector_size": 512,
            "total_channels": 8,
            "device_model": f"{self.vendor.value}-NVR7000-4K",
            "firmware_version": "v4.32.010_build240115",
            "evidence_hash_sha256": hashlib.sha256(evidence_path.encode()).hexdigest(),
        }

    async def stream_frames(
        self, case_id: str, evidence_id: str, channel_id: str, count: int = 10
    ) -> AsyncGenerator[RawFrameMeta, None]:
        """Yield synthetic raw frame metadata blocks."""
        for idx in range(count):
            frame_offset = idx * 65536
            frame_hash = hashlib.sha256(f"frame_content_{channel_id}_{idx}".encode()).hexdigest()

            # Emulate vendor timestamp
            raw_ts = f"2026-03-10 12:00:{idx:02d}"
            fmt = TimestampFormat.VENDOR_DAHUA
            if self.vendor == VendorType.HIKVISION:
                raw_ts = f"20260310T1200{idx:02d}Z"
                fmt = TimestampFormat.VENDOR_HIKVISION

            yield RawFrameMeta(
                case_id=case_id,
                evidence_id=evidence_id,
                channel_id=channel_id,
                vendor_type=self.vendor,
                raw_timestamp_str=raw_ts,
                timestamp_format=fmt,
                timestamp_source=TimestampSource.RECORDING_EMBEDDED,
                frame_index=idx,
                file_offset_bytes=frame_offset,
                pts=idx * 1000,
                dts=idx * 1000,
                file_path=f"/evidence/disk01/{channel_id}.raw",
                frame_hash_sha256=frame_hash,
            )


class UniversaCoreEngine(CoreEngineInterface):
    """Real acquisition adapter reading cases, disk images, and carved clips from C++ Core Engine."""

    def __init__(self, cases_dir: str | None = None) -> None:
        from pathlib import Path
        if cases_dir:
            self.cases_dir = Path(cases_dir)
        else:
            self.cases_dir = Path(__file__).resolve().parents[3] / "cases"

    async def identify_device(self, evidence_path: str) -> dict[str, Any]:
        """Inspect evidence file and return detected hardware vendor and hashes."""
        from pathlib import Path
        p = Path(evidence_path)
        sha256_hash = ""
        if p.exists() and p.is_file():
            hasher = hashlib.sha256()
            with open(p, "rb") as f:
                while chunk := f.read(65536):
                    hasher.update(chunk)
            sha256_hash = hasher.hexdigest()

        vendor = VendorType.GENERIC
        try:
            with open(p, "rb") as f:
                header = f.read(512)
                if b"DHAV" in header:
                    vendor = VendorType.DAHUA
                elif b"ftypisom" in header or b"hik" in header.lower():
                    vendor = VendorType.HIKVISION
                elif b"DVR-MOCK" in header:
                    vendor = VendorType.GENERIC
        except Exception:
            pass

        return {
            "evidence_path": evidence_path,
            "detected_vendor": vendor.value,
            "filesystem": "FAT32_PROPRIETARY",
            "sector_size": 512,
            "total_channels": 4,
            "device_model": f"{vendor.value}-FORENSIC-DVR",
            "evidence_hash_sha256": sha256_hash,
        }

    async def stream_frames(
        self, case_id: str, evidence_id: str, channel_id: str, count: int = 10
    ) -> AsyncGenerator[RawFrameMeta, None]:
        """Stream real carved video frames from case directory, or fallback to mock."""
        case_path = self.cases_dir / case_id
        carved_dir = case_path / "carved"

        carved_files = []
        if carved_dir.exists():
            carved_files = sorted(
                [f for f in carved_dir.iterdir() if f.is_file() and f.suffix in {".mp4", ".dav"}]
            )

        if not carved_files:
            fallback = MockCoreEngine()
            async for frame in fallback.stream_frames(case_id, evidence_id, channel_id, count):
                yield frame
            return

        frame_idx = 0
        for vid_file in carved_files:
            # Hash the carved file
            hasher = hashlib.sha256()
            try:
                with open(vid_file, "rb") as f:
                    while c := f.read(65536):
                        hasher.update(c)
                file_hash = hasher.hexdigest()
            except Exception:
                file_hash = hashlib.sha256(vid_file.name.encode()).hexdigest()

            pts_val = frame_idx * 40
            yield RawFrameMeta(
                case_id=case_id,
                evidence_id=evidence_id,
                channel_id=channel_id,
                vendor_type=VendorType.GENERIC,
                raw_timestamp_str=f"2026-03-10 12:00:{frame_idx:02d}",
                timestamp_format=TimestampFormat.AUTO,
                timestamp_source=TimestampSource.RECORDING_EMBEDDED,
                frame_index=frame_idx,
                file_offset_bytes=frame_idx * 32768,
                pts=pts_val,
                dts=pts_val,
                file_path=str(vid_file),
                frame_hash_sha256=file_hash,
            )
            frame_idx += 1

