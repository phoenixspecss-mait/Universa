"""Module #2 (Codec/Format Engine — Rust/FFmpeg) Integration Interface.

Represents the container demuxing and decoding layer responsible for parsing
proprietary codecs (DHAV, HIK, H.264/H.265 bitstreams), recovering orphaned
frames, and exposing presentation timestamps (PTS/DTS).
"""

from abc import ABC, abstractmethod
from collections.abc import AsyncGenerator
from typing import Any

from src.timeline.constants import TimestampFormat, TimestampSource, VendorType
from src.timeline.schemas import RawFrameMeta


class CodecEngineInterface(ABC):
    """Integration contract that Module #2 (Rust/FFmpeg Codec Engine) will fulfill."""

    @abstractmethod
    async def parse_segment_headers(self, file_path: str) -> dict[str, Any]:
        """Parse container headers, index tables, and keyframe intervals."""
        pass

    @abstractmethod
    async def extract_recovered_frames(
        self, case_id: str, evidence_id: str, channel_id: str, count: int = 5
    ) -> AsyncGenerator[RawFrameMeta, None]:
        """Stream recovered orphaned or carved video frames."""
        pass


class MockCodecEngine(CodecEngineInterface):
    """Mock adapter simulating Rust/FFmpeg codec parser."""

    def __init__(self) -> None:
        self.codec = "H.265/HEVC"

    async def parse_segment_headers(self, file_path: str) -> dict[str, Any]:
        return {
            "file_path": file_path,
            "container_format": "DAHUA_DAV",
            "video_codec": self.codec,
            "resolution": "3840x2160",
            "fps": 25.0,
            "time_base": "1/1000",
            "total_frames_recovered": 1500,
            "is_damaged_stream": True,
            "carved_fragments_count": 3,
        }

    async def extract_recovered_frames(
        self, case_id: str, evidence_id: str, channel_id: str, count: int = 5
    ) -> AsyncGenerator[RawFrameMeta, None]:
        """Yield recovered video frames with PTS/DTS timing."""
        for idx in range(count):
            pts_val = idx * 40  # 25 fps = 40ms per frame
            yield RawFrameMeta(
                case_id=case_id,
                evidence_id=evidence_id,
                channel_id=channel_id,
                vendor_type=VendorType.DAHUA,
                raw_timestamp_str="2026-03-10 12:05:00",
                timestamp_format=TimestampFormat.MEDIA_RELATIVE_PTS,
                timestamp_source=TimestampSource.DERIVED_PTS,
                frame_index=1000 + idx,
                file_offset_bytes=1048576 + (idx * 32768),
                pts=pts_val,
                dts=pts_val,
                file_path=f"/carved_segments/{channel_id}_fragment_02.dav",
                frame_hash_sha256=f"carved_hash_{channel_id}_{idx}",
            )
