#pragma once

#include <string>
#include <vector>
#include <cstdint>
#include "file_carver.h"
#include "clip_validator.h"

struct TimelineEntry {
    std::string clip_path;
    std::string estimated_start_utc;
    std::string estimated_end_utc;
    int channel_guess = -1;
    uint64_t offset_in_image = 0;
    double duration_seconds = 0.0;
};

class TimelineNormalizer {
public:
    TimelineNormalizer();

    std::vector<TimelineEntry> estimateRelativeTimestamp(
        const std::vector<CarvedChunk>& chunks,
        const std::vector<ValidationResult>& validations,
        const std::string& recordingStartUtc = "2026-01-01T00:00:00Z"
    );

    static std::vector<TimelineEntry> mergeTimelines(
        const std::vector<std::vector<TimelineEntry>>& multipleTimelines
    );

private:
    static int64_t parseIso8601ToEpoch(const std::string& isoStr);
    static std::string formatEpochToIso8601(int64_t epochSeconds);
};

