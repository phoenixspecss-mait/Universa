#include "timeline_normalizer.h"
#include "constants.h"

#include <iostream>
#include <algorithm>
#include <ctime>
#include <cstdio>
#include <iomanip>
#include <sstream>

TimelineNormalizer::TimelineNormalizer() = default;

int64_t TimelineNormalizer::parseIso8601ToEpoch(const std::string& isoStr) {
    std::tm tm{};
    int y = 0, M = 0, d = 0, h = 0, m = 0, s = 0;
    if (std::sscanf(isoStr.c_str(), "%d-%d-%dT%d:%d:%d", &y, &M, &d, &h, &m, &s) >= 3 ||
        std::sscanf(isoStr.c_str(), "%d-%d-%d %d:%d:%d", &y, &M, &d, &h, &m, &s) >= 3) {
        tm.tm_year = y - 1900;
        tm.tm_mon = M - 1;
        tm.tm_mday = d;
        tm.tm_hour = h;
        tm.tm_min = m;
        tm.tm_sec = s;
#if defined(_WIN32)
        return _mkgmtime(&tm);
#else
        return timegm(&tm);
#endif
    }
    std::cerr << "[WARN] Malformed timestamp, using fallback\n";
    return universa::FALLBACK_EPOCH;
}

std::string TimelineNormalizer::formatEpochToIso8601(int64_t epochSeconds) {
    std::time_t tt = static_cast<std::time_t>(epochSeconds);
    std::tm gmt{};
#if defined(_WIN32)
    gmtime_s(&gmt, &tt);
#else
    gmtime_r(&tt, &gmt);
#endif
    char buf[32];
    std::strftime(buf, sizeof(buf), "%Y-%m-%dT%H:%M:%SZ", &gmt);
    return std::string(buf);
}

struct ClipItem {
    CarvedChunk chunk;
    ValidationResult val;
};

std::vector<TimelineEntry> TimelineNormalizer::estimateRelativeTimestamp(
    const std::vector<CarvedChunk>& chunks,
    const std::vector<ValidationResult>& validations,
    const std::string& recordingStartUtc
) {
    std::vector<ClipItem> items;
    items.reserve(chunks.size());

    for (size_t i = 0; i < chunks.size(); ++i) {
        ValidationResult val{};
        if (i < validations.size()) {
            val = validations[i];
        }
        items.push_back({chunks[i], val});
    }

    std::sort(items.begin(), items.end(), [](const ClipItem& a, const ClipItem& b) {
        return a.chunk.offset < b.chunk.offset;
    });

    int64_t baseEpoch = parseIso8601ToEpoch(recordingStartUtc);
    double cumulativeSeconds = 0.0;

    std::vector<TimelineEntry> timeline;
    timeline.reserve(items.size());

    for (const auto& item : items) {
        double dur = (item.val.duration_seconds > 0.0) ? item.val.duration_seconds : 1.0;
        int64_t startSec = baseEpoch + static_cast<int64_t>(cumulativeSeconds);
        int64_t endSec = startSec + static_cast<int64_t>(dur);
        if (endSec == startSec) endSec = startSec + 1;

        TimelineEntry entry;
        entry.clip_path = item.chunk.output_path;
        entry.estimated_start_utc = formatEpochToIso8601(startSec);
        entry.estimated_end_utc = formatEpochToIso8601(endSec);
        entry.channel_guess = -1;
        entry.offset_in_image = item.chunk.offset;
        entry.duration_seconds = item.val.duration_seconds;

        timeline.push_back(entry);
        cumulativeSeconds += dur;
    }

    return timeline;
}

std::vector<TimelineEntry> TimelineNormalizer::mergeTimelines(
    const std::vector<std::vector<TimelineEntry>>& multipleTimelines
) {
    std::vector<TimelineEntry> merged;
    for (const auto& t : multipleTimelines) {
        merged.insert(merged.end(), t.begin(), t.end());
    }

    std::sort(merged.begin(), merged.end(), [](const TimelineEntry& a, const TimelineEntry& b) {
        if (a.estimated_start_utc != b.estimated_start_utc) {
            return a.estimated_start_utc < b.estimated_start_utc;
        }
        return a.offset_in_image < b.offset_in_image;
    });

    return merged;
}

