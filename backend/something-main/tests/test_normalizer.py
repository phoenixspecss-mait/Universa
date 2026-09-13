"""Comprehensive unit tests for TimelineNormalizer."""

from datetime import UTC, datetime

from src.timeline.constants import (
    AnomalyFlag,
    CorrectionMethod,
    TimestampFormat,
    TimestampSource,
)
from src.timeline.normalizer import TimelineNormalizer


def test_unix_epoch_seconds():
    normalizer = TimelineNormalizer()
    res = normalizer.normalize("1773144000", timestamp_format=TimestampFormat.UNIX_EPOCH_S)
    assert res.success is True
    assert res.utc_timestamp == datetime(2026, 3, 10, 12, 0, 0, tzinfo=UTC)
    assert res.raw_timestamp == "1773144000"


def test_unix_epoch_milliseconds():
    normalizer = TimelineNormalizer()
    res = normalizer.normalize("1773144000000", timestamp_format=TimestampFormat.UNIX_EPOCH_MS)
    assert res.success is True
    assert res.utc_timestamp == datetime(2026, 3, 10, 12, 0, 0, tzinfo=UTC)


def test_iso_8601_with_utc_z():
    normalizer = TimelineNormalizer()
    res = normalizer.normalize("2026-03-10T12:00:00Z", timestamp_format=TimestampFormat.ISO_8601)
    assert res.success is True
    assert res.utc_timestamp == datetime(2026, 3, 10, 12, 0, 0, tzinfo=UTC)


def test_iso_8601_with_offset():
    normalizer = TimelineNormalizer()
    res = normalizer.normalize(
        "2026-03-10T17:30:00+05:30", timestamp_format=TimestampFormat.ISO_8601
    )
    assert res.success is True
    assert res.utc_timestamp == datetime(2026, 3, 10, 12, 0, 0, tzinfo=UTC)


def test_naive_timestamp_with_supplied_timezone():
    normalizer = TimelineNormalizer()
    res = normalizer.normalize(
        "2026-03-10 17:30:00",
        supplied_timezone="Asia/Kolkata",
    )
    assert res.success is True
    assert res.utc_timestamp == datetime(2026, 3, 10, 12, 0, 0, tzinfo=UTC)
    assert res.raw_timestamp == "2026-03-10 17:30:00"


def test_hikvision_compact_format():
    normalizer = TimelineNormalizer()
    res = normalizer.normalize(
        "20260310T120000Z", timestamp_format=TimestampFormat.VENDOR_HIKVISION
    )
    assert res.success is True
    assert res.utc_timestamp == datetime(2026, 3, 10, 12, 0, 0, tzinfo=UTC)


def test_dahua_format():
    normalizer = TimelineNormalizer()
    res = normalizer.normalize(
        "2026-03-10 12:00:00",
        timestamp_format=TimestampFormat.VENDOR_DAHUA,
        supplied_timezone="UTC",
    )
    assert res.success is True
    assert res.utc_timestamp == datetime(2026, 3, 10, 12, 0, 0, tzinfo=UTC)


def test_cctv_dd_mm_yyyy_format():
    normalizer = TimelineNormalizer()
    res = normalizer.normalize(
        "10/03/2026 12:00:00",
        timestamp_format=TimestampFormat.CCTV_DD_MM_YYYY,
        supplied_timezone="UTC",
    )
    assert res.success is True
    assert res.utc_timestamp == datetime(2026, 3, 10, 12, 0, 0, tzinfo=UTC)


def test_fat_dos_32_timestamp_and_filesystem_segregation():
    """Correction #3: FAT/DOS timestamps must be explicitly classified as filesystem timestamps."""
    normalizer = TimelineNormalizer()
    # 2026-03-10 12:00:00 in FAT32:
    # date: (2026-1980=46)<<9 | 3<<5 | 10 = (46<<9) | 96 | 10 = 23552 | 96 | 10 = 23658 (0x5C6A)
    # time: 12<<11 | 0<<5 | 0 = 24576 (0x6000)
    # 32-bit int: (23658 << 16) | 24576 = 1550475264 (0x5C6A6000)
    fat_val = "0x5C6A6000"
    res = normalizer.normalize(
        fat_val,
        timestamp_format=TimestampFormat.FAT_DOS_32,
        timestamp_source=TimestampSource.FAT_DIRENTRY,
        supplied_timezone="UTC",
    )
    assert res.success is True
    assert res.utc_timestamp == datetime(2026, 3, 10, 12, 0, 0, tzinfo=UTC)
    # Anomaly flag indicates filesystem approximation
    assert AnomalyFlag.FILESYSTEM_TIMESTAMP_APPROXIMATION.value in res.anomaly_flags


