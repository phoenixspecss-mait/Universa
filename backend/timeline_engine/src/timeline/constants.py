"""Domain constants and enumerations for the timeline engine."""

try:
    from enum import StrEnum
except ImportError:
    from enum import Enum

    class StrEnum(str, Enum):
        """Python 3.9/3.10 fallback for StrEnum."""
        def __str__(self) -> str:
            return str(self.value)



class VendorType(StrEnum):
    """Recognized DVR/NVR vendor hardware signatures."""

    HIKVISION = "HIKVISION"
    DAHUA = "DAHUA"
    CP_PLUS = "CP_PLUS"
    UNV = "UNV"
    GENERIC = "GENERIC"
    FAT_FS = "FAT_FS"


class TimestampFormat(StrEnum):
    """Categorized incoming timestamp formatting."""

    UNIX_EPOCH_S = "UNIX_EPOCH_S"
    UNIX_EPOCH_MS = "UNIX_EPOCH_MS"
    ISO_8601 = "ISO_8601"
    VENDOR_DAHUA = "VENDOR_DAHUA"
    VENDOR_HIKVISION = "VENDOR_HIKVISION"
    CCTV_DD_MM_YYYY = "CCTV_DD_MM_YYYY"
    CCTV_MM_DD_YYYY = "CCTV_MM_DD_YYYY"
    FAT_DOS_32 = "FAT_DOS_32"
    MEDIA_RELATIVE_PTS = "MEDIA_RELATIVE_PTS"
    AUTO = "AUTO"


class TimestampSource(StrEnum):
    """Forensic provenance source of the timestamp.

    Filesystem timestamps (FAT, mtime, ctime) are explicitly segregated from
    embedded bitstream recording timestamps.
    """

    RECORDING_EMBEDDED = "RECORDING_EMBEDDED"
    METADATA_HEADER = "METADATA_HEADER"
    FILESYSTEM_MTIME = "FILESYSTEM_MTIME"
    FILESYSTEM_CTIME = "FILESYSTEM_CTIME"
    FAT_DIRENTRY = "FAT_DIRENTRY"
    DERIVED_PTS = "DERIVED_PTS"
    UNKNOWN = "UNKNOWN"


class EventType(StrEnum):
    """Forensic timeline event classifications."""

    FRAME_INDEX = "FRAME_INDEX"
    AI_DETECTION = "AI_DETECTION"
    MOTION_DETECTED = "MOTION_DETECTED"
    RECORDING_START = "RECORDING_START"
    RECORDING_STOP = "RECORDING_STOP"
    TIMELINE_GAP_DETECTED = "TIMELINE_GAP_DETECTED"
    TIME_REGRESSION_DETECTED = "TIME_REGRESSION_DETECTED"
    SYSTEM_EVENT = "SYSTEM_EVENT"


class CorrelationType(StrEnum):
    """Cross-camera event correlation classifications.

    Forensic Rule: Temporal correlation must never assert identity certainty.
    """

    TEMPORAL_COINCIDENCE = "TEMPORAL_COINCIDENCE"
    CROSS_CAMERA_CLASS_MATCH = "CROSS_CAMERA_CLASS_MATCH"
    TRACK_CONTINUITY = "TRACK_CONTINUITY"
    EMBEDDING_MATCH = "EMBEDDING_MATCH"
    POSSIBLE_TRANSITION = "POSSIBLE_TRANSITION"


class CorrectionMethod(StrEnum):
    """Applied timeline mathematical correction method."""

    NONE = "NONE"
    FIXED_OFFSET = "FIXED_OFFSET"
    LINEAR_DRIFT = "LINEAR_DRIFT"


class AnomalyFlag(StrEnum):
    """Forensic timeline anomaly markers."""

    NON_MONOTONIC_TIME_JUMP = "NON_MONOTONIC_TIME_JUMP"
    RECORDING_DISCONTINUITY = "RECORDING_DISCONTINUITY"
    FILESYSTEM_TIMESTAMP_APPROXIMATION = "FILESYSTEM_TIMESTAMP_APPROXIMATION"
    MALFORMED_RAW_TIMESTAMP = "MALFORMED_RAW_TIMESTAMP"
    FALLBACK_TIMEZONE_APPLIED = "FALLBACK_TIMEZONE_APPLIED"
    CLOCK_DRIFT_DETECTED = "CLOCK_DRIFT_DETECTED"
