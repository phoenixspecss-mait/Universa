"""Forensic Timestamp Normalization Engine.

Converts multi-vendor timestamps (Hikvision, Dahua, CCTV, FAT/DOS, Epoch, ISO)
into canonical UTC while preserving evidentiary raw timestamps and applying
auditable clock offset and drift corrections.
"""

import re
from dataclasses import dataclass, field
from datetime import UTC, datetime, timedelta, timezone
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

from dateutil import parser as dateutil_parser

from src.config import settings
from src.timeline.constants import (
    AnomalyFlag,
    CorrectionMethod,
    TimestampFormat,
    TimestampSource,
)


@dataclass
class NormalizationResult:
    """Forensic normalization result container."""

    success: bool
    raw_timestamp: str
    utc_timestamp: datetime | None = None
    applied_offset_ms: float = 0.0
    correction_method: CorrectionMethod = CorrectionMethod.NONE
    timestamp_source: TimestampSource = TimestampSource.UNKNOWN
    detected_format: str = "UNKNOWN"
    anomaly_flags: list[str] = field(default_factory=list)
    errors: list[str] = field(default_factory=list)


class TimelineNormalizer:
    """Forensic timestamp normalizer adhering to strict evidentiary standards."""

    def __init__(self, fallback_timezone: str | None = None) -> None:
        self.fallback_timezone = fallback_timezone or settings.DEFAULT_FALLBACK_TIMEZONE

    def normalize(
        self,
        raw_timestamp_str: str,
        timestamp_format: TimestampFormat = TimestampFormat.AUTO,
        timestamp_source: TimestampSource = TimestampSource.UNKNOWN,
        supplied_timezone: str | None = None,
        offset_ms: float = 0.0,
        drift_rate_ppm: float = 0.0,
        reference_time_utc: datetime | None = None,
        pts: int | None = None,
        time_base_num: int = 1,
        time_base_den: int = 1000,
    ) -> NormalizationResult:
        """Parse, validate, convert to UTC, and apply derived corrections.

        Raw timestamp is NEVER mutated. Filesystem/FAT timestamps are flagged
        and segregated from embedded recording timestamps.
        """
        raw_clean = str(raw_timestamp_str).strip()
        anomaly_flags: list[str] = []
        errors: list[str] = []

        # Normalize string enum inputs if passed from JSON
        if isinstance(timestamp_format, str):
            try:
                timestamp_format = TimestampFormat(timestamp_format)
            except ValueError:
                timestamp_format = TimestampFormat.AUTO

        if isinstance(timestamp_source, str):
            try:
                timestamp_source = TimestampSource(timestamp_source)
            except ValueError:
                timestamp_source = TimestampSource.UNKNOWN

        # Forensic rule: Flag if filesystem timestamp is used as recording time
        if timestamp_source in (
            TimestampSource.FILESYSTEM_MTIME,
            TimestampSource.FILESYSTEM_CTIME,
            TimestampSource.FAT_DIRENTRY,
        ):
            anomaly_flags.append(AnomalyFlag.FILESYSTEM_TIMESTAMP_APPROXIMATION.value)

        # 1. Parse raw string to aware datetime
        dt_parsed, detected_fmt = self._parse_to_datetime(
            raw_clean, timestamp_format, supplied_timezone, anomaly_flags, errors
        )

        if dt_parsed is None or errors:
            return NormalizationResult(
                success=False,
                raw_timestamp=raw_clean,
                timestamp_source=timestamp_source,
                detected_format=detected_fmt,
                anomaly_flags=anomaly_flags,
                errors=errors,
            )

        # 2. Convert to canonical UTC
        utc_dt = dt_parsed.astimezone(UTC)

        # 3. Handle PTS media-relative offset if applicable
        if timestamp_format == TimestampFormat.MEDIA_RELATIVE_PTS and pts is not None:
            if time_base_den <= 0:
                errors.append(
                    f"Invalid media time_base denominator: {time_base_den}. Denominator must be >= 1."
                )
                anomaly_flags.append(AnomalyFlag.MALFORMED_RAW_TIMESTAMP.value)
                return NormalizationResult(
                    success=False,
                    raw_timestamp=raw_clean,
                    timestamp_source=timestamp_source,
                    detected_format="INVALID_TIME_BASE",
                    anomaly_flags=anomaly_flags,
                    errors=errors,
                )
            pts_seconds = (pts * time_base_num) / float(time_base_den)
            utc_dt = utc_dt + timedelta(seconds=pts_seconds)
            detected_fmt = f"{detected_fmt}+PTS({pts})"

        # 4. Apply clock calibration (Fixed offset + optional linear drift)
        applied_offset = offset_ms
        method = CorrectionMethod.NONE

        if abs(offset_ms) > 1e-6 or abs(drift_rate_ppm) > 1e-6:
            drift_delta_ms = 0.0
            if abs(drift_rate_ppm) > 1e-6 and reference_time_utc is not None:
                elapsed_seconds = (utc_dt - reference_time_utc).total_seconds()
                drift_delta_ms = elapsed_seconds * (drift_rate_ppm / 1_000_000.0) * 1000.0
                method = CorrectionMethod.LINEAR_DRIFT
            elif abs(offset_ms) > 1e-6:
                method = CorrectionMethod.FIXED_OFFSET

            total_correction_ms = offset_ms + drift_delta_ms
            utc_dt = utc_dt + timedelta(milliseconds=total_correction_ms)
            applied_offset = total_correction_ms

        return NormalizationResult(
            success=True,
            raw_timestamp=raw_clean,
            utc_timestamp=utc_dt,
            applied_offset_ms=applied_offset,
            correction_method=method,
            timestamp_source=timestamp_source,
            detected_format=detected_fmt,
            anomaly_flags=anomaly_flags,
            errors=[],
        )

    def _parse_to_datetime(
        self,
        raw_str: str,
        fmt_hint: TimestampFormat,
        supplied_tz: str | None,
        anomaly_flags: list[str],
        errors: list[str],
    ) -> tuple[datetime | None, str]:
        """Internal multi-vendor parser with validation."""
        tz_target = self._resolve_timezone(supplied_tz, anomaly_flags, errors)
        if errors:
            return None, "INVALID_TIMEZONE"

        # Try Unix Epoch (Float / Int)
        if fmt_hint in (
            TimestampFormat.UNIX_EPOCH_S,
            TimestampFormat.UNIX_EPOCH_MS,
            TimestampFormat.AUTO,
        ):
            if re.match(r"^-?\d+(\.\d+)?$", raw_str):
                try:
                    val = float(raw_str)
                    if fmt_hint == TimestampFormat.UNIX_EPOCH_MS:
                        seconds_val = val / 1000.0
                        fmt_name = TimestampFormat.UNIX_EPOCH_MS.value
                    elif fmt_hint == TimestampFormat.UNIX_EPOCH_S:
                        seconds_val = val
                        fmt_name = TimestampFormat.UNIX_EPOCH_S.value
                    else:  # AUTO magnitude detection
                        # > 1e16 -> nanoseconds (e.g. 1773144000123456789)
                        if abs(val) > 1e16:
                            seconds_val = val / 1e9
                            fmt_name = "UNIX_EPOCH_NS"
                        # > 1e13 -> microseconds (e.g. 1773144000123456)
                        elif abs(val) > 1e13:
                            seconds_val = val / 1e6
                            fmt_name = "UNIX_EPOCH_US"
                        # > 1e10 -> milliseconds (e.g. 1773144000000)
                        elif abs(val) > 1e10:
                            seconds_val = val / 1e3
                            fmt_name = TimestampFormat.UNIX_EPOCH_MS.value
                        else:
                            seconds_val = val
                            fmt_name = TimestampFormat.UNIX_EPOCH_S.value

                    # Calendar range safety check: year must be reasonable (-62135596800 to 253402300799)
                    if not (-62135596800 <= seconds_val <= 253402300799):
                        raise ValueError(
                            f"Epoch seconds {seconds_val} out of valid calendar range"
                        )

                    dt = datetime.fromtimestamp(seconds_val, tz=UTC)
                    return dt, fmt_name
                except (ValueError, OverflowError, OSError) as exc:
                    if fmt_hint != TimestampFormat.AUTO:
                        errors.append(f"Invalid epoch timestamp '{raw_str}': {exc}")
                        return None, "EPOCH_ERROR"

        # Try FAT DOS 32-bit timestamp
        if fmt_hint in (TimestampFormat.FAT_DOS_32, TimestampFormat.AUTO):
            fat_match = re.match(r"^(0x[0-9a-fA-F]{1,8}|\d+)$", raw_str)
            if fat_match and (fmt_hint == TimestampFormat.FAT_DOS_32 or "0x" in raw_str):
                try:
                    int_val = int(raw_str, 16 if "0x" in raw_str else 10)
                    dt = self._parse_fat_dos_32(int_val, tz_target)
                    return dt, TimestampFormat.FAT_DOS_32.value
                except ValueError as exc:
                    if fmt_hint == TimestampFormat.FAT_DOS_32:
                        errors.append(f"Invalid FAT32 timestamp '{raw_str}': {exc}")
                        return None, TimestampFormat.FAT_DOS_32.value

        # Try Hikvision Compact ISO: YYYYMMDDTHHmmssZ or YYYYMMDDTHHmmss
        hik_match = re.match(
            r"^(\d{4})(\d{2})(\d{2})T(\d{2})(\d{2})(\d{2})(Z|[+-]\d{2}:?\d{2})?$", raw_str
        )
        if hik_match:
            try:
                y, m, d, h, mn, s, tz_part = hik_match.groups()
                dt_naive = datetime(int(y), int(m), int(d), int(h), int(mn), int(s))
                if tz_part:
                    if tz_part == "Z":
                        return dt_naive.replace(tzinfo=UTC), TimestampFormat.VENDOR_HIKVISION.value
                    else:
                        parsed = dateutil_parser.parse(raw_str)
                        return parsed, TimestampFormat.VENDOR_HIKVISION.value
                else:
                    return dt_naive.replace(
                        tzinfo=tz_target
                    ), TimestampFormat.VENDOR_HIKVISION.value
            except ValueError as exc:
                errors.append(f"Malformed Hikvision timestamp '{raw_str}': {exc}")
                return None, TimestampFormat.VENDOR_HIKVISION.value

        # Try Dahua format: YYYY-MM-DD HH:mm:ss or YYYY/MM/DD HH:mm:ss
        dahua_match = re.match(
            r"^(\d{4})[-/](\d{2})[-/](\d{2})\s+(\d{2}):(\d{2}):(\d{2})(\.\d+)?$", raw_str
        )
        if dahua_match:
            try:
                y, m, d, h, mn, s, subs = dahua_match.groups()
                micro = int(float(subs) * 1_000_000) if subs else 0
                dt_naive = datetime(int(y), int(m), int(d), int(h), int(mn), int(s), micro)
                return dt_naive.replace(tzinfo=tz_target), TimestampFormat.VENDOR_DAHUA.value
            except ValueError as exc:
                errors.append(f"Malformed Dahua timestamp '{raw_str}': {exc}")
                return None, TimestampFormat.VENDOR_DAHUA.value

        # Try CCTV DD/MM/YYYY HH:mm:ss
        cctv_match = re.match(
            r"^(\d{2})/(\d{2})/(\d{4})\s+(\d{2}):(\d{2}):(\d{2})(\.\d+)?$", raw_str
        )
        if cctv_match:
            try:
                d, m, y, h, mn, s, subs = cctv_match.groups()
                micro = int(float(subs) * 1_000_000) if subs else 0
                dt_naive = datetime(int(y), int(m), int(d), int(h), int(mn), int(s), micro)
                return dt_naive.replace(tzinfo=tz_target), TimestampFormat.CCTV_DD_MM_YYYY.value
            except ValueError as exc:
                errors.append(f"Malformed CCTV date '{raw_str}': {exc}")
                return None, TimestampFormat.CCTV_DD_MM_YYYY.value

        # General ISO-8601 / dateutil fallback
        try:
            parsed = dateutil_parser.isoparse(raw_str)
            if parsed.tzinfo is None:
                parsed = parsed.replace(tzinfo=tz_target)
            return parsed, TimestampFormat.ISO_8601.value
        except (ValueError, TypeError):
            pass

        try:
            parsed = dateutil_parser.parse(raw_str)
            if parsed.tzinfo is None:
                parsed = parsed.replace(tzinfo=tz_target)
            return parsed, "GENERIC_PARSED"
        except (ValueError, TypeError, OverflowError) as exc:
            errors.append(f"Unrecognized or malformed timestamp format '{raw_str}': {exc}")
            anomaly_flags.append(AnomalyFlag.MALFORMED_RAW_TIMESTAMP.value)
            return None, "UNRECOGNIZED"

    def _resolve_timezone(
        self,
        supplied_tz: str | None,
        anomaly_flags: list[str],
        errors: list[str],
    ) -> timezone | ZoneInfo:
        """Resolve timezone string to tzinfo instance."""
        target = supplied_tz or self.fallback_timezone
        if not supplied_tz:
            anomaly_flags.append(AnomalyFlag.FALLBACK_TIMEZONE_APPLIED.value)

        # Handle UTC shorthand
        if target.upper() in ("UTC", "Z", "+00:00", "+0000"):
            return UTC

        # Handle explicit offsets (+05:30, -04:00)
        offset_match = re.match(r"^([+-])(\d{2}):?(\d{2})$", target)
        if offset_match:
            sign, hours, mins = offset_match.groups()
            delta = timedelta(hours=int(hours), minutes=int(mins))
            if sign == "-":
                delta = -delta
            return timezone(delta)

        # Handle IANA timezone names (e.g. Asia/Kolkata)
        try:
            return ZoneInfo(target)
        except (ZoneInfoNotFoundError, ValueError) as exc:
            errors.append(f"Invalid timezone specification '{target}': {exc}")
            return UTC

    @staticmethod
    def _parse_fat_dos_32(fat_int: int, tz: timezone | ZoneInfo) -> datetime:
        """Decode a 32-bit DOS/FAT timestamp (16-bit date high, 16-bit time low)."""
        date_part = (fat_int >> 16) & 0xFFFF
        time_part = fat_int & 0xFFFF

        year = ((date_part >> 9) & 0x7F) + 1980
        month = (date_part >> 5) & 0x0F
        day = date_part & 0x1F

        hour = (time_part >> 11) & 0x1F
        minute = (time_part >> 5) & 0x3F
        second = (time_part & 0x1F) * 2

        if not (
            1 <= month <= 12
            and 1 <= day <= 31
            and 0 <= hour <= 23
            and 0 <= minute <= 59
            and 0 <= second <= 60
        ):
            raise ValueError(
                f"FAT timestamp components out of valid calendar range: "
                f"{year}-{month}-{day} {hour}:{minute}:{second}"
            )

        return datetime(year, month, day, hour, minute, min(second, 59), tzinfo=tz)

    @staticmethod
    def check_temporal_continuity(
        channel_id: str,
        current_utc: datetime,
        current_frame_index: int,
        last_utc: datetime | None,
        last_frame_index: int | None,
    ) -> list[str]:
        """Check for non-monotonic time jumps and timeline gaps.

        Strict Forensic Rules:
        - Non-monotonic jump: Flag TIME_REGRESSION_DETECTED. Frame index ordering
          is distinct from timestamp ordering.
        - Temporal void: Flag TIMELINE_GAP_DETECTED (not proven RECORDING_GAP).
        """
        anomalies: list[str] = []
        if last_utc is None or last_frame_index is None:
            return anomalies

        delta_seconds = (current_utc - last_utc).total_seconds()

        # Check for time rollback / clock reset while frame index increases
        if (
            current_frame_index >= last_frame_index
            and delta_seconds < -settings.TIME_REGRESSION_THRESHOLD_SECONDS
        ):
            anomalies.append(AnomalyFlag.NON_MONOTONIC_TIME_JUMP.value)

        # Check for timeline gap (Correction #5)
        if delta_seconds > settings.TIMELINE_GAP_THRESHOLD_SECONDS:
            anomalies.append(AnomalyFlag.RECORDING_DISCONTINUITY.value)

        return anomalies