def test_fixed_offset_correction():
    normalizer = TimelineNormalizer()
    res = normalizer.normalize(
        "2026-03-10T12:00:00Z",
        offset_ms=5000.0,
    )
    assert res.success is True
    assert res.utc_timestamp == datetime(2026, 3, 10, 12, 0, 5, tzinfo=UTC)
    assert res.applied_offset_ms == 5000.0
    assert res.correction_method == CorrectionMethod.FIXED_OFFSET
    # Raw is preserved unmodified!
    assert res.raw_timestamp == "2026-03-10T12:00:00Z"


def test_linear_drift_correction():
    normalizer = TimelineNormalizer()
    ref_time = datetime(2026, 3, 10, 12, 0, 0, tzinfo=UTC)
    # 1 hour later = 3600 seconds. Drift: +100 PPM = +0.36 seconds = +360 ms
    event_time_str = "2026-03-10T13:00:00Z"
    res = normalizer.normalize(
        event_time_str,
        drift_rate_ppm=100.0,
        reference_time_utc=ref_time,
    )
    assert res.success is True
    assert res.correction_method == CorrectionMethod.LINEAR_DRIFT
    assert abs(res.applied_offset_ms - 360.0) < 1.0


def test_invalid_and_malformed_timestamps():
    normalizer = TimelineNormalizer()

    # Impossible date (Feb 31)
    res1 = normalizer.normalize("2026-02-31 12:00:00")
    assert res1.success is False
    assert len(res1.errors) > 0

    # Garbage non-date string
    res2 = normalizer.normalize("INVALID_TIMESTAMP_STRING")
    assert res2.success is False
    assert len(res2.errors) > 0

    # Invalid timezone
    res3 = normalizer.normalize("2026-03-10 12:00:00", supplied_timezone="NonExistent/Zone")
    assert res3.success is False


def test_non_monotonic_time_jump_anomaly():
    """Detects backwards time jump when frame index increments."""
    t1 = datetime(2026, 3, 10, 12, 0, 10, tzinfo=UTC)
    t2 = datetime(2026, 3, 10, 12, 0, 5, tzinfo=UTC)  # Jump backwards 5 seconds

    anomalies = TimelineNormalizer.check_temporal_continuity(
        channel_id="CAM01",
        current_utc=t2,
        current_frame_index=150,
        last_utc=t1,
        last_frame_index=100,
    )
    assert AnomalyFlag.NON_MONOTONIC_TIME_JUMP.value in anomalies


def test_timeline_gap_anomaly():
    """Correction #5: Flags TIMELINE_GAP_DETECTED (not proven RECORDING_GAP)."""
    t1 = datetime(2026, 3, 10, 12, 0, 0, tzinfo=UTC)
    t2 = datetime(2026, 3, 10, 12, 0, 45, tzinfo=UTC)  # 45 second gap (> 30s threshold)

    anomalies = TimelineNormalizer.check_temporal_continuity(
        channel_id="CAM01",
        current_utc=t2,
        current_frame_index=101,
        last_utc=t1,
        last_frame_index=100,
    )
    assert AnomalyFlag.RECORDING_DISCONTINUITY.value in anomalies


def test_media_relative_pts_with_custom_time_base():
    """Test media-relative PTS calculation with non-default time base (e.g. MOT17 1/15360)."""
    normalizer = TimelineNormalizer()
    res = normalizer.normalize(
        "2026-09-10T12:00:00+00:00",
        timestamp_format=TimestampFormat.MEDIA_RELATIVE_PTS,
        timestamp_source=TimestampSource.DERIVED_PTS,
        pts=51200,
        time_base_num=1,
        time_base_den=15360,
    )
    assert res.success is True
    assert res.utc_timestamp is not None
    # 51200 / 15360 = 3.33333333... seconds
    expected = datetime(2026, 9, 10, 12, 0, 3, 333333, tzinfo=UTC)
    delta_micros = abs((res.utc_timestamp - expected).total_seconds())
    assert delta_micros < 0.000002
    assert res.raw_timestamp == "2026-09-10T12:00:00+00:00"


def test_media_relative_pts_default_backwards_compatible():
    """Test media-relative PTS calculation with default 1/1000 time base."""
    normalizer = TimelineNormalizer()
    res = normalizer.normalize(
        "2026-09-10T12:00:00+00:00",
        timestamp_format=TimestampFormat.MEDIA_RELATIVE_PTS,
        timestamp_source=TimestampSource.DERIVED_PTS,
        pts=5000,
    )
    assert res.success is True
    # 5000 / 1000 = 5.0 seconds
    expected = datetime(2026, 9, 10, 12, 0, 5, 0, tzinfo=UTC)
    assert res.utc_timestamp == expected
